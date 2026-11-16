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
| `crate_small` | 0,9 × 0,75 × 0,45 m | Bodenmitte | Kiste, quer im Flur |
| `crate_long` | 1,0 × 0,75 × 0,5 m | Bodenmitte | Kiste, im Level um 90° gedreht |
| `sofa` | 2,4 × 1,2 × 0,8 m | Bodenmitte | |
| `coffee_table` | 1,3 × 1,2 × 0,8 m | Bodenmitte | |
| `shelf` | 0,5 × 1,2 × 1,8 m | Bodenmitte | |
| `bed` | 2,0 × 1,2 × 2,0 m | Bodenmitte | |
| `wardrobe` | 0,7 × 1,2 × 0,8 m | Bodenmitte | |
| `kitchen_island` | 2,0 × 1,2 × 0,9 m | Bodenmitte | |
| `kitchen_counter` | 4,5 × 1,2 × 0,6 m | Bodenmitte | |
| `desk` | 2,0 × 1,2 × 0,8 m | Bodenmitte | |
| `locker` | 0,45 × 1,2 × 1,1 m | Bodenmitte | Metall: Kugeln prallen ab |
| `radiator` | 0,35 × 1,2 × 1,2 m | Bodenmitte | Metall |
| `fridge` | 0,7 × 1,2 × 0,7 m | Bodenmitte | Metall |
| `filing_cabinet` | 0,7 × 1,2 × 1,5 m | Bodenmitte | Metall |
| `safe` | 0,5 × 1,2 × 1,4 m | Bodenmitte | Metall |
| `door_leaf` | 0,855 × 1,6 × 0,12 m | Mitte des Quaders | ein Türflügel, entlang X; für Türen in Z-Wänden um 90° gedreht |

Kisten, Möbel und Metall-Objekte werden **nicht gestreckt**: Jede Szene ist in genau der Größe
gebaut, die in ihrer Tabellenzeile in `scripts/level.gd` steht (Breite, Tiefe; die Höhe ist
1,2 m für Möbel und Metall, 0,75 m für Kisten). Wer ein Modell mit anderen Maßen einsetzt,
trägt die neue Breite und Tiefe in der Tabellenzeile ein, damit die Kollision dazu passt.

Die Höhe der Kollision ist für alle Möbel gleich (volle Deckung). Ein niedrig aussehendes
Möbel, etwa ein flacher Couchtisch, deckt im Spiel trotzdem wie ein hohes.

Ein neues Möbel: Szene hier anlegen und eine Zeile in `FURNITURE`, `METAL` oder `CRATES`
ergänzen (`[x, z, Breite, Tiefe, "szenenname"]`, optional mit Drehung in Grad).
