"""
Baut das Testobjekt fuer den ersten Durchstich durch die Toolchain.

    blender --background --python tools/build_testcube.py -- --out out/testpad

Erzeugt out/testpad.blend und out/me_testpad_checker.png.

Das Objekt ist bewusst kein nackter Wuerfel, sondern beantwortet beim
Draufstehen gleich die Maszstabsfrage:

    Plattform 256 x 256 m, 2 m dick, Checker-Textur mit 1-m-Feldern
    Saeule     1.83 m hoch  -> Augenhoehe des Spielers, Sichtpruefung
    Torbogen   2.10 m lichte Hoehe -> "Tuer geht bis zum Kopf"
    Treppe     5 Stufen a 0.30 m / 18 Grad -> Steigungs-Collision
    Rampen     15 / 30 / 45 Grad -> ab wann rutscht man ab

Wenn die Saeule dem Spieler bis zu den Augen geht und du unter dem Torbogen
durchlaeufst ohne anzustoszen, stimmt der Maszstab fuer alle spaeteren
Bannerlord-Scenes - die werden mit exakt demselben Faktor 1.0 importiert.
"""

import argparse
import math
import os
import struct
import sys
import zlib

try:
    import bpy
    import bmesh
except ImportError:
    bpy = None


# Gegen die installierte Sollumz_RDR-Version pruefen (siehe build_terrain.py).
SOLLUM_DRAWABLE_MODEL = "sollumz_drawable_model"
SOLLUM_BOUND_GEOMETRY_BVH = "sollumz_bound_geometrybvh"

PLAYER_EYE_M = 1.83
DOOR_CLEAR_M = 2.10
PAD_SIZE_M = 256.0
PAD_THICK_M = 2.0


def tag_sollum(obj, sollum_type):
    try:
        obj.sollum_type = sollum_type
    except Exception as exc:
        print(f"  [warn] sollum_type '{sollum_type}' auf {obj.name}: {exc}")


def write_checker_png(path, cells=256, px_per_cell=2):
    """1 Feld = 1 Meter. Damit laesst sich der Maszstab ingame abzaehlen.
    Jedes 10. Feld ist heller - so sieht man 10-m-Schritte auf einen Blick."""
    size = cells * px_per_cell
    rows = bytearray()
    for y in range(size):
        cy = y // px_per_cell
        rows.append(0)  # PNG-Filter: None
        for x in range(size):
            cx = x // px_per_cell
            dark = (cx + cy) % 2 == 0
            decade = cx % 10 == 0 or cy % 10 == 0
            v = 200 if decade else (90 if dark else 150)
            rows += bytes((v, v, v)) if not decade else bytes((v, 140, 60))

    def chunk(tag, data):
        c = tag + data
        return struct.pack(">I", len(data)) + c + struct.pack(">I", zlib.crc32(c))

    png = (b"\x89PNG\r\n\x1a\n"
           + chunk(b"IHDR", struct.pack(">IIBBBBB", size, size, 8, 2, 0, 0, 0))
           + chunk(b"IDAT", zlib.compress(bytes(rows), 6))
           + chunk(b"IEND", b""))
    with open(path, "wb") as fh:
        fh.write(png)
    print(f"  Checker-Textur ({cells} m, 1 m je Feld) -> {path}")


def box(name, size, loc, mat=None):
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=loc)
    obj = bpy.context.active_object
    obj.name = name
    obj.scale = size
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    if mat:
        obj.data.materials.append(mat)
    return obj


def ramp(name, length, width, angle_deg, loc, mat=None):
    """Keil mit definiertem Steigungswinkel - zum Testen, ab wann die
    Collision den Spieler abrutschen laesst."""
    h = length * math.tan(math.radians(angle_deg))
    mesh = bpy.data.meshes.new(name)
    bm = bmesh.new()
    w = width / 2.0
    v = [bm.verts.new(p) for p in (
        (0, -w, 0), (length, -w, 0), (length, -w, h),
        (0, w, 0), (length, w, 0), (length, w, h),
    )]
    bm.faces.new((v[0], v[1], v[2]))
    bm.faces.new((v[5], v[4], v[3]))
    bm.faces.new((v[0], v[2], v[5], v[3]))
    bm.faces.new((v[1], v[4], v[5], v[2]))
    bm.faces.new((v[0], v[3], v[4], v[1]))
    bm.to_mesh(mesh)
    bm.free()
    obj = bpy.data.objects.new(name, mesh)
    obj.location = loc
    bpy.context.collection.objects.link(obj)
    if mat:
        obj.data.materials.append(mat)
    return obj


def build(out_base):
    bpy.ops.wm.read_factory_settings(use_empty=True)

    tex_path = os.path.abspath(out_base + "_checker.png")
    write_checker_png(tex_path, cells=int(PAD_SIZE_M))

    mat = bpy.data.materials.new("me_testpad_mat")
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes["Principled BSDF"]
    img = mat.node_tree.nodes.new("ShaderNodeTexImage")
    img.image = bpy.data.images.load(tex_path)
    mat.node_tree.links.new(bsdf.inputs["Base Color"], img.outputs["Color"])

    parts = []

    pad = box("pad", (PAD_SIZE_M, PAD_SIZE_M, PAD_THICK_M),
              (0, 0, -PAD_THICK_M / 2), mat)
    # 1 UV-Kachel je Meter
    for loop in pad.data.uv_layers.active.data:
        loop.uv = (loop.uv[0] * PAD_SIZE_M, loop.uv[1] * PAD_SIZE_M)
    parts.append(pad)

    # Augenhoehe: Saeule muss dem Spieler bis zu den Augen gehen
    parts.append(box("ref_eye", (0.4, 0.4, PLAYER_EYE_M),
                     (2, 0, PLAYER_EYE_M / 2), mat))

    # Torbogen mit 2.10 m lichter Hoehe - "Tuer geht bis zum Kopf"
    post_h = DOOR_CLEAR_M
    parts.append(box("door_l", (0.3, 0.3, post_h), (6, -0.75, post_h / 2), mat))
    parts.append(box("door_r", (0.3, 0.3, post_h), (6, 0.75, post_h / 2), mat))
    parts.append(box("door_top", (0.3, 1.8, 0.3),
                     (6, 0, post_h + 0.15), mat))

    # Treppe: 5 Stufen a 0.30 m Hoehe / 0.30 m Tiefe
    for i in range(5):
        parts.append(box(f"step_{i}", (0.30, 2.0, 0.30 * (i + 1)),
                         (10 + i * 0.30, 0, 0.30 * (i + 1) / 2), mat))

    # Rampen: wo endet begehbar?
    for k, ang in enumerate((15, 30, 45)):
        parts.append(ramp(f"ramp_{ang}", 8.0, 3.0, ang, (16, k * 5 - 5, 0), mat))

    for obj in parts:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = parts[0]
    bpy.ops.object.join()

    drawable = bpy.context.active_object
    drawable.name = "me_testpad_lod0"
    tag_sollum(drawable, SOLLUM_DRAWABLE_MODEL)

    col = drawable.copy()
    col.data = drawable.data.copy()
    col.name = "me_testpad_col"
    bpy.context.collection.objects.link(col)
    tag_sollum(col, SOLLUM_BOUND_GEOMETRY_BVH)

    blend_path = os.path.abspath(out_base + ".blend")
    os.makedirs(os.path.dirname(blend_path), exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=blend_path)
    print(f"  Testobjekt ({len(drawable.data.polygons)} Faces) -> {blend_path}")
    print("\nNaechster Schritt: in Blender oeffnen, Sollumz-Shader auf das")
    print("Material legen, YTYP mit Archetyp 'me_testpad' anlegen, dann")
    print("ydr + ybn + ytyp exportieren und durch tools/convert_to_rdr2.ps1 jagen.")


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else sys.argv[1:]
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default="out/testpad")
    args = ap.parse_args(argv)
    if bpy is None:
        raise SystemExit("Dieses Skript muss in Blender laufen:\n"
                         "  blender --background --python tools/build_testcube.py -- --out out/testpad")
    build(args.out)


if __name__ == "__main__":
    main()
