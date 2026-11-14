# Showdown – "Go Go Go" Taktik-Prototyp

Top-down 3D-Taktikspiel in Zeitlupe: Ein 3-köpfiges SEK stürmt eine Wohnung.
Godot **4.7** (entwickelt und getestet mit 4.7.2 stable), reines GDScript.

## Starten

1. Godot 4.7.x öffnen → **Importieren** → `project.godot` in diesem Ordner wählen.
2. **F5** drücken (Hauptszene ist `scenes/main.tscn`).

Oder direkt im Terminal: `godot --path .`

## Steuerung

| Eingabe | Wirkung |
|---|---|
| W A S D | Officer bewegen |
| Maus | Zielen (die Waffe folgt dem Mauszeiger verzögert) |
| Linksklick | Schießen (beendet den Zug) |
| Rechtsklick / Shift | Aktionstaste: Spezialfähigkeit des Officers (Granate und Schild beenden den Zug, die Rolle nicht) |
| C / Strg | Ducken / Aufstehen (umschalten) |
| E | Tür öffnen (in Reichweite erscheint ein „E“ an der Tür) |
| F / Enter | Position halten (Zug ohne Schuss beenden) |
| Leertaste (halten) | Vorspulen (5-fach) |
| 1 / 2 oder Mausrad | Zeitlupe langsamer / schneller (3–30 %) |
| R | nach Fehlschlag: Durchlauf wiederholen · im Ergebnis: Replay erneut |
| N | neue Mission (nach Fehlschlag oder Ergebnis) |
| Esc | Beenden |

## Das Squad

| Officer | Spezialfähigkeit (Aktionstaste) |
|---|---|
| 1 · vorn | Startet geduckt. **Blendgranate** (2 Stück): fliegt im Bogen zum Mauszeiger (höchstens 8 m), springt nach dem Aufkommen weiter, prallt an Wänden und Möbeln ab und zündet 0,6 Spielsekunden nach dem ersten Aufkommen. Der Wurf beendet den Zug. Blendet Gegner im Umkreis von 4,5 m mit Sichtlinie zur Granate für 2,5 Spielsekunden: sie sehen, zielen und schießen nicht. Das Team ist immun. |
| 2 · Mitte | **Schild**: das Heben beendet den Zug, danach bleibt es für den Rest des Durchlaufs oben. Es fängt Kugeln von vorn ab (etwa 110°) und deckt Kollegen dahinter. Mit erhobenem Schild läuft er langsamer und kann nicht schießen. |
| 3 · hinten | Rammt im Intro die Eingangstür auf. **Hechtrolle**: gut 3 m schneller Satz in Laufrichtung, nicht lenkbar, weiterhin treffbar. Danach kurz maximale Streuung, 1,5 Spielsekunden Abklingzeit. |

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
- Ab dem zweiten Zug läuft das bisher Aufgezeichnete zuerst in **Echtzeit** ab. Kurz bevor
  der Moment erreicht ist, an dem der vorige Zug endete, bremst die Zeit auf Zeitlupe und
  du übernimmst den nächsten Officer. Die Züge bauen also zeitlich aufeinander auf.
- Vor jeder Übernahme läuft ein Countdown **3 – 2 – 1 – GO GO GO**.
- Vorherige Officer fahren ihre Aufzeichnung nach; ist sie zu Ende, halten sie Position.
  Ihre Schüsse werden jetzt echte Kugeln.
- **Kugeln haben Flugzeit** (40 m pro Spielsekunde). Man sieht sie auch im Dunkeln kommen
  und kann ausweichen. Ein Treffer tötet – auch Kollegen und Geiseln.
- An **Metall-Objekten** (bläulich glänzend: Spind und Heizkörper im Flur, Kühlschrank,
  Aktenschrank, Tresor) prallen Kugeln ab, Einfallswinkel = Ausfallswinkel, höchstens
  zweimal. Der eigene Laser spiegelt sich dort und zeigt die Bahn des Abprallers.
- **Doppeltüren** (gut 2 m breit) sind zu Beginn geschlossen; den Eingang rammt Officer 3
  im Intro auf. Die übrigen sind geschlossen und blocken Sicht, Kugeln und Granaten. Aufstoßen
  hört man 6 m weit: Gegner in der Nähe drehen sich zur Tür.
- **Gegner reagieren:** Beim ersten Alarm stellt sich ein Gegner hinter eine nahe Geisel und
  bedroht sie. Über der Geisel läuft eine Frist (10 Spielsekunden); ist sie um, erschießt er
  sie. Blenden hält die Frist an. Nach einem eigenen Schuss oder einem knappen Fehlschuss
  weichen Gegner ohne Geisel kurz hinter ein Möbelstück aus.
- Die **Startplätze der Gegner** werden bei jeder neuen Mission ausgelost (je drei pro Raum).
- Nach dem letzten Zug folgt die **Auswertung**: alle Aufzeichnungen laufen gemeinsam durch.
  Ihr Endzustand ist der Checkpoint des nächsten Durchlaufs. Tote Geisel = Mission failed.
- Sind nach einer Auswertung alle Gegner ausgeschaltet: Replay des ganzen Einsatzes in
  Echtzeit, danach Ergebnis mit **Wertung**: je ein Stern für Einsatzdauer, Zahl der
  Team-Schüsse und Zahl der Durchläufe.

## Anzeigen

- Leiste oben: aktueller Abschnitt und Status der vier Officer (aktiv, fertig, wartet, Ausfall).
- Aktiver Officer: pulsierender Bodenring und Pfeil über dem Kopf.
- Weißer Bogen am Laser-Ende: Streuung. Schrumpft beim Stillstehen zu einem Punkt.
- Roter Laser: Team. Orange: Gegner. Der Gegner-Laser erscheint erst, wenn der Gegner
  einen Officer gesichtet hat (dann auch aus dem Dunkeln).
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
| `scripts/time_control.gd` | Autoload `TimeControl`: zentrale Zeitlupe über die Tick-Rate |
| `scripts/actor.gd` | Basisklasse aller Figuren (Kollision, Blickrichtung, Tod, Zustand); Geiseln nutzen sie direkt |
| `scripts/character_model.gd` | Animiertes 3D-Modell: wählt Lauf-, Ziel-, Schuss- und Sterbe-Animation |
| `scripts/officer.gd` | Spielersteuerung, träges Zielen, Aim-Stabilität/Streuung, Spezialfähigkeiten |
| `scripts/enemy.gd` | Gegner-KI (bewachen/patrouillieren, alarmiert, feuern) |
| `scripts/laser.gd` | Laserstrahl |
| `scripts/door.gd` | Tür: geschlossen ein Hindernis, offen nur Optik |
| `scripts/sound_bank.gd` | Sounds: lädt die Aufnahmen, erzeugt die kurzen Signaltöne im Code |
| `scripts/fx_overlay.gd` | 2D-Effekte über dem Nebel: Kugeln, Mündungsfeuer, Einschläge, Streubogen, Markierung |
| `scripts/vision.gd` | Sichtkegel per Raycast, Abdunkelungs-Maske, Sichtbarkeitstest |
| `scripts/level.gd` | Test-Wohnung als Datentabellen (Wände, Möbel, Startpositionen) |
| `scripts/hud.gd` | HUD: Abschnittsleiste, Titelkarten, Kinobalken, Ergebnis-Tafel |
| `shaders/fog.gdshader` | Abdunkelung außerhalb der Sichtkegel |
| `assets/characters/*.gltf` | Figuren mit Animationen |
| `assets/sounds/*.wav` | Schüsse, Blendgranate, Tür |

## Fremdmaterial

Die drei Figuren in `assets/characters/` stammen aus dem **Toon Shooter Game Kit** von
Quaternius (https://quaternius.com/packs/toonshootergamekit.html), Lizenz **CC0**.

Die vier Sounds in `assets/sounds/` stammen von opengameart.org, alle **CC0**:
`shot_team.wav` und `shot_enemy.wav` aus „gunshots“ (https://opengameart.org/content/gunshots),
`flash_bang.wav` aus „flash bang sound“ (https://opengameart.org/content/flash-bang-sound),
`door_open.wav` aus „door open sfx“ (https://opengameart.org/content/door-open-sfx).
Countdown, Slowdown, Abpraller, Einschlag und Freeze werden im Code erzeugt.

## Stellschrauben

- Zeitlupe, Vorspul-Faktor: `scripts/time_control.gd`
- Kugeltempo, Dauer des Standbilds, Countdown, Granate (Wurfweite, Radius, Blenddauer), Zahl der Abpraller, Tür-Reichweite und -Lautstärke, Sterne-Ziele, Kamerawinkel: Konstanten oben in `scripts/game_manager.gd`
- Sichtkegel (Winkel, Reichweite, Nahbereich): `@export` in `scripts/vision.gd`
- Tempo, Ziel-Trägheit, Streuung, Munition, Granaten, Schild-Tempo, Rolle: `@export` in `scripts/officer.gd`
- Reaktionszeit, Sichtweite, Feuerrate, Deckung, Geisel-Frist der Gegner: `@export` in `scripts/enemy.gd`
- Grundriss, Türen, Metall-Objekte, Squad-Rollen, Gegner-Startplätze, Geiseln: Tabellen oben in `scripts/level.gd`
