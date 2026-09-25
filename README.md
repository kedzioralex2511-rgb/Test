# TAOM -> RedM

Pipeline, um die TAOM-Weltkarte (Mount & Blade II: Bannerlord) als begehbares
Terrain mit Siedlungen nach RDR2/RedM zu bringen.

## Die zentrale Entscheidung: zwei Maszstaebe

Das Terrain wird gestaucht, die Gebaeude nicht. Mittelerde ist ~1500 km breit,
RDR2 bietet ~15 x 20 km nutzbaren Raum - also Faktor 1:100 fuer die Karte.
Gebaeude bleiben dagegen 1:1, weil der Spieler 1:1 bleibt: eine Tuer, die in
Bannerlord bis zum Kopf geht, geht auch in RDR2 bis zum Kopf.

| Was                                   | Faktor          |
| ------------------------------------- | --------------- |
| Heightmap horizontal                  | 0.01            |
| Heightmap vertikal                    | 0.0333 (~3x ueberhoeht) |
| Siedlungspositionen aus settlements.xml | 0.01          |
| Gebaeude-Meshes                       | **1.0 - nie skalieren** |

Bannerlord und RDR2 nutzen beide Meter und eine ~1.8-m-Spielfigur, deshalb ist
der Scene-Import faktorfrei. Beim FBX-Export nur auf Achsen achten: Bannerlord
ist Y-up, Blender/RDR2 sind Z-up. Unit Scale bleibt 1.0.

## Konsequenz: Pads

Ein 500-m-Stadtgrundriss ueberdeckt bei 1:100 ganze 50 km Originalkarte. Ueber
50 km variiert die Hoehe um mehrere hundert Meter. Ohne Einebnung steht die
Stadt in einem Hang, der durch das Stadttor laeuft. `build_terrain.py` ebnet
deshalb pro Siedlung eine Plattform mit weichem Uebergangsring ein, *bevor*
gekachelt wird.

## Konsequenz: Siedlungen ausduennen

Bei 30 Siedlungen auf 225 km^2 sind das ~2.7 km Abstand - eine 500-m-Scene
passt locker. Setzt man dagegen alle TAOM-Siedlungen, ueberlappen sich die
Dorfcluster nach der Stauchung. Gestaffelt vorgehen:

| Stufe       | Behandlung                     | Footprint |
| ----------- | ------------------------------ | --------- |
| Grossstaedte| volle Scene, begehbar          | 400-600 m |
| Burgen      | volle Scene                    | 200-300 m |
| Doerfer     | 5-15 handplatzierte Props      | 60-100 m  |
| Rest        | Landmark-Prop oder weglassen   | -         |

## Reihenfolge

1. **Wuerfel-Test.** 256-m-Wuerfel: Blender -> Sollumz_RDR -> CitiCon -> Server,
   draufstellen. Faellt das durch, ist alles andere verlorene Arbeit.
2. **Weltradius messen.** Objekte in Schritten 1k/2k/4k/8k/12k/16k vom Nullpunkt
   platzieren, jeweils Collision, Treffer und Flimmern pruefen.
3. **Maszstab festlegen** aus dem gemessenen Radius (Default oben: 1:100).
4. **Eine Terrain-Kachel** bauen und ingame pruefen: `--only 0_0`.
5. **Ein einzelnes Gebaeude** end-to-end, Tuerhoehe gegen 1.83-m-Referenz messen.
6. **Eine komplette Siedlung** inkl. Pad, LOD und Collision.
7. Erst dann der volle Lauf.

## Durchstichtest: `me_cubetest/`

Fertige RedM-Resource. Ordner auf den Server, `ensure me_cubetest`, laeuft
sofort - Schritt 1 braucht kein eigenes Asset.

    /mestock                      ladbares RDR2-Stock-Prop suchen
    /meradius 1000 2000 20000     Weltradius messen  -> ergibt scale_horizontal
    /mepad                        eigene Pipeline pruefen (braucht stream/)

Schritt 0 vorweg: eine fertige Community-Map einwerfen und sehen, ob sie
laedt. Damit ist geklaert, ob spaetere Fehler am Server oder an der eigenen
Pipeline liegen. Details und Links in `me_cubetest/README.md`.

## Terrain-Generator

    blender --background --python tools/build_terrain.py -- \
        --config tools/config.json --dry-run     # nur Statistik
    blender --background --python tools/build_terrain.py -- \
        --config tools/config.json --only 0_0    # eine Kachel
    blender --background --python tools/build_terrain.py -- \
        --config tools/config.json               # alles

Die Kachelgroesse wird auf ein Vielfaches des groebsten LOD-Strides eingerastet
und die Heightmap am Rand repliziert, damit jede Kachel - auch die am Rand -
alle LOD-Stufen bekommt. Der `--dry-run` meldet die tatsaechliche Kachelgroesse.

Pro Kachel entsteht eine `.blend` mit `_lod0/_lod1/_lod2` (-> ydr) und `_col`
(-> ybn). Randvertices werden aus globalen Gitterindizes berechnet, damit
Nachbarkacheln bitgenau zusammenpassen; ein Skirt nach unten deckt Risse
zwischen unterschiedlichen LOD-Stufen ab.

## Offene Punkte

- `tag_sollum()` in `build_terrain.py`: die Sollum-Typbezeichner gegen die
  installierte Sollumz_RDR-Version pruefen. Der RDR-Fork ist experimentell.
- LOD-Slots weist Sollumz selbst zu; das Skript liefert nur benannte Objekte.
- Konvertierung nach RDR2 laeuft ueber CitiCon, skriptbar aus dem RedM.app-Ordner:
  `CitiCon.com formats:convert <datei...>` (Ausgabe `<name>_nya.<ext>`).
- Originalwelt zunaechst *nicht* loeschen - Mittelerde ueber die RDR2-Wasserebene
  legen (`origin.z`). Das Loeschen ist ein spaeterer Optimierungsschritt.
- Navmesh (ynv) gibt es nicht; NPC-Wegfindung auf dem Terrain funktioniert nicht.
- Innenraeume sind in Bannerlord getrennte Scenes - Tueren fuehren zunaechst nirgendwohin.

## Rechtliches

TAOM-Assets gehoeren dem Mod-Team. Fuer eine Veroeffentlichung braucht es deren
Einverstaendnis; RDR2-Texturen per Hash referenzieren statt mitliefern.
