# me_cubetest

Durchstichtest fuer die TAOM-Pipeline. Drei Tests, von billig nach teuer -
jeder beantwortet genau eine Frage, damit ein Fehlschlag eindeutig zuzuordnen ist.

| Schritt | Test                    | Braucht          | Beweist                     |
| ------- | ----------------------- | ---------------- | --------------------------- |
| 0       | fremde Map einwerfen    | nur Download     | Server + Streaming in Ordnung |
| 1       | `/meradius`             | **nichts**       | nutzbarer Weltradius, Maszstab |
| 2       | `/mepad`                | Blender + CitiCon| die eigene Pipeline         |

## Sofort loslegen

Ordner auf den Server, `ensure me_cubetest` in die server.cfg, fertig. Die
Resource laeuft ohne jedes eigene Asset - Schritt 1 nutzt RDR2-Stock-Props.

In der F8-Konsole:

    /mestock                                   ladbares Stock-Modell suchen
    /meradius [start] [schritt] [max] [modell] Weltradius messen
    /metest <name>                             einzelnen Modellnamen pruefen
    /mepad                                     eigene Pipeline pruefen
    /mepos    /meclear

## Schritt 0 - laedt der Server ueberhaupt gestreamte Assets?

Bevor du irgendetwas selbst baust: eine fertige Community-Map einwerfen und
sehen, ob sie erscheint.

- https://github.com/joniinnanen/RedM-maps
- https://github.com/Rexshack-RedM/redm-ymaps
- https://github.com/blnstudio/redm-free-maps

Laedt sie -> Server, fxmanifest und Streaming sind in Ordnung, spaetere Fehler
liegen an deiner Pipeline. Laedt sie nicht -> erst die Serverkonfiguration
reparieren, sonst suchst du spaeter am falschen Ende.

## Schritt 1 - Weltradius

    /meradius 1000 2000 20000

Setzt ein Prop in wachsender Entfernung ab, teleportiert dich hin und meldet
pro Distanz:

- **Drift Objekt / Spieler** - Abweichung zwischen gesetzter und
  zurueckgelesener Koordinate. Reine Float-Praezision, waechst linear mit der
  Entfernung vom Nullpunkt.
- **existiert / sichtbar** - ob die Engine das Objekt dort noch fuehrt.
- **Absacken** - nur mit eigenem Testpad aussagekraeftig.

Findet kein Stock-Modell: `/mestock` zeigt, welche Kandidaten scheitern, und
mit `/metest <name>` pruefst du eigene. Namenslisten auf
[redlookup.com/objects](https://redlookup.com/objects/) und in der
[RDR2Mods-Objektliste](https://www.rdr2mods.com/wiki/pages/list-of-object-models-in-rdr2-r16/).
Einen gefundenen Namen kannst du direkt uebergeben:

    /meradius 1000 2000 20000 p_door01x

Am Ende steht der nutzbare Radius und der daraus folgende `scale_horizontal`
fuer `tools/config.json`. Diese Zahl entscheidet ueber den Maszstab der ganzen
Karte, deshalb steht der Test vor jedem Terrain-Lauf.

Ein kleines Stock-Prop misst Praezision und Persistenz, aber nicht, ob dich
etwas traegt. Fuer die Collision-Frage braucht es Schritt 2.

## Schritt 2 - die eigene Pipeline

Ein heruntergeladenes Modell beweist, dass *fremde* Toolchains funktionieren.
Ueber deine sagt es nichts - und deine muss am Ende 1024 Terrain-Kacheln
durchschleusen. Deshalb einmal selbst durch die ganze Kette:

    # Testobjekt bauen (erzeugt out/testpad.blend + Checker-Textur)
    blender --background --python tools/build_testcube.py -- --out out/testpad

    # in Blender oeffnen:
    #  - Sollumz-Shader auf das Material 'me_testpad_mat'
    #  - YTYP anlegen, Archetyp exakt 'me_testpad', Asset Type Drawable,
    #    lodDist grosszuegig (z.B. 3000)
    #  - me_testpad_lod0 -> ydr,  me_testpad_col -> ybn,  ytyp exportieren
    #  -> alles nach out/export/

    .\tools\convert_to_rdr2.ps1 -InputPath out\export -OutputPath me_cubetest\stream

Danach in `fxmanifest.lua` die beiden auskommentierten Zeilen einkommentieren
(`files` und `data_file`), Resource neu starten, `/mepad`.

Stehst du drauf, pruefe vor Ort:

| Was                  | Soll                                       |
| -------------------- | ------------------------------------------ |
| Saeule               | geht bis Augenhoehe (1.83 m)               |
| Torbogen             | du laeufst durch ohne anzustoszen (2.10 m) |
| Checker-Feld         | 1 m, jedes 10. Feld orange                 |
| Rampen 15/30/45 Grad | ab wann rutschst du ab?                    |

Das ist zugleich die Maszstabspruefung fuer alle spaeteren Bannerlord-Scenes:
die werden mit exakt demselben Faktor 1.0 importiert. Stimmt die Tuerhoehe
hier, stimmt sie dort. Die Rampen sagen dir, ab welchem Winkel die Collision
den Spieler abrutschen laesst - die Zahl brauchst du spaeter fuer die
Uebergangsringe der Siedlungs-Pads.

## Wenn /mepad nichts laedt

In dieser Reihenfolge pruefen:

1. Sind die beiden Zeilen in `fxmanifest.lua` einkommentiert?
2. Liegen alle drei Dateien in `stream/`?
3. Heiszt der Archetyp im ytyp exakt `me_testpad` (nicht `me_testpad_lod0`)?
4. Hat CitiCon wirklich konvertiert? Eine unkonvertierte GTA-V-ydr sieht
   identisch aus, laedt in RDR2 aber nicht.
5. Laedt Schritt 0 noch? Wenn nicht, liegt es am Server, nicht an dir.
