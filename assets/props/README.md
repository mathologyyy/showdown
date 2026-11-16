# Bausteine der Umgebung

Jede Szene hier ist ein austauschbarer Baustein. `scripts/level.gd` setzt sie an die Stellen
aus seinen Tabellen; Kollision, Deckung und Abpraller rechnet der Code weiterhin mit eigenen
Quadern. Zum Verschönern den Inhalt der Szene ersetzen (Mesh-Knoten löschen, eigenes Modell
einhängen) und Maße und Ursprung beibehalten.

Der Grundriss liegt auf einem 0,5-m-Raster, Bodenflächen auf einem 1-m-Raster.

| Szene | Maß (X × Y × Z) | Ursprung | Hinweis |
|---|---|---|---|
| `wall_3m`, `wall_1m`, `wall_05m` | 3 / 1 / 0,5 × 1,6 × 0,25 m | Bodenmitte | läuft entlang X, wird für Z-Wände um 90° gedreht; längste Module zuerst |
| `wall_post` | 0,27 × 1,62 × 0,27 m | Bodenmitte | steht an jedem Wandende und füllt die Ecken |
| `floor_3x3`, `floor_3x1`, `floor_1x1` | 3×3 / 3×1 / 1×1 m, 0,1 m dick | Mitte, Oberkante bei Y = 0 | `floor_3x1` wird auch um 90° gedreht verlegt |
| `crate` | 1 × 1 × 1 m | Bodenmitte | wird auf die Maße aus `CRATES` skaliert (Höhe 0,75 m) |
| `furniture` | 1 × 1 × 1 m | Bodenmitte | wird auf die Maße aus `FURNITURE` skaliert (Höhe 1,2 m) |
| `metal_cabinet` | 1 × 1 × 1 m | Bodenmitte | wird auf die Maße aus `METAL` skaliert (Höhe 1,2 m) |
| `door_leaf` | 1 × 1 × 1 m | Mitte des Quaders | ein Türflügel, wird auf Flügelgröße skaliert |

Kiste, Möbel, Metallschrank und Türflügel sind Einheitswürfel, die gestreckt werden. Ein
Modell mit festen Proportionen sollte deshalb zu den Maßen in der Tabelle passen – oder die
Maße in `scripts/level.gd` werden an das Modell angepasst.
