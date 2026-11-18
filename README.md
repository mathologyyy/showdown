# Showdown – "Go Go Go" Taktik-Prototyp

Top-down 3D-Taktikspiel mit Zeitlupe beim Zielen: Ein 3-köpfiges SEK stürmt eine Wohnung.
Godot **4.7** (entwickelt und getestet mit 4.7.2 stable), reines GDScript.

## Starten

1. Godot 4.7.x öffnen → **Importieren** → `project.godot` in diesem Ordner wählen.
2. **F5** drücken (Hauptszene ist `scenes/main.tscn`).

Oder direkt im Terminal: `godot --path .`

Beim Start erscheint das **Hauptmenü** („Spiel starten“, „So wird gespielt“, „Beenden“). Vor der
ersten Mission erklären drei kurze Tafeln das Runden-Prinzip; jede Taste oder ein Klick blättert
weiter, Esc bzw. Start überspringt sie. Über das Pausemenü kommt man zurück ins Hauptmenü.

## Steuerung

| Tastatur / Maus | Controller | Wirkung |
|---|---|---|
| W A S D | Linker Stick | Officer bewegen |
| Maus | Rechter Stick | Blickrichtung (folgt verzögert). Am Controller schaut der Officer bei ruhendem rechten Stick in Laufrichtung. |
| Rechte Maustaste (halten) | LT oder LB (halten) | Waffe anlegen: erst dann gibt es Laser, Streubogen und Schuss; währenddessen läuft die Zeitlupe |
| Linksklick | RT oder RB | Schießen, nur mit angelegter Waffe (beendet den Zug) |
| Leertaste | A | Aktionstaste: Spezialfähigkeit des Officers (Granate und Schild beenden den Zug) |
| Umschalttaste | Y | Hechtsprung (alle Officer) |
| C / Strg | B | Ducken / Aufstehen (umschalten) |
| E | X | Tür öffnen (in Reichweite erscheint ein Hinweis an der Tür) |
| 1 / 2 oder Mausrad | Steuerkreuz ↓ / ↑ | Zeitlupe langsamer / schneller |
| R | A | nach Fehlschlag: Durchlauf wiederholen · im Ergebnis: Replay erneut |
| N | Y | neue Mission (nach Fehlschlag oder Ergebnis) |
| Esc | Start | Pausemenü (Fortsetzen / Zug beenden / Mission neu starten / Hauptmenü / Beenden) |

Die Controller-Tasten sind nach ihrer **Lage** benannt wie beim Xbox-Pad (A unten, B rechts,
X links, Y oben). Das Spiel erkennt am Gerätenamen, ob ein Xbox-, Switch-Pro- oder
PlayStation-Controller benutzt wird, und zeigt im HUD die Beschriftung, die dort an dieser
Stelle steht (Switch Pro: B / A / Y / X, ZL / L, ZR / R, +). Es schaltet automatisch auf das
zuletzt benutzte Eingabegerät um.

**Zielen mit dem Controller:** Die Richtung des rechten Sticks ist die Blickrichtung. Der Officer
dreht sich in echter Zeit dorthin (auch in der Zeitlupe schnell) und hält dann an; nach dem
Loslassen bleibt die zuletzt gehaltene Richtung stehen, Laufen dreht ihn nicht. Drehtempo und
Totzone stehen in `gameplay_tweaks.cfg` (`pad_turn_speed_deg`, `pad_aim_deadzone`). Die
Auslenkung bestimmt die Wurfweite der Blendgranate.

**Zug freiwillig beenden** („Position halten“) liegt vorübergehend auf keiner Taste mehr, weil
man sie zu leicht versehentlich drückt. Im Pausemenü gibt es dafür „Zug beenden“. Wieder
einschalten: `HOLD_KEY_ENABLED` oben in `scripts/game_manager.gd` (dann F / Enter).

## Das Squad

| Officer | Spezialfähigkeit (Aktionstaste) |
|---|---|
| 1 · vorn | Startet geduckt. **Blendgranate** (2 Stück): fliegt im Bogen zum Mauszeiger (höchstens 8 m), springt nach dem Aufkommen weiter, prallt an Wänden und Möbeln ab und zündet 0,6 Spielsekunden nach dem ersten Aufkommen. Der Wurf beendet den Zug. Blendet Gegner im Umkreis von 4,5 m mit Sichtlinie zur Granate für 2,5 Spielsekunden: sie sehen, zielen und schießen nicht. Das Team ist immun. |
| 2 · Mitte | **Schild**: das Heben beendet den Zug, danach bleibt es für den Rest des Durchlaufs oben. Es fängt Kugeln von vorn ab (etwa 110°) und deckt Kollegen dahinter. Mit erhobenem Schild läuft er langsamer und kann nicht schießen. |
| 3 · hinten | Rammt im Intro die Eingangstür auf. **Durchschuss**: die Aktionstaste schaltet den Modus an und aus. Im Modus gehen seine Kugeln durch bis zu zwei Wände, Möbel oder Türen, die Streuung ist dafür dreimal so groß. Metall-Objekte stoppen die Kugel bzw. lassen sie abprallen. Der Laser zeigt die Bahn durch die Wand. |

**Hechtsprung (alle):** schneller Satz in Laufrichtung (doppeltes Lauftempo), nicht lenkbar,
weiterhin treffbar, nicht mit erhobenem Schild. Danach kurz maximale Streuung, 1,5 Spielsekunden
Abklingzeit. Figuren blockieren sich gegenseitig nicht, man springt also über geduckte Kollegen hinweg.

**Ducken:** Geduckt ist man 30 % langsamer. Stehende Kollegen schießen über Geduckte hinweg.
Hinter den hellbraunen **Kisten** ist ein Geduckter aus dieser Richtung nicht zu treffen;
zum Schießen über die Kiste muss er aufstehen. Im Freien schützt Ducken nicht.

## Spielablauf

- Ein **Durchlauf** besteht aus einem Zug pro lebendem Officer. Alle Züge starten vom
  selben Checkpoint (T0).
- Ein **Zug** endet mit dem eigenen Schuss, dem Granatenwurf, dem Heben des Schilds, mit
  „Position halten“ oder wenn der Officer fällt. Schuss und Wurf wirken erst ab dem
  nächsten Zug. Gegnerschüsse beenden den Zug nicht mehr: ihre Kugeln fliegen sofort.
  (Umschaltbar über drei Konstanten ganz oben in `scripts/game_manager.gd`.)
- Beim eigenen Schuss fährt die Kamera 2 Sekunden lang nah an den Schützen.
  Granatenwurf und Schildheben zeigen ebenfalls eine kurze Nahaufnahme in Zeitlupe.
- Nach jedem Zug wird sichtbar **zurückgespult**: der Zug läuft rückwärts bis zum Checkpoint,
  mit ◀◀-Symbol, VHS-Verzerrung und entsättigtem Bild.
- Das normale Spiel läuft in **Echtzeit**; die Zeitlupe gilt nur, solange die Waffe angelegt ist
  (umschaltbar in `gameplay_tweaks.cfg`).
- „Echtzeit“ (Vorlauf und Abschluss-Replay) läuft mit `realtime_speed` aus `gameplay_tweaks.cfg`,
  derzeit doppelt so schnell wie echte Echtzeit; die Zeitlupe mit `slowdown_speed` (derzeit 5 %).
- Ab dem zweiten Zug läuft das bisher Aufgezeichnete zuerst in **Echtzeit** ab. Kurz bevor
  der Moment erreicht ist, an dem der vorige Zug endete, bremst die Zeit auf Zeitlupe und
  du übernimmst den nächsten Officer. Die Züge bauen also zeitlich aufeinander auf. Im Vorlauf
  zählt oben mittig ein Timer (**„ÜBERNAHME IN x s"** mit Fortschrittsbalken) in echten
  Sekunden bis zur Übernahme herunter.
- Vor jeder Übernahme läuft ein Countdown **3 – 2 – 1 – GO GO GO**.
- Vorherige Officer fahren ihre Aufzeichnung nach; ist sie zu Ende, halten sie Position.
  Ihre Schüsse werden jetzt echte Kugeln.
- **Kugeln haben Flugzeit** (40 m pro Spielsekunde). Man sieht sie auch im Dunkeln kommen
  und kann ausweichen. Ein Treffer tötet – auch Kollegen und Geiseln.
- An **Metall-Objekten** (bläulich glänzend: Spind und Heizkörper im Flur, Kühlschrank,
  Aktenschrank, Tresor) prallen Kugeln ab, Einfallswinkel = Ausfallswinkel, höchstens
  zweimal. Der eigene Laser spiegelt sich dort und zeigt die Bahn des Abprallers.
- **Doppeltüren** (1,75 m breit) sind zu Beginn geschlossen; den Eingang rammt Officer 3
  im Intro auf. Die übrigen sind geschlossen und blocken Sicht, Kugeln und Granaten. Aufstoßen
  hört man 6 m weit: Gegner in der Nähe drehen sich zur Tür.
- **Gegner** tragen die Waffe gesenkt und ziehen sie erst, wenn sie einen Officer sehen oder
  etwas hören (Schuss, Granate, Tür). Erst mit gezogener Waffe zielen und schießen sie.
- **Gegner reagieren:** Beim ersten Alarm stellt sich ein Gegner hinter eine nahe Geisel und
  bedroht sie. Über der Geisel läuft eine Frist (10 Spielsekunden); ist sie um, erschießt er
  sie. Blenden hält die Frist an. Nach einem eigenen Schuss oder einem knappen Fehlschuss
  weichen Gegner ohne Geisel kurz hinter ein Möbelstück aus.
- Die **Startplätze der Gegner** werden bei jeder neuen Mission ausgelost (je drei pro Raum).
- Nach dem letzten Zug folgt die **Auswertung**: alle Aufzeichnungen laufen gemeinsam durch.
  Ihr Endzustand ist der Checkpoint des nächsten Durchlaufs. Tote Geisel = Mission failed.
  (Abschaltbar über `fail_on_hostage_hit` in `gameplay_tweaks.cfg`.)
- **Letzter Officer:** Ist nach einer Auswertung nur noch ein Officer einsatzfähig, gibt es
  keine Runden mehr. Ab dann wird nichts mehr eingefroren oder zurückgespult: Schüsse,
  Granaten und Schild wirken sofort, und es geht ohne Unterbrechung weiter, bis alle Gegner
  ausgeschaltet sind oder der Officer fällt. „Position halten“ hat dann keine Wirkung.
- **Treffer-Feedback:** Ein sichtbarer Treffer an einer Figur hält das Bild kurz an, die Kamera
  ruckt, es gibt einen eigenen Ton und der Controller vibriert (auch bei Schuss und Blendgranate).
  Treffer außerhalb der Sichtkegel bleiben wie bisher ungewiss.
- **Abschluss-Replay:** Die Kamera folgt dem Team, Schussbahnen bleiben kurz als Leuchtspur
  stehen, und beim letzten ausgeschalteten Gegner fährt sie in kurzer Zeitlupe nah heran.
- Sind nach einer Auswertung alle Gegner ausgeschaltet: Replay des ganzen Einsatzes in
  Echtzeit, danach Ergebnis mit **Wertung**: je ein Stern für Einsatzdauer, Zahl der
  Team-Schüsse und Zahl der Durchläufe.

## Anzeigen

- Leiste oben: aktueller Abschnitt und Status der Officer (aktiv, fertig, wartet, Ausfall).
- Unten links: ein Icon pro Officer. Mit Blendgranate in der Hand, hinter dem Schild, und
  der dünne Große im Laufschritt (der mit dem Durchschuss). Der gerade gespielte ist
  hell und farbig umrandet, Ausfälle sind durchgestrichen. Darüber Munition und Aim-Stabilität.
- Oben links: kleine Übersicht der Tastenbelegung (während des Spielens).
- Aktiver Officer: pulsierender Bodenring und Pfeil über dem Kopf.
- Laser und weißer Streubogen erscheinen nur mit angelegter Waffe. Der Bogen schrumpft beim
  Stillstehen zu einem Punkt.
- Roter Laser: Team. Orange: Gegner. Der Gegner-Laser erscheint erst, wenn der Gegner
  einen Officer gesichtet und die Waffe gezogen hat (dann auch aus dem Dunkeln).
- Ring mit „!“ über dem Gegner: füllt sich bis zu seinem nächsten Schuss.
- Kreisende Sterne über dem Gegner: geblendet.
- Officer, die gerade nicht gespielt werden, sind abgedunkelt.
- Roter Ring mit Sekunden über einer Geisel: Frist, bis ihr Bewacher schießt.
- Farbige Linie und Ring am Boden: restlicher Weg und Endposition der Officer, die schon
  dran waren. Gelb gestrichelt mit ✕: ihr noch kommender Schuss.
- Weiß gestrichelte Linie mit Kreis (Officer 1): Wurfbahn und Blendradius der Granate.

## Dateien

| Datei | Inhalt |
|---|---|
| `scenes/main.tscn` | Hauptszene (ein Node mit `game_manager.gd`, alles Weitere entsteht per Code) |
| `scripts/game_manager.gd` | Ablauf/Phasen, Simulations-Tick, Kugeln, Checkpoints, Eingabe, Kamera, Laser |
| `scripts/round_system.gd` | Daten des Rundensystems: Durchlauf, Züge, Aufzeichnungen, Replay-Timeline |
| `gameplay_tweaks.cfg` | Alle Gameplay-Werte als Textdatei (siehe Stellschrauben) |
| `scripts/tweaks.gd` | Autoload `Tweaks`: liest `gameplay_tweaks.cfg` |
| `scripts/time_control.gd` | Autoload `TimeControl`: Spieltempo und Zeitlupe über die Tick-Rate |
| `scripts/actor.gd` | Basisklasse aller Figuren (Kollision, Blickrichtung, Tod, Zustand); Geiseln nutzen sie direkt |
| `scripts/character_model.gd` | Animiertes 3D-Modell: wählt Lauf-, Ziel-, Schuss- und Sterbe-Animation |
| `scripts/officer.gd` | Spielersteuerung, träges Zielen, Aim-Stabilität/Streuung, Spezialfähigkeiten |
| `scripts/enemy.gd` | Gegner-KI (bewachen/patrouillieren, alarmiert, feuern) |
| `scripts/laser.gd` | Laserstrahl |
| `scripts/door.gd` | Tür: geschlossen ein Hindernis, offen nur Optik |
| `scripts/sound_bank.gd` | Sounds: lädt die Aufnahmen, erzeugt die kurzen Signaltöne im Code |
| `scripts/fx_overlay.gd` | 2D-Effekte über dem Nebel: Kugeln, Mündungsfeuer, Einschläge, Streubogen, Markierung |
| `scripts/vision.gd` | Sichtkegel per Raycast, Abdunkelungs-Maske, Sichtbarkeitstest |
| `scripts/level.gd` | Test-Wohnung als Datentabellen (Wände, Böden, Möbel, Startpositionen), setzt sie aus den Bausteinen zusammen |
| `assets/props/*.tscn` | Bausteine der Umgebung (Wand- und Boden-Module, Kisten, einzelne Möbel und Metall-Objekte, Türflügel) |
| `scripts/main_menu.gd` | Hauptmenü und Einweisung (drei gezeichnete Tafeln) |
| `scripts/pause_menu.gd` | Pausemenü |
| `scripts/hud.gd` | HUD: Abschnittsleiste, Officer-Icons, Tastenbelegung, Titelkarten, Kinobalken, Ergebnis-Tafel |
| `shaders/fog.gdshader` | Abdunkelung außerhalb der Sichtkegel |
| `shaders/rewind.gdshader` | VHS-Effekt beim Zurückspulen |
| `assets/characters/*.gltf` | Figuren mit Animationen |
| `assets/sounds/*.wav` | Schüsse, Blendgranate, Tür |

## Modelle und Umgebung austauschen

Das Spiel ist so angelegt, dass Optik und Spiellogik getrennt sind: Die Logik rechnet mit
Positionen und einfachen Kollisions-Quadern, alles Sichtbare kommt aus austauschbaren Dateien.

- **Figuren:** Tabelle `MODELS` oben in `scripts/character_model.gd`, ein Eintrag pro Art:
  `officer_flash`, `officer_shield`, `officer_pierce`, `enemy`, `hostage`. Die drei Officer
  zeigen noch auf dasselbe Modell; zum Austauschen die Datei im Eintrag ändern. Stammt ein
  Modell nicht aus dem Quaternius-Kit, lassen sich im Eintrag Größe (`scale`), Animationsnamen
  (`anims`, Rollen siehe `ANIMS`) und einzufärbende Materialien (`tint`) angeben. Fehlende
  Animationen werden übersprungen, das Spiel läuft trotzdem.
- **Umgebung:** Bausteine als Szenen in `assets/props/` (Maße und Ursprung siehe
  `assets/props/README.md`): Wand-Module 3 m / 1 m / 0,5 m plus Eckpfosten, Boden-Platten
  3×3 / 3×1 / 1×1 m, Türflügel sowie je eine eigene Szene pro Kiste, Möbelstück und
  Metall-Objekt in dessen echter Größe (nichts wird gestreckt). Zum Verschönern den Inhalt
  der Szene ersetzen.
- **Grundriss:** Tabellen oben in `scripts/level.gd` auf einem 0,5-m-Raster (Böden: 1 m). Das
  Level belegt jede Wandstrecke und Bodenfläche automatisch mit den größten passenden Modulen.
- **Noch im Code gebaut:** Schild und Rammbock (`scripts/officer.gd`), Licht (`scripts/level.gd`).

## Fremdmaterial

Die drei Figuren in `assets/characters/` stammen aus dem **Toon Shooter Game Kit** von
Quaternius (https://quaternius.com/packs/toonshootergamekit.html), Lizenz **CC0**.

Die vier Sounds in `assets/sounds/` stammen von opengameart.org, alle **CC0**:
`shot_team.wav` und `shot_enemy.wav` aus „gunshots“ (https://opengameart.org/content/gunshots),
`flash_bang.wav` aus „flash bang sound“ (https://opengameart.org/content/flash-bang-sound),
`door_open.wav` aus „door open sfx“ (https://opengameart.org/content/door-open-sfx).
Countdown, Slowdown, Abpraller, Einschlag und Freeze werden im Code erzeugt.

## Stellschrauben

Die wichtigsten Gameplay-Werte stehen in **`gameplay_tweaks.cfg`** (einfache Textdatei, jeder Wert
mit Kommentar). Sie wird beim Start und bei jeder neuen Mission (**N**) neu gelesen.

| Sektion | Inhalt |
|---|---|
| `[tempo]` | Echtzeit-Tempo (Vorlauf, Replay), Slowdown-Tempo, normales Spieltempo, Schalter „Slowdown nur beim Zielen“, Übergangszeit, Rückspulgeschwindigkeit (mit Mindest- und Höchstdauer), Tempo der Auswertung |
| `[player]` | Lauftempo (auch geduckt, mit Schild, mit angelegter Waffe), Ziel-Rotation, Aim-Stabilität, Streuung, Munition, Granaten, Hechtsprung, Streuung im Durchschuss |
| `[enemy]` | Reaktionszeit, Ziel-Tempo, Ziel-Genauigkeit, Zeit zum Ziehen der Waffe, Feuerrate, Sicht- und Hörweite, Lauftempo, Deckung, Geisel-Frist |
| `[weapons]` | Kugeltempo, Granate (Wurfweite, Tempo, Zünder, Blendradius, Blenddauer), Zahl der Abpraller, Zahl der durchschlagenen Wände |
| `[mission]` | Schalter `fail_on_hostage_hit`: scheitert die Mission, wenn eine Geisel getroffen wird? |

Weiterhin im Code:

- Dauer des Standbilds, Countdown, Tür-Reichweite und -Lautstärke, Sterne-Ziele, Kamerawinkel: Konstanten oben in `scripts/game_manager.gd`
- Sichtkegel (Winkel, Reichweite, Nahbereich): `@export` in `scripts/vision.gd`
- Grundriss, Türen, Metall-Objekte, Squad-Rollen, Gegner-Startplätze, Geiseln: Tabellen oben in `scripts/level.gd`
