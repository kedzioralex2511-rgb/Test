"""
Erzeugt aus einer Heightmap gekachelte Terrain-Meshes fuer RDR2/RedM.

Aufruf (headless):
    blender --background --python tools/build_terrain.py -- --config tools/config.json

Pro Kachel entsteht eine .blend mit:
    <tile>_lod0 / _lod1 / _lod2   Render-Meshes (fuer ydr)
    <tile>_col                    Collision-Mesh (fuer ybn)

Die Kachelraender werden aus globalen Gitterindizes berechnet, nicht pro Kachel
lokal - dadurch sind benachbarte Randvertices bitgenau identisch und es gibt
keine Nahtluecken. Gegen LOD-Uebergaenge zwischen Nachbarkacheln gibt es
zusaetzlich einen Skirt (Schuerze) nach unten.
"""

import argparse
import json
import math
import os
import sys

import numpy as np

try:
    import bpy
except ImportError:  # erlaubt --dry-run ausserhalb von Blender
    bpy = None


# --------------------------------------------------------------------------
# Sollumz-Anbindung
#
# ACHTUNG: Diese Bezeichner gegen die installierte Sollumz_RDR-Version pruefen.
# Der RDR-Fork weicht stellenweise vom Upstream ab. Wenn das Setzen scheitert,
# laeuft das Skript weiter und meldet es - die .blend ist dann trotzdem
# brauchbar, die Typen setzt du einmalig von Hand.
# --------------------------------------------------------------------------
SOLLUM_DRAWABLE_MODEL = "sollumz_drawable_model"
SOLLUM_BOUND_GEOMETRY_BVH = "sollumz_bound_geometrybvh"


def tag_sollum(obj, sollum_type):
    try:
        obj.sollum_type = sollum_type
    except Exception as exc:
        print(f"  [warn] sollum_type '{sollum_type}' auf {obj.name} fehlgeschlagen: {exc}")


# --------------------------------------------------------------------------
# Heightmap
# --------------------------------------------------------------------------
def load_heightmap(path, raw_size=None):
    """Gibt ein float-Array in [0,1] zurueck, Zeile 0 = Nord."""
    ext = os.path.splitext(path)[1].lower()

    if ext in (".r16", ".raw"):
        if not raw_size:
            raise SystemExit("Fuer .r16/.raw muss heightmap_size_px gesetzt sein.")
        w, h = raw_size
        data = np.fromfile(path, dtype="<u2")
        if data.size != w * h:
            raise SystemExit(f"{path}: {data.size} Samples, erwartet {w*h}.")
        return data.reshape(h, w).astype(np.float64) / 65535.0

    if bpy is None:
        raise SystemExit("Bildformate brauchen Blender; nutze .r16 fuer --dry-run.")

    img = bpy.data.images.load(path)
    w, h = img.size
    buf = np.empty(w * h * 4, dtype=np.float32)
    img.pixels.foreach_get(buf)
    bpy.data.images.remove(img)
    # Blender liefert bottom-up -> umdrehen, damit Zeile 0 Nord ist.
    return np.flipud(buf.reshape(h, w, 4)[:, :, 0].astype(np.float64))


def carve_pads(height_m, cfg):
    """Ebnet Bauflaechen fuer 1:1-Siedlungsscenes ein.

    Ohne diesen Schritt steht eine 500-m-Stadt auf gestauchtem Terrain in einem
    Hang mit zweistelligem Hoehenunterschied quer durch den Grundriss.
    """
    pads = cfg.get("pads") or []
    if not pads:
        return height_m

    h, w = height_m.shape
    m_per_px_x = cfg["world_size_m"][0] / w
    m_per_px_y = cfg["world_size_m"][1] / h

    # Pixelkoordinaten des Gitters, in Originalmetern
    px = (np.arange(w) + 0.5) * m_per_px_x
    py = (np.arange(h) + 0.5) * m_per_px_y
    gx, gy = np.meshgrid(px, py)

    out = height_m.copy()
    for pad in pads:
        cx, cy = pad["x_m"], pad["y_m"]
        # Radien sind in Spielmetern angegeben -> zurueck auf Originalmeter
        r = pad["radius_m"] / cfg["scale_horizontal"]
        f = pad.get("falloff_m", pad["radius_m"]) / cfg["scale_horizontal"]

        dist = np.hypot(gx - cx, gy - cy)
        inner = dist <= r
        if not inner.any():
            print(f"  [warn] Pad '{pad.get('name','?')}' liegt ausserhalb der Karte.")
            continue

        target = pad.get("height_m")
        if target is None:
            target = float(np.median(out[inner]))

        # smoothstep von 1 (innen) auf 0 (ausserhalb r+f)
        t = np.clip((dist - r) / max(f, 1e-6), 0.0, 1.0)
        weight = 1.0 - (t * t * (3.0 - 2.0 * t))
        out = out * (1.0 - weight) + target * weight
        print(f"  Pad '{pad.get('name','?')}' auf {target:.1f} m geebnet "
              f"(r={pad['radius_m']} m Spielmass)")
    return out


# --------------------------------------------------------------------------
# Mesh-Bau
# --------------------------------------------------------------------------
def build_grid(heights_game, i0, j0, n, stride, step_m, origin, skirt_depth):
    """Baut ein (n/stride)^2-Quadgitter. Positionen kommen aus globalen Indizes,
    damit Nachbarkacheln exakt dieselben Randvertices haben."""
    idx_i = np.arange(i0, i0 + n + 1, stride)
    idx_j = np.arange(j0, j0 + n + 1, stride)
    ni, nj = len(idx_i) - 1, len(idx_j) - 1

    zz = heights_game[np.ix_(idx_j, idx_i)]
    xx = origin[0] + idx_i * step_m
    yy = origin[1] - idx_j * step_m  # Zeile 0 = Nord -> Y nach Sueden fallend

    gx, gy = np.meshgrid(xx, yy)
    verts = np.stack([gx.ravel(), gy.ravel(), (zz + origin[2]).ravel()], axis=1)

    w = ni + 1
    a = (np.arange(nj)[:, None] * w + np.arange(ni)[None, :]).ravel()
    quads = np.stack([a, a + 1, a + w + 1, a + w], axis=1)

    uv_scale = 1.0 / max(step_m * stride * 8.0, 1e-6)  # ~8 Quads pro Texturkachel
    uvs = np.stack([gx.ravel() * uv_scale, gy.ravel() * uv_scale], axis=1)

    if skirt_depth > 0:
        verts, quads, uvs = add_skirt(verts, quads, uvs, ni, nj, skirt_depth)

    return verts, quads, uvs


def add_skirt(verts, quads, uvs, ni, nj, depth):
    """Haengt eine Schuerze an den Kachelrand - schliesst Risse zwischen
    Nachbarkacheln, die auf unterschiedlichen LOD-Stufen streamen."""
    w = ni + 1
    ring = (
        [j * 0 + i for i in range(ni + 1)]                       # Nordkante
        + [j * w + ni for j in range(1, nj + 1)]                 # Ostkante
        + [nj * w + i for i in range(ni - 1, -1, -1)]            # Suedkante
        + [j * w + 0 for j in range(nj - 1, 0, -1)]              # Westkante
    )
    ring = np.array(ring, dtype=np.int64)
    base = len(verts)

    skirt_verts = verts[ring].copy()
    skirt_verts[:, 2] -= depth
    skirt_uvs = uvs[ring].copy()

    m = len(ring)
    k = np.arange(m)
    kn = (k + 1) % m
    skirt_quads = np.stack([ring[k], ring[kn], base + kn, base + k], axis=1)

    return (
        np.concatenate([verts, skirt_verts]),
        np.concatenate([quads, skirt_quads]),
        np.concatenate([uvs, skirt_uvs]),
    )


def make_object(name, verts, quads, uvs, mat_idx=None, materials=()):
    mesh = bpy.data.meshes.new(name)
    nv, nq = len(verts), len(quads)

    mesh.vertices.add(nv)
    mesh.vertices.foreach_set("co", verts.astype(np.float32).ravel())
    mesh.loops.add(nq * 4)
    mesh.loops.foreach_set("vertex_index", quads.astype(np.int32).ravel())
    mesh.polygons.add(nq)
    mesh.polygons.foreach_set("loop_start", (np.arange(nq) * 4).astype(np.int32))
    mesh.polygons.foreach_set("loop_total", np.full(nq, 4, dtype=np.int32))

    uv_layer = mesh.uv_layers.new(name="UVMap")
    uv_layer.data.foreach_set("uv", uvs[quads.ravel()].astype(np.float32).ravel())

    for mat in materials:
        mesh.materials.append(mat)
    if mat_idx is not None and materials:
        mesh.polygons.foreach_set("material_index", mat_idx.astype(np.int32))

    mesh.update()
    mesh.validate()

    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    return obj


def biome_materials(cfg):
    """Ein Material je Biom. Die Zuordnung auf RDR2-Shader passiert spaeter in
    Sollumz - hier zaehlt nur, dass die Slots pro Kachel stimmen."""
    mats = []
    for biome in cfg.get("biomes", []):
        mat = bpy.data.materials.get(biome["name"]) or bpy.data.materials.new(biome["name"])
        mat.diffuse_color = (*biome["rgb"], 1.0)
        mats.append(mat)
    return mats


def sample_biomes(mask, cfg, i0, j0, n, stride):
    """Weist jedem Quad den Biom-Index der naechstliegenden Palettenfarbe zu."""
    palette = np.array([b["rgb"] for b in cfg["biomes"]])
    idx_i = np.arange(i0, i0 + n, stride) + stride // 2
    idx_j = np.arange(j0, j0 + n, stride) + stride // 2
    idx_i = np.clip(idx_i, 0, mask.shape[1] - 1)
    idx_j = np.clip(idx_j, 0, mask.shape[0] - 1)

    cols = mask[np.ix_(idx_j, idx_i)].reshape(-1, 3)
    d = ((cols[:, None, :] - palette[None, :, :]) ** 2).sum(axis=2)
    return d.argmin(axis=1)


# --------------------------------------------------------------------------
def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    ap = argparse.ArgumentParser()
    ap.add_argument("--config", required=True)
    ap.add_argument("--only", help="nur diese Kachel bauen, z.B. 3_7 (fuer den ersten Test)")
    ap.add_argument("--dry-run", action="store_true", help="nur Statistik, keine Meshes")
    args = ap.parse_args(argv)

    with open(args.config) as fh:
        cfg = json.load(fh)

    hm = load_heightmap(cfg["heightmap"], cfg.get("heightmap_size_px"))
    h_px, w_px = hm.shape
    print(f"Heightmap {w_px}x{h_px}")

    lo, hi = cfg["height_range_m"]
    height_m = lo + hm * (hi - lo)
    height_m = carve_pads(height_m, cfg)

    sh, sv = cfg["scale_horizontal"], cfg["scale_vertical"]
    heights_game = height_m * sv

    world_x = cfg["world_size_m"][0] * sh
    world_y = cfg["world_size_m"][1] * sh
    step_m = world_x / (w_px - 1)
    tile = cfg["tile_size_m"]
    n = int(round(tile / step_m))
    if n < 4:
        raise SystemExit(f"tile_size_m zu klein: nur {n} Quads pro Kachel.")

    tiles_x = math.ceil((w_px - 1) / n)
    tiles_y = math.ceil((h_px - 1) / n)

    print(f"Weltgroesse im Spiel : {world_x/1000:.2f} x {world_y/1000:.2f} km")
    print(f"Sampleabstand        : {step_m:.2f} m")
    print(f"Kacheln              : {tiles_x} x {tiles_y} = {tiles_x*tiles_y}")
    print(f"Quads je Kachel LOD0 : {n*n}")
    print(f"Hoehenbereich        : {heights_game.min():.1f} .. {heights_game.max():.1f} m")

    if args.dry_run:
        return

    origin = cfg.get("origin", [0, 0, 0])
    strides = cfg.get("lod_strides", [1, 4, 16])
    col_stride = cfg.get("collision_stride", 1)
    skirt = cfg.get("skirt_depth_m", 8.0)
    out_dir = cfg["output_dir"]
    os.makedirs(out_dir, exist_ok=True)

    mask = None
    if cfg.get("biome_mask"):
        mask = load_biome_mask(cfg["biome_mask"])

    for tj in range(tiles_y):
        for ti in range(tiles_x):
            name = f"{cfg.get('prefix','me')}_{ti}_{tj}"
            if args.only and args.only != f"{ti}_{tj}":
                continue

            bpy.ops.wm.read_factory_settings(use_empty=True)
            mats = biome_materials(cfg)

            i0, j0 = ti * n, tj * n
            n_eff = min(n, w_px - 1 - i0, h_px - 1 - j0)
            if n_eff < 1:
                continue

            for lod, stride in enumerate(strides):
                if n_eff % stride:
                    print(f"  [warn] {name}: stride {stride} teilt {n_eff} nicht, LOD{lod} uebersprungen")
                    continue
                v, q, uv = build_grid(heights_game, i0, j0, n_eff, stride,
                                      step_m, origin, skirt if lod == 0 else skirt * stride)
                mi = sample_biomes(mask, cfg, i0, j0, n_eff, stride) if mask is not None else None
                if mi is not None:
                    mi = np.concatenate([mi, np.zeros(len(q) - len(mi), dtype=mi.dtype)])
                obj = make_object(f"{name}_lod{lod}", v, q, uv, mi, mats)
                tag_sollum(obj, SOLLUM_DRAWABLE_MODEL)

            v, q, uv = build_grid(heights_game, i0, j0, n_eff, col_stride,
                                  step_m, origin, skirt)
            col = make_object(f"{name}_col", v, q, uv)
            tag_sollum(col, SOLLUM_BOUND_GEOMETRY_BVH)

            path = os.path.join(out_dir, f"{name}.blend")
            bpy.ops.wm.save_as_mainfile(filepath=path)
            print(f"  {name}: {len(q)} Quads Collision -> {path}")


def load_biome_mask(path):
    img = bpy.data.images.load(path)
    w, h = img.size
    buf = np.empty(w * h * 4, dtype=np.float32)
    img.pixels.foreach_get(buf)
    bpy.data.images.remove(img)
    return np.flipud(buf.reshape(h, w, 4)[:, :, :3].astype(np.float64))


if __name__ == "__main__":
    main()
