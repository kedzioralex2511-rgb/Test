# me_cubetest

Durchstichtest fuer die TAOM-Pipeline. Beantwortet zwei Fragen, bevor
irgendetwas anderes gebaut wird:

1. Laedt ein selbst gebautes Modell, und traegt seine Collision den Spieler?
2. Wie weit vom Nullpunkt funktioniert das noch?

## Was noch fehlt

Der Ordner `stream/` ist leer. Dort hinein muessen drei Dateien, die nur auf
einem Windows-Rechner mit Blender, Sollumz_RDR und RedM entstehen koennen:

    stream/me_testpad.ydr     Render-Mesh
    stream/me_testpad.ybn     Collision
    stream/me_testpad.ytyp    Archetyp, muss "me_testpad" heiszen

Alles andere in dieser Resource ist fertig.

## Weg dorthin

    # 1. Testobjekt bauen (erzeugt out/testpad.blend + Checker-Textur)
    blender --background --python tools/build_testcube.py -- --out out/testpad

    # 2. out/testpad.blend in Blender oeffnen:
    #    - Sollumz-Shader auf das Material 'me_testpad_mat' legen
    #    - YTYP anlegen, Archetyp exakt 'me_testpad', Asset Type Drawable,
    #      lodDist grosszuegig (z.B. 3000)
    #    - me_testpad_lod0 als ydr exportieren
    #    - me_testpad_col   als ybn exportieren
    #    - ytyp exportieren
    #    -> alles nach out/export/

    # 3. Ins RDR2-Format konvertieren
    .\tools\convert_to_rdr2.ps1 -InputPath out\export -OutputPath me_cubetest\stream

    # 4. Ordner me_cubetest auf den Server, dann
    #    ensure me_cubetest   in der server.cfg

## Testen

In der F8-Konsole:

    /mepad                          Objekt absetzen und drauf teleportieren
    /meradius 1000 2000 20000       Weltradius ausmessen
    /mepos                          aktuelle Koordinaten
    /meclear                        Testobjekte entfernen

Die Ausgabe landet ebenfalls in F8.

### /mepad

Meldet, ob das Modell streamt, ob `CreateObject` es platzieren kann und ob du
darauf stehen bleibst statt durchzufallen. Bleibst du stehen, pruefe vor Ort:

| Was                  | Soll                                      |
| -------------------- | ----------------------------------------- |
| Saeule               | geht bis Augenhoehe (1.83 m)              |
| Torbogen             | du laeufst durch ohne anzustoszen (2.10 m)|
| Checker-Feld         | 1 m, jedes 10. Feld orange                |
| Rampen 15/30/45 Grad | ab wann rutschst du ab?                   |

Das ist zugleich die Maszstabspruefung fuer alle spaeteren Bannerlord-Scenes:
die werden mit exakt demselben Faktor 1.0 importiert. Stimmt die Tuerhoehe
hier, stimmt sie dort.

### /meradius

Setzt das Objekt in wachsender Entfernung ab und teleportiert dich jeweils
darauf. Pro Distanz wird gemeldet:

- **Drift** - Abweichung zwischen gesetzter und zurueckgelesener Koordinate.
  Reine Float-Genauigkeit; waechst mit der Entfernung.
- **Absacken** - faellst du durch, fehlt die Collision.
- **in der Luft / Ground-Z** - ob die Engine dort noch Boden findet.

Am Ende steht der nutzbare Radius und der daraus folgende `scale_horizontal`
fuer `tools/config.json`. Genau diese Zahl entscheidet ueber den Maszstab der
ganzen Karte, deshalb steht der Test vor jedem Terrain-Lauf.

## Wenn /mepad nichts laedt

Das Modell wird nicht gestreamt. In dieser Reihenfolge pruefen:

1. Liegen alle drei Dateien in `stream/`?
2. Heiszt der Archetyp im ytyp exakt `me_testpad` (nicht `me_testpad_lod0`)?
3. `restart me_cubetest` auf dem Server, F8-Konsole auf Streaming-Fehler ansehen.
4. Hat CitiCon wirklich konvertiert? Eine unkonvertierte GTA-V-ydr laedt in
   RDR2 nicht, sieht aber gleich aus.
