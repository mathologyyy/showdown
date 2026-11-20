extends Node3D
## GameManager: baut die Szene auf und steuert den gesamten Ablauf.
##
## Ablauf eines Durchlaufs:
##   Checkpoint (T0) ─► Zug Officer 1 ─► Freeze ─► Zurückspulen ─► Reset auf T0 ─► Zug Officer 2 ─► …
##   … ─► Auswertung (alle Aufzeichnungen laufen gemeinsam durch) ─► neuer Checkpoint
##
## Ab dem zweiten Zug läuft das bisher Aufgezeichnete zuerst in ECHTZEIT ab. Kurz vor
## dem Moment, an dem der vorige Zug endete, bremst die Zeit auf Zeitlupe herunter
## und der Spieler übernimmt den nächsten Officer ("Übernahme"). Vor jeder Übernahme
## läuft ein Countdown 3 – 2 – 1 – GO GO GO.
##
## Spezialfähigkeiten (Leertaste): Blendgranate, Schild, Durchschuss – siehe officer.gd.
## Alle Officer können einen Hechtsprung machen (Umschalttaste).
## Rechte Maustaste halten legt die Waffe an (Laser, Streubogen, Schießen).
## Kugeln prallen an Metall-Objekten (Level.METAL) ab.
##
## Sind in einer Auswertung alle Gegner ausgeschaltet, folgt das Abschluss-Replay
## in Echtzeit und der Ergebnis-Screen.
##
## Die Simulation läuft ausschließlich in _physics_process mit festem Zeitschritt
## (deterministisch, siehe time_control.gd), alles Sichtbare in _process.

enum Phase { PLAYING, BREAK, RESOLVE, FAILED, FINAL_REPLAY, RESULTS, INTRO, REWIND, MENU }

## Hauptmenü + Einweisung (eigenes Skript, per Pfad geladen).
const MainMenuScript := preload("res://scripts/main_menu.gd")
## Hauptmenü schon durchlaufen? Statisch, damit "Neue Mission" (Szene neu laden)
## direkt ins Spiel führt und nicht wieder ins Menü.
static var _menu_done := false

## Was einen Zug beendet (zum Ausprobieren umschaltbar):
const ENEMY_SHOT_ENDS_TURN := false   # Gegnerschüsse frieren nicht mehr ein, die Kugel fliegt sofort
const SHIELD_ENDS_TURN := true        # Schild heben beendet den Zug
const GRENADE_ENDS_TURN := true       # Granatenwurf beendet den Zug (sie fliegt ab dem nächsten Zug)

const OFFICER_COLORS := [
	Color(0.15, 0.40, 1.00), Color(0.10, 0.75, 0.55), Color(0.55, 0.35, 1.00),
]
const ROLE_SHORT := {"flash": "Blend", "shield": "Schild", "pierce": "Durchschuss"}
## "Position halten" (Zug freiwillig beenden) per Taste. Vorübergehend aus, weil man es
## zu leicht versehentlich drückt; im Pausemenü gibt es dafür weiterhin "Zug beenden".
const HOLD_KEY_ENABLED := false
## Beschriftung der Controller-Tasten je Bauart. Schlüssel = Lage wie bei Godot/Xbox:
## a unten, b rechts, x links, y oben. Die Funktion hängt an der Lage, nicht am Buchstaben.
const PAD_LABELS := {
	"xbox": {"title": "XBOX", "a": "A", "b": "B", "x": "X", "y": "Y",
		"lt": "LT", "lb": "LB", "rt": "RT", "rb": "RB", "start": "Start"},
	"switch": {"title": "SWITCH PRO", "a": "B", "b": "A", "x": "Y", "y": "X",
		"lt": "ZL", "lb": "L", "rt": "ZR", "rb": "R", "start": "+"},
	"ps": {"title": "PLAYSTATION", "a": "Kreuz", "b": "Kreis", "x": "Quadrat", "y": "Dreieck",
		"lt": "L2", "lb": "L1", "rt": "R2", "rb": "R1", "start": "Options"},
}
const ENEMY_COLOR := Color(0.75, 0.08, 0.06)
const HOSTAGE_COLOR := Color(0.95, 0.80, 0.15)
const LASER_OFFICER := Color(1.0, 0.05, 0.05, 0.9)
const LASER_ENEMY := Color(1.0, 0.55, 0.0, 0.9)
const COL_GO := Color(1.0, 0.85, 0.2)
const COL_REALTIME := Color(0.55, 0.9, 1.0)
const COL_FREEZE := Color(0.6, 0.8, 1.0)
const COL_DANGER := Color(1.0, 0.35, 0.25)

const BREAK_SECONDS := 1.8          # echte Sekunden Standbild nach einem Schuss
var BULLET_SPEED: float = 40.0      # m pro Spielsekunde (bei 10 % Zeitlupe: 4 m/s auf dem Schirm); aus Tweaks "weapons"
const SHOT_RANGE := 60.0
const RESOLVE_TAIL_TICKS := 72      # Auswertung läuft 0,15 s über die längste Aufzeichnung hinaus
const SOLO_TAIL_TICKS := 288        # ohne Runden: so lange läuft die Welt nach der Entscheidung noch weiter (0,6 s)
var RESOLVE_TIME_SCALE: float = 0.6 # Tempo der Auswertung; aus Tweaks "tempo"
var REWIND_SPEED: float = 4.0        # Rückspultempo als Vielfaches der Echtzeit; aus Tweaks "tempo"
var REWIND_MAX_SECONDS: float = 3.0  # Obergrenze fürs Rückspulen in echten Sekunden; aus Tweaks "tempo"
var REWIND_MIN_SECONDS: float = 0.8  # Untergrenze fürs Rückspulen in echten Sekunden; aus Tweaks "tempo"
var _rw_tracks: Array = []           # Welt-Aufzeichnung des laufenden Zugs fürs Rückspulen: pro Figur PackedFloat32Array (x, z, yaw, alive, flags)
var _rw_doors: Array = []            # in diesem Zug geöffnete Türen: [{tick, door}]
var _rw_pos := 0.0                   # aktuelle Rückspul-Position in Ticks (läuft gegen 0)
var _rw_rate := 0.0                  # Ticks pro echter Sekunde
## Übernahme so viele Ticks VOR dem Ende des vorigen Zugs (0,25 Spielsekunden).
const TAKEOVER_LEAD_TICKS := 120
## Countdown vor jeder Übernahme: 3, 2, 1 mit je so vielen echten Sekunden. Währenddessen
## bremst die Zeit von Echtzeit auf Zeitlupe.
const COUNT_STEP := 0.5
const COUNT_TOTAL := COUNT_STEP * 3.0
var GRENADE_RANGE: float = 8.0      # maximale Wurfweite (m); aus Tweaks "weapons"
var GRENADE_SPEED: float = 10.0     # m pro Spielsekunde; aus Tweaks "weapons"
var GRENADE_FUSE: float = 0.6       # Spielsekunden zwischen erstem Aufkommen und Zündung; aus Tweaks "weapons"
const GRENADE_GRAVITY := 12.0
const GRENADE_BOUNCE := 0.4         # so viel Höhe bleibt nach einem Aufprall
const GRENADE_KEEP := 0.5           # so viel Tempo bleibt nach Boden- oder Wandkontakt
const SHOT_CUT_SECONDS := 2.0       # Nahaufnahme beim eigenen Schuss (echte Sekunden)
const ABILITY_CUT_SECONDS := 1.6    # Nahaufnahme bei Granatenwurf und Schildheben (echte Sekunden)
const CUT_ANIM_SCALE := 0.5         # Animationstempo der gezeigten Figur während eines Fähigkeiten-Clips
const CUT_ZOOM := 0.42              # Kameraabstand in der Nahaufnahme (Anteil der Totalen)
const CUT_BULLET_METERS := 1.0      # so weit fliegt die Kugel in der Nahaufnahme
const INTRO_SECONDS := 2.4          # Rammbock-Intro
const CROUCH_COVER_REACH := 1.6     # so nah muss die Kiste vor dem Geduckten stehen
var FLASH_RADIUS: float = 4.5       # Blendradius (nur mit Sichtlinie zur Granate); aus Tweaks "weapons"
var FLASH_SECONDS: float = 2.5      # so lange sind Gegner geblendet (Spielzeit); aus Tweaks "weapons"
var PIERCE_MAX_WALLS: int = 2       # Durchschuss: durch so viele Wände/Möbel/Türen geht eine Kugel; aus Tweaks "weapons"
var MAX_BOUNCES: int = 2            # so oft prallt eine Kugel höchstens an Metall ab; aus Tweaks "weapons"
var FAIL_ON_HOSTAGE_HIT: bool = true # Mission scheitert, sobald eine Geisel getroffen wird; aus Tweaks "mission"
const DOOR_REACH := 1.7             # so nah muss ein Officer an der Tür stehen, um sie zu öffnen
const DOOR_NOISE := 6.0             # so weit hört man eine aufgestoßene Tür
## Wegschieben: näher als so (Mitte zu Mitte) kommen sich zwei Figuren nicht.
const PUSH_GAP := Actor.RADIUS * 2.0
const NEAR_MISS := 0.9              # fliegt eine Team-Kugel so knapp vorbei, geht der Gegner in Deckung
const GHOST_STEP := 12              # Vorschau früherer Officer: ein Wegpunkt alle so viele Ticks
## Wertung: je ein Stern für Einsatzdauer, Team-Schüsse und Durchläufe unter diesen Grenzen.
const STAR_SECONDS := 15.0
const STAR_EXTRA_SHOTS := 2         # erlaubte Schüsse = Zahl der Gegner + so viele
const STAR_PASSES := 4
## Controller: linker Stick bewegt, rechter Stick zielt, LT/LB legt die Waffe an, RT/RB schießt.
const PAD_MOVE_DEADZONE := 0.25
var PAD_AIM_DEADZONE: float = 0.35  # radiale Totzone des Ziel-Sticks; aus Tweaks "player"
var PAD_TURN_SPEED: float = 1080.0   # Drehtempo mit dem Controller (Grad pro ECHTER Sekunde); aus Tweaks "player"
## Fällt die Auslenkung des Ziel-Sticks pro Frame um mehr als das, wird er gerade
## losgelassen: die Richtung beim Zurückschnappen zählt dann nicht mehr.
const PAD_RELEASE_DROP := 0.04
const PAD_TRIGGER := 0.5            # ab dieser Auslenkung gilt ein Trigger (LT/RT) als gedrückt
const PAD_THROW_DEFAULT := 5.0      # Wurfweite der Granate (m), solange der rechte Stick ruht
## Treffer-Feedback: so lange steht das Bild bei einem sichtbaren Treffer (echte Sekunden).
const HITSTOP_SECONDS := 0.07
## Abschluss-Replay: Kamera folgt dem Team (Abstand als Anteil der Totalen) und fährt beim
## letzten ausgeschalteten Gegner kurz nah heran, dazu Zeitlupe.
const REPLAY_ZOOM := 0.72
const REPLAY_KILL_ZOOM := 0.45
const REPLAY_KILL_SCALE := 0.2      # Tempo der Zeitlupe beim letzten Treffer
const REPLAY_KILL_SECONDS := 1.3    # echte Sekunden
const CAM_PITCH_DEG := 60.0
const CAM_FOV := 50.0

var officers: Array[Officer] = []
var enemies: Array[Enemy] = []
var hostages: Array[Actor] = []
var doors: Array[Door] = []
var phase := Phase.PLAYING
## Simulations-Tick seit dem aktuellen Checkpoint (480 Ticks = 1 Spielsekunde).
var tick := 0
var active: Officer = null
var rounds := RoundSystem.new()

## Optional für Tests/Bots: ersetzt Maus+Tastatur.
## Liefert {move: Vector2, aim: Vector3, action: bool, aim_hold: bool} (aim_hold optional).
var input_provider: Callable

var _all: Array[Actor] = []          # officers + enemies + hostages, feste Reihenfolge
var _level: Level
var _camera: Camera3D
var _vision: VisionSystem
var _fx: FxOverlay
var _hud: Hud
var _pause: PauseMenu
var _officer_lasers: Array[LaserBeam] = []
var _reflect_lasers: Array[LaserBeam] = []   # an Metall gespiegelter Teil der Officer-Laser
var _enemy_lasers: Array[LaserBeam] = []
var _active_ring: MeshInstance3D
var _rng := RandomNumberGenerator.new()

## Kugeln im Flug: {pos, prev, dir, rid, enemy, left, leg, bounces, ghost, hit_actor, rec}
var _bullets: Array = []
## Blendgranaten im Flug: {from, to, t, dur, ghost}
var _grenades: Array = []
var _count_start := 0                # ab diesem Tick läuft der Countdown
var _count_left := -1.0              # verbleibende echte Sekunden, < 0 = läuft nicht
var _count_digit := 0
var _action_latch := false           # Aktionstaste wurde seit dem letzten Tick gedrückt
var _action_prev := false
var _door_req := false               # E gedrückt: nächste Tür öffnen
var _last_aim := Vector3.ZERO        # letzter Zielpunkt (für die Wurf-Vorschau)
var _ghosts: Array = []              # Vorschau früherer Officer: [{color, pts: [{tick, pos}], shots}]
var _deadline_count := 0
var _snd: SoundBank
var _crouch_req := false             # C gedrückt: ducken / aufstehen
var _cut: Dictionary = {}            # Nahaufnahme-Clip: {kind: "shot", from, dir} | {kind: "grenade", from, to, actor, path} | {kind: "shield", actor}
var _cam_k := 0.0                    # 0 = Totale, 1 = Nahaufnahme
var _cam_focus := Vector3.ZERO
var _go_step := 3                    # "GO", "GO GO", "GO GO GO" nacheinander
var _go_t := 0.0
var _intro_t := 0.0
var _intro_hit := false
var _initial_doors: Array = []       # Türzustand nach dem Intro (Start des Abschluss-Replays)
var _track: RoundSystem.Track        # Aufzeichnung des laufenden Zugs
var _segment: RoundSystem.Segment    # Welt-Aufzeichnung der laufenden Auswertung
var _resolve_end := 0
## Nur noch ein Officer übrig: keine Runden mehr. Kein Freeze, kein Zurückspulen, keine
## Auswertung – alles wirkt sofort, und das Gespielte wird direkt fürs Abschluss-Replay
## aufgezeichnet (_segment).
var _solo := false
var _solo_end := -1                  # Tick, an dem der Einsatz ohne Runden endet (< 0 = läuft noch)
var _takeover_tick := 0              # ab diesem Tick steuert der Spieler
var _lead_total := 0.0               # Vorlauf + Countdown in echten Sekunden (Übernahme-Timer)
var _taken := false
var _fire_req := false
var _hold_req := false
var _pad_active := false             # zuletzt benutztes Eingabegerät war ein Controller
var _pad_dev := 0                    # Gerätenummer dieses Controllers
var _pad_fire_down := false          # RT über der Schwelle (ein Schuss pro Durchdrücken)
var _pad_aim_dir := Vector3.ZERO     # letzte Zielrichtung per Stick (ZERO = Blickrichtung des Officers)
var _pad_aim_dist := PAD_THROW_DEFAULT
var _pad_prev_deflect := 0.0         # Auslenkung des Ziel-Sticks im vorigen Frame
var _pad_kind := "xbox"              # Bauart des Controllers: Schlüssel in PAD_LABELS
var _roll_req := false               # Hechtsprung-Taste gedrückt
var _settle := 0                     # Ticks Pause nach einem Reset (Physik übernimmt Teleports)
var _break_left := 0.0
var _last_usec := 0
var _shake := 0.0
var _time := 0.0
var _rp_seg := 0
var _rp_tick := 0
var _rp_elapsed := 0
var _rp_cam_k := 0.0                 # 0 = Totale, 1 = Replay-Kamera folgt dem Team
var _rp_focus := Vector3.ZERO        # Punkt, auf den die Replay-Kamera schaut
var _rp_zoom := 1.0
var _rp_slow := 0.0                  # verbleibende echte Sekunden Zeitlupe (letzter Treffer)
var _rp_final_done := false          # Zeitlupe beim letzten Gegner schon ausgelöst
var _rp_last_down := Vector3.ZERO    # dort ist zuletzt ein Gegner gefallen
var _hitstop := 0.0                  # verbleibende echte Sekunden Bildstopp nach einem Treffer
var _menu = null                     # Hauptmenü (main_menu.gd), nur bis zum Spielstart


func _ready() -> void:
	# Gameplay-Werte aus der editierbaren Datei laden
	Tweaks.reload()
	TimeControl.apply_tweaks()
	BULLET_SPEED = Tweaks.num("weapons", "bullet_speed", 40.0)
	GRENADE_RANGE = Tweaks.num("weapons", "grenade_range", 8.0)
	GRENADE_SPEED = Tweaks.num("weapons", "grenade_speed", 10.0)
	GRENADE_FUSE = Tweaks.num("weapons", "grenade_fuse", 0.6)
	FLASH_RADIUS = Tweaks.num("weapons", "flash_radius", 4.5)
	FLASH_SECONDS = Tweaks.num("weapons", "flash_seconds", 2.5)
	MAX_BOUNCES = Tweaks.whole("weapons", "max_bounces", 2)
	PIERCE_MAX_WALLS = Tweaks.whole("weapons", "pierce_max_walls", 2)
	PAD_AIM_DEADZONE = clampf(Tweaks.num("player", "pad_aim_deadzone", 0.35), 0.05, 0.9)
	PAD_TURN_SPEED = Tweaks.num("player", "pad_turn_speed_deg", 1080.0)
	FAIL_ON_HOSTAGE_HIT = Tweaks.flag("mission", "fail_on_hostage_hit", true)
	RESOLVE_TIME_SCALE = Tweaks.num("tempo", "resolve_speed", 0.6)
	REWIND_SPEED = Tweaks.num("tempo", "rewind_speed", 4.0)
	REWIND_MAX_SECONDS = Tweaks.num("tempo", "rewind_max_seconds", 3.0)
	REWIND_MIN_SECONDS = Tweaks.num("tempo", "rewind_min_seconds", 0.8)
	_rng.randomize()
	_level = Level.new()
	add_child(_level)
	_level.build()
	for d in Level.DOORS:
		var door := Door.new()
		add_child(door)
		door.setup(Vector3(d[0], 0, d[1]), Vector3(d[2], 0, d[3]))
		doors.append(door)
	_snd = SoundBank.new()
	add_child(_snd)
	_spawn_actors()

	_camera = Camera3D.new()
	_camera.fov = CAM_FOV
	_camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	add_child(_camera)
	_camera.rotation_degrees = Vector3(-CAM_PITCH_DEG, 0, 0)
	_camera.current = true
	_update_camera(0.0)

	# Leuchtender Ring am Boden unter dem aktiven Officer
	_active_ring = MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.56
	tm.outer_radius = 0.68
	_active_ring.mesh = tm
	var rm := StandardMaterial3D.new()
	rm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_active_ring.material_override = rm
	_active_ring.scale.y = 0.15
	_active_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_active_ring.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	add_child(_active_ring)

	_vision = VisionSystem.new()          # CanvasLayer 1: Abdunkelung
	add_child(_vision)
	var fx_layer := CanvasLayer.new()     # CanvasLayer 2: Effekte über dem Nebel
	fx_layer.layer = 2
	add_child(fx_layer)
	_fx = FxOverlay.new()
	fx_layer.add_child(_fx)
	_fx.camera = _camera
	_hud = Hud.new()                      # CanvasLayer 3: HUD
	add_child(_hud)
	_pause = PauseMenu.new()              # CanvasLayer 10: Pausemenü
	add_child(_pause)
	_pause.end_turn_requested.connect(request_hold)
	_pause.main_menu_requested.connect(_to_main_menu)
	# Bauart eines schon angeschlossenen Controllers für die Tastenanzeige ermitteln
	var pads := Input.get_connected_joypads()
	_set_pad_kind(pads[0] if not pads.is_empty() else -1)

	# Tastaturfokus sofort holen (beim Start aus dem Editor sonst erst nach einem Klick)
	get_window().grab_focus()
	_last_usec = Time.get_ticks_usec()
	if _menu_done:
		_start_intro()
	else:
		_open_menu()


# =============================================================================
#  Hauptmenü
# =============================================================================

## Vor dem ersten Einsatz: Menü über dem stehenden Spielbild. Simulation, HUD und
## Pausemenü ruhen, bis "Spiel starten" gewählt (und die Einweisung durch) ist.
func _open_menu() -> void:
	phase = Phase.MENU
	_hud.visible = false
	_pause.enabled = false
	_menu = MainMenuScript.new()
	add_child(_menu)
	_menu.start_requested.connect(_on_menu_start)


func _on_menu_start() -> void:
	_menu_done = true
	_menu.queue_free()
	_menu = null
	_hud.visible = true
	_pause.enabled = true
	_last_usec = Time.get_ticks_usec()
	_start_intro()


## Aus dem Pausemenü zurück ins Hauptmenü: Szene neu laden, Menü wieder zeigen.
func _to_main_menu() -> void:
	_menu_done = false
	TimeControl.override_scale = -1.0
	get_tree().reload_current_scene()


# =============================================================================
#  Intro: Officer 3 rammt die Eingangstür auf
# =============================================================================

func _start_intro() -> void:
	phase = Phase.INTRO
	_intro_t = 0.0
	_intro_hit = false
	TimeControl.override_scale = 1.0
	officers[2].ram.visible = true
	_hud.set_letterbox(true)
	_hud.show_card("ZUGRIFF", "Officer 3 rammt die Tür auf", COL_REALTIME, 0.0)


## Läuft in echter Zeit: zur Tür, Stoß, Tür fliegt auf, zurück auf die Startposition.
func _update_intro(real_dt: float) -> void:
	var o := officers[2]
	var home: Vector3 = Level.OFFICER_SPAWNS[2]
	var at_door := doors[0].center + Vector3(0.0, 0.0, 0.95)
	var t_go := 0.75
	var t_hit := 1.3
	var t_back := 1.55
	var before := o.global_position
	_intro_t += real_dt
	if _intro_t < t_go:
		o.global_position = home.lerp(at_door, smoothstep(0.0, t_go, _intro_t))
		o.set_yaw(lerp_angle(o.yaw, o.yaw_to(doors[0].center), 0.25))
	elif _intro_t < t_back:
		o.global_position = at_door
		o.set_yaw(PI)
		# Rammbock ausholen und zustoßen
		var k := clampf((_intro_t - t_go) / (t_hit - t_go), 0.0, 1.0)
		o.ram.position.z = 0.35 + (-0.25 * sin(k * PI) if k < 0.6 else 0.45 * (k - 0.6) / 0.4)
		if k > 0.5 and not _intro_hit:
			_intro_hit = true
			o.model.punch()
		if _intro_t >= t_hit and not doors[0].is_open:
			_open_door(0)
			_shake = 0.3
			_snd.play("impact", 0.6, 10.0)
	else:
		o.ram.position.z = 0.35
		o.global_position = at_door.lerp(home, smoothstep(t_back, INTRO_SECONDS, _intro_t))
		o.set_yaw(lerp_angle(o.yaw, PI, 0.2))
	o.speed = before.distance_to(o.global_position) / maxf(real_dt, 0.001)
	o.reset_physics_interpolation()
	if _intro_t >= INTRO_SECONDS:
		o.global_position = home
		o.set_yaw(PI)
		o.speed = 0.0
		o.ram.visible = false
		o.reset_physics_interpolation()
		_initial_doors = []
		for d in doors:
			_initial_doors.append(d.is_open)
		_hud.hide_card()
		rounds.begin_pass(_snapshot(), _alive_order())
		_start_turn()


func _spawn_actors() -> void:
	for i in Level.OFFICER_SPAWNS.size():
		var o := Officer.new()
		add_child(o)
		# eigenes Modell pro Rolle (CharacterModel.MODELS: officer_flash/_shield/_pierce)
		o.setup(i, "officer_" + Level.OFFICER_ROLES[i], OFFICER_COLORS[i], Actor.LAYER_OFFICER, str(i + 1))
		o.global_position = Level.OFFICER_SPAWNS[i]
		o.set_yaw(PI)
		o.apply_tweaks()
		o.ammo = o.max_ammo
		o.set_role(Level.OFFICER_ROLES[i])
		if i == 0:
			o.set_crouched(true)        # der Vorderste startet geduckt
		if i == 2:
			o.build_ram()
		officers.append(o)
		for list in [_officer_lasers, _reflect_lasers]:
			var beam := LaserBeam.new(LASER_OFFICER)
			add_child(beam)
			list.append(beam)

	for i in Level.ENEMY_SPOTS.size():
		# Startplatz pro Mission zufällig; innerhalb der Mission bleibt alles deterministisch
		var spots: Array = Level.ENEMY_SPOTS[i]
		var def: Dictionary = spots[_rng.randi() % spots.size()]
		var e := Enemy.new()
		e.game = self
		add_child(e)
		e.setup(i, "enemy", ENEMY_COLOR, Actor.LAYER_ENEMY)
		e.apply_tweaks()
		e.global_position = def.pos
		e.set_yaw(e.yaw_to(def.look))
		e.home_yaw = e.yaw
		e.patrol = def.get("patrol", [])
		enemies.append(e)
		var beam := LaserBeam.new(LASER_ENEMY)
		add_child(beam)
		_enemy_lasers.append(beam)

	for i in Level.HOSTAGES.size():
		var h := Actor.new()
		add_child(h)
		h.setup(i, "hostage", HOSTAGE_COLOR, Actor.LAYER_HOSTAGE)
		h.global_position = Level.HOSTAGES[i]
		h.set_yaw(i * 2.1)
		hostages.append(h)

	_all.assign(officers)
	_all.append_array(enemies)
	_all.append_array(hostages)


# =============================================================================
#  Checkpoints (Zeit-"Rückspulen" = Weltzustand wiederherstellen)
# =============================================================================

func _snapshot() -> Dictionary:
	var states := []
	for a in _all:
		states.append(a.get_state())
	var open := []
	for d in doors:
		open.append(d.is_open)
	return {"actors": states, "doors": open}


func _restore(cp: Dictionary) -> void:
	for i in _all.size():
		_all[i].set_state(cp.actors[i])
	for i in doors.size():
		doors[i].set_open(cp.doors[i], true)
	_door_req = false
	_crouch_req = false
	_roll_req = false
	_cut = {}
	tick = 0
	_settle = 2
	_fire_req = false
	_hold_req = false
	_action_latch = false
	_action_prev = false
	_bullets.clear()
	_grenades.clear()
	_fx.clear()
	# Welt-Aufzeichnung des nächsten Zugs fürs Rückspulen neu beginnen
	_rw_tracks = []
	for a in _all:
		_rw_tracks.append(PackedFloat32Array())
	_rw_doors = []


func _alive_order() -> Array[int]:
	var order: Array[int] = []
	for o in officers:
		if o.alive:
			order.append(o.idx)
	return order


# =============================================================================
#  Phasen
# =============================================================================

func _start_turn() -> void:
	# Ende des vorigen Zugs in diesem Durchlauf (0 beim ersten Zug)
	var prev_end := rounds.longest_track()
	_restore(rounds.checkpoint)
	active = officers[rounds.active_idx()]
	_build_ghosts()
	_track = rounds.begin_turn()
	phase = Phase.PLAYING
	_solo = rounds.order.size() == 1
	_solo_end = -1
	if _solo:
		_segment = RoundSystem.Segment.new()
		for a in _all:
			_segment.tracks.append(PackedFloat32Array())
	_takeover_tick = maxi(0, prev_end - TAKEOVER_LEAD_TICKS)
	_taken = false
	_count_left = -1.0
	_count_digit = 0
	# Während des Countdowns vergeht (wegen des Abbremsens) so viel Spielzeit:
	var ramp_ticks := int(COUNT_TOTAL * (TimeControl.realtime_speed + TimeControl.rest_scale()) * 0.5 * TimeControl.SIM_HZ)
	_count_start = maxi(0, _takeover_tick - ramp_ticks)
	# Der Vorlauf läuft im Echtzeit-Tempo (realtime_speed), der Countdown dauert
	# COUNT_TOTAL echte Sekunden – zusammen die Gesamtdauer bis zur Übernahme
	_lead_total = float(_count_start) / (TimeControl.SIM_HZ * TimeControl.realtime_speed) + COUNT_TOTAL
	_hud.set_panel_text("")
	_hud.set_freeze(false)
	_hud.hide_card()
	_hud.set_letterbox(_takeover_tick > 0)
	if _count_start > 0:
		# Vorlauf: bisherige Aufzeichnungen in Echtzeit, noch keine Kontrolle
		_hud.show_card("ECHTZEIT", "Bisheriger Ablauf  ·  gleich übernimmst du Officer %d" % (active.idx + 1),
				COL_REALTIME, 0.0)


## Vorschau-Daten aus den Aufzeichnungen der Officer, die in diesem Durchlauf schon dran waren.
func _build_ghosts() -> void:
	_ghosts = []
	for idx in rounds.tracks:
		var tr: RoundSystem.Track = rounds.tracks[idx]
		var n := tr.length()
		if n == 0:
			continue
		var pts := []
		for t in range(0, n, GHOST_STEP):
			pts.append({"tick": t, "pos": _track_pos(tr, t)})
		pts.append({"tick": n - 1, "pos": _track_pos(tr, n - 1)})
		var shots := []
		for sh in tr.shots:
			shots.append({"tick": sh.tick, "pos": _track_pos(tr, sh.tick) + Vector3(0, 0.95, 0), "dir": sh.dir})
		_ghosts.append({"color": officers[idx].color, "pts": pts, "shots": shots})


func _track_pos(tr: RoundSystem.Track, t: int) -> Vector3:
	var b := t * RoundSystem.Track.STRIDE
	return Vector3(tr.frames[b], 0.05, tr.frames[b + 1])


## Vorlauf und Countdown (pro Frame, in echter Zeit). Die Simulation läuft bis zum
## Übernahme-Tick und wartet dort, bis der Countdown bei "GO GO GO" angekommen ist.
func _update_countdown(real_dt: float) -> void:
	if _count_left < 0.0:
		TimeControl.override_scale = TimeControl.realtime_speed
		if tick >= _count_start and _settle == 0:
			_count_left = COUNT_TOTAL
			if _takeover_tick > 0 and TimeControl.rest_scale() < 0.95:
				_snd.play("slowdown")
		else:
			return
	_count_left -= real_dt
	if _count_left <= 0.0:
		_takeover_tick = tick
		_take_control()
		return
	var digit := ceili(_count_left / COUNT_STEP)
	if digit != _count_digit:
		_count_digit = digit
		_snd.play("beep")
		_hud.hide_card()
		_hud.show_big(str(digit), COL_GO, COUNT_STEP)
	var k := 1.0 - _count_left / COUNT_TOTAL
	TimeControl.override_scale = lerpf(TimeControl.realtime_speed, TimeControl.rest_scale(), smoothstep(0.0, 1.0, k))


## Der Spieler bekommt die Kontrolle über den aktiven Officer.
func _take_control() -> void:
	_taken = true
	_count_left = -1.0
	_fire_req = false
	_hold_req = false
	_action_latch = false
	_action_prev = false
	TimeControl.override_scale = -1.0
	_hud.set_letterbox(false)
	_hud.hide_card()
	_go_step = 0
	_go_t = 0.0
	_pad_aim_dir = Vector3.ZERO
	_pad_aim_dist = PAD_THROW_DEFAULT
	_roll_req = false
	if _solo:
		_hud.show_card("LETZTER OFFICER", "Keine Runden mehr  ·  ab jetzt läuft alles ohne Zurückspulen durch",
				COL_DANGER, 3.0)
	_fx.add_pulse(active.global_position, active.color.lightened(0.5))


## "GO" – "GO GO" – "GO GO GO": drei kurze Einblendungen nacheinander.
func _update_go(real_dt: float) -> void:
	if _go_step >= 3:
		return
	_go_t -= real_dt
	if _go_t <= 0.0:
		_go_step += 1
		_go_t = 0.17
		_hud.show_big(" ".join(PackedStringArray(["GO", "GO", "GO"].slice(0, _go_step))), COL_GO,
				0.17 if _go_step < 3 else 0.6)
		_snd.play("go", 0.8 + 0.12 * _go_step)


## Schuss gefallen / Zug beendet: Szene einfrieren, kurz zeigen, dann weiter.
## Der auslösende Schuss wird hier NICHT aufgelöst – die Kugel fliegt erst, wenn der
## Schuss in den folgenden Zügen bzw. der Auswertung nachgespielt wird.
func _begin_break(title: String, reason: String, color: Color, seconds := BREAK_SECONDS) -> void:
	phase = Phase.BREAK
	_snd.play("freeze")
	_break_left = seconds
	_go_step = 3
	TimeControl.override_scale = -1.0
	var next := "Auswertung"
	if rounds.turn + 1 < rounds.order.size():
		next = "Officer %d" % (rounds.order[rounds.turn + 1] + 1)
	_hud.set_letterbox(false)
	_hud.set_freeze(true)
	_hud.show_card(title, "%s\nAls Nächstes: %s" % [reason, next], color, 0.0)


func _next_turn() -> void:
	_hud.hide_card()
	_hud.set_freeze(false)
	if rounds.advance_turn():
		_start_turn()
	else:
		_start_resolve()


## Nach dem Freeze: der gerade gespielte Zug läuft sichtbar rückwärts bis Tick 0.
## Danach geht es weiter wie bisher (nächster Zug bzw. Auswertung ab Checkpoint).
func _start_rewind() -> void:
	var n := 0
	if not _rw_tracks.is_empty():
		n = _rw_tracks[0].size() / RoundSystem.Segment.STRIDE
	if n < 2 or REWIND_SPEED <= 0.0:
		_next_turn()
		return
	phase = Phase.REWIND
	_rw_pos = float(n - 1)
	# Rate so, dass das Rückspulen mindestens REWIND_MIN_SECONDS und höchstens
	# REWIND_MAX_SECONDS echte Sekunden dauert
	var lo := n / maxf(REWIND_MAX_SECONDS, 0.1)
	var hi := maxf(lo, n / maxf(REWIND_MIN_SECONDS, 0.05))
	_rw_rate = clampf(REWIND_SPEED * TimeControl.SIM_HZ, lo, hi)
	_bullets.clear()
	_grenades.clear()
	_fx.clear()
	_hud.set_freeze(false)
	_hud.set_rewind(true)
	_hud.set_letterbox(true)
	_hud.show_card("ZURÜCKSPULEN", "Zurück zum Start des Durchlaufs", COL_REALTIME, 0.0)
	_snd.play("rewind")


## Rückspul-Schritt (pro Frame, echte Zeit): Figuren fahren ihre aufgezeichneten
## Positionen rückwärts ab, Türen schließen sich wieder, die Uhr läuft rückwärts.
func _update_rewind(real_dt: float) -> void:
	var prev_pos := _rw_pos
	_rw_pos -= _rw_rate * real_dt
	if _rw_pos <= 0.0:
		# _next_turn stellt den Checkpoint ohnehin exakt wieder her
		_hud.set_letterbox(false)
		_hud.hide_card()
		_hud.set_rewind(false)
		_next_turn()
		return
	var t := int(_rw_pos)
	var b := t * RoundSystem.Segment.STRIDE
	for i in _all.size():
		var a: Actor = _all[i]
		var tr: PackedFloat32Array = _rw_tracks[i]
		var before := a.global_position
		a.apply_frame(tr[b], tr[b + 1], tr[b + 2])
		var is_alive := tr[b + 3] > 0.5
		if a.alive != is_alive:
			a.set_alive(is_alive)         # Tote stehen beim Rückspulen wieder auf
		a.apply_flags(int(tr[b + 4]))
		# Spielgeschwindigkeit fürs Lauf-Animation-Tempo
		a.speed = before.distance_to(a.global_position) / maxf((prev_pos - _rw_pos) / TimeControl.SIM_HZ, 0.0001)
		a.reset_physics_interpolation()
	for d in _rw_doors:
		if d.tick > t and doors[d.door].is_open:
			doors[d.door].set_open(false)   # animiert schließen
	tick = t                            # Uhr im HUD läuft rückwärts


## Auswertung: alle Aufzeichnungen des Durchlaufs laufen gemeinsam ohne Unterbrechung.
func _start_resolve() -> void:
	_restore(rounds.checkpoint)
	active = null
	phase = Phase.RESOLVE
	rounds.begin_resolve()
	_segment = RoundSystem.Segment.new()
	for a in _all:
		_segment.tracks.append(PackedFloat32Array())
	_resolve_end = rounds.longest_track() + RESOLVE_TAIL_TICKS
	TimeControl.override_scale = RESOLVE_TIME_SCALE
	_hud.set_letterbox(true)
	_hud.show_card("AUSWERTUNG", "Alle Züge dieses Durchlaufs laufen gemeinsam ab", Color.WHITE, 1.8)


func _finish_resolve() -> void:
	_segment.ticks = tick
	if _hostage_lost():
		_fail("Eine Geisel wurde getötet.")
	elif _count_alive(officers) == 0:
		_fail("Das gesamte Team ist ausgefallen.")
	else:
		rounds.timeline.append(_segment)
		if _count_alive(enemies) == 0:
			_start_final_replay()
		else:
			rounds.begin_pass(_snapshot(), _alive_order())
			_start_turn()


func _fail(reason: String) -> void:
	phase = Phase.FAILED
	TimeControl.override_scale = -1.0
	_hud.hide_card()
	_hud.set_letterbox(false)
	_hud.set_rewind(false)
	_hud.set_panel_text("MISSION FAILED\n\n%s\n\n[R / %s] Durchlauf wiederholen      [N / %s] Neue Mission" % [reason, _pad_lbl("a"), _pad_lbl("y")])


## Abschluss-Replay: die Timeline aller Auswertungen in Echtzeit, ohne Sichtkegel.
func _start_final_replay() -> void:
	phase = Phase.FINAL_REPLAY
	active = null
	_rp_seg = 0
	_rp_tick = 0
	_rp_elapsed = 0
	_rp_focus = _level_center()
	_rp_zoom = 1.0
	_rp_slow = 0.0
	_rp_final_done = false
	_bullets.clear()
	_grenades.clear()
	_fx.clear()
	TimeControl.override_scale = TimeControl.realtime_speed
	_vision.enabled = false
	for i in doors.size():
		doors[i].set_open(_initial_doors[i], true)
	_hud.set_panel_text("")
	_hud.set_rewind(false)
	_hud.set_letterbox(true)
	_hud.show_card("EINSATZ-REPLAY", "Der gesamte Einsatz in Echtzeit", COL_REALTIME, 1.5)


func _show_results() -> void:
	phase = Phase.RESULTS
	var team_shots := 0
	var enemy_shots := 0
	for seg in rounds.timeline:
		for s in seg.shots:
			if s.enemy:
				enemy_shots += 1
			else:
				team_shots += 1
	var seconds := float(rounds.total_ticks()) / TimeControl.SIM_HZ
	_hud.set_letterbox(false)
	# Wertung: je ein Stern für ein Ziel
	var max_shots := enemies.size() + STAR_EXTRA_SHOTS
	var passes := rounds.timeline.size()
	var goals := [
		[seconds <= STAR_SECONDS, "Einsatzdauer %.1f s  (Ziel: höchstens %.0f s)" % [seconds, STAR_SECONDS]],
		[team_shots <= max_shots, "Schüsse Team %d  (Ziel: höchstens %d)" % [team_shots, max_shots]],
		[passes <= STAR_PASSES, "Durchläufe %d  (Ziel: höchstens %d)" % [passes, STAR_PASSES]],
	]
	var stars := ""
	var lines := ""
	for g in goals:
		stars += "★ " if g[0] else "☆ "
		lines += ("★  " if g[0] else "☆  ") + g[1] + "\n"
	_hud.set_panel_text((
			"EINSATZ BEENDET\n\n%s\n\n%s\n"
			+ "Schüsse Gegner: %d\n"
			+ "Geiseln gerettet: %d / %d\n"
			+ "Officer einsatzfähig: %d / %d\n\n"
			+ "[R / %s] Replay erneut      [N / %s] Neue Mission") % [
			stars.strip_edges(), lines, enemy_shots,
			_count_alive(hostages), hostages.size(),
			_count_alive(officers), officers.size(), _pad_lbl("a"), _pad_lbl("y")])


# =============================================================================
#  Simulation (fester Zeitschritt)
# =============================================================================

func _physics_process(_delta: float) -> void:
	if _hitstop > 0.0:
		return                          # Bildstopp nach einem Treffer
	if _settle > 0:
		_settle -= 1
		return
	# Übernahme-Tick erreicht, Countdown läuft noch: die Welt wartet
	if phase == Phase.PLAYING and not _taken and tick >= _takeover_tick:
		return
	match phase:
		Phase.PLAYING, Phase.RESOLVE:
			_sim_tick(TimeControl.DT)
		Phase.FINAL_REPLAY:
			_replay_tick()


func _sim_tick(dt: float) -> void:
	# --- Officer: aktiver per Eingabe, frühere per Aufzeichnung, übrige warten ---
	for o in officers:
		if not o.alive:
			continue
		if o == active:
			if _taken:
				var inp := _read_input()
				var held: bool = inp.get("action", false) or _action_latch
				var pressed := held and not _action_prev
				_action_prev = held
				_action_latch = false
				_last_aim = inp.aim
				if _door_req:
					_door_req = false
					var di := _near_door(o)
					if di >= 0:
						_track.doors.append({"tick": tick, "door": di})
						_open_door(di)
				var crouch := _crouch_req
				_crouch_req = false
				var roll: bool = _roll_req or inp.get("roll", false)
				_roll_req = false
				var shield_before := o.shield_up
				var thrown := o.control_tick(inp.move, inp.aim, inp.get("aim_hold", false), held, pressed, crouch, roll, dt,
						inp.get("pad_turn", -1.0))
				_track.add_frame(o)
				if thrown:
					var target := _grenade_target(o, inp.aim)
					_track.throws.append({"tick": tick, "target": target})
					if GRENADE_ENDS_TURN and not _solo:
						# Nahaufnahme: Wurfbewegung, Kamera auf den Werfer, Granate auf ihrer echten Flugbahn
						_cut = {"kind": "grenade", "from": o.eye(), "to": target, "actor": o,
							"path": _grenade_preview(o.eye(), target)}
						_cam_focus = o.global_position
						o.model.throw()
						_begin_break("GRANATE GEWORFEN", "Officer %d  ·  Wirkung ungewiss" % (o.idx + 1), COL_FREEZE, ABILITY_CUT_SECONDS)
						return
					o.model.throw()
					_throw_grenade(o.eye(), target, false)
				if SHIELD_ENDS_TURN and not _solo and o.shield_up and not shield_before:
					# Nahaufnahme: Kamera auf den Officer, der das Schild hebt
					_cut = {"kind": "shield", "actor": o}
					_cam_focus = o.global_position
					_begin_break("SCHILD OBEN", "Officer %d deckt ab jetzt nach vorn" % (o.idx + 1), COL_FREEZE, ABILITY_CUT_SECONDS)
					return
			else:
				_track.add_frame(o)
			if _taken and _hold_req:
				if _solo:
					_hold_req = false         # ohne Runden gibt es keinen Zug zu beenden
				else:
					_begin_break("POSITION GEHALTEN", "Officer %d sichert" % (o.idx + 1), Color.WHITE)
					return
			if _taken and _fire_req:
				_fire_req = false
				if o.can_fire():
					o.ammo -= 1
					var dir := o.roll_shot_dir(_rng)
					var pierce := o.pierce_mode       # Durchschuss: Kugel geht durch Wände
					if _solo:
						_fire_bullet(o, dir, false, pierce)  # ohne Runden fliegt die Kugel sofort
					else:
						_track.shots.append({"tick": tick, "dir": dir, "pierce": pierce})
						_shot_fx(o, dir)
						# Nahaufnahme: Mündungsfeuer und die Kugel auf ihrem ersten Meter
						_cut = {"kind": "shot", "from": o.eye(), "dir": dir}
						_cam_focus = o.global_position
						_begin_break("FREEZE", "Officer %d hat geschossen  ·  Treffer ungewiss" % (o.idx + 1),
								COL_FREEZE, SHOT_CUT_SECONDS)
						return
		elif rounds.tracks.has(o.idx):
			var tr: RoundSystem.Track = rounds.tracks[o.idx]
			if tick < tr.length():
				var b := tick * RoundSystem.Track.STRIDE
				o.apply_frame(tr.frames[b], tr.frames[b + 1], tr.frames[b + 2])
				o.apply_flags(int(tr.frames[b + 3]))
			elif tick == tr.length():
				# danach: letzte Position und Blickrichtung halten; ein Schild bleibt oben
				o.apply_flags(o.flags() & ~Officer.FLAG_ROLL)
			for s in tr.doors:
				if s.tick == tick:
					_open_door(s.door)
			for s in tr.throws:
				if s.tick == tick and o.grenades > 0:
					o.grenades -= 1
					o.model.throw()          # nur Optik: Wurfbewegung der aufgezeichneten Figur
					_throw_grenade(o.eye(), s.target, false)
			for s in tr.shots:
				if s.tick == tick and o.ammo > 0:
					o.ammo -= 1
					_fire_bullet(o, s.dir, false, s.get("pierce", false))

	_push_bodies()

	# --- Gegner: jede Runde live simuliert ---
	for e in enemies:
		if e.alive:
			e.sim_tick(dt)
			if phase == Phase.BREAK:
				return

	_step_bullets(dt)
	_step_grenades(dt)

	if phase == Phase.PLAYING and not _solo and not active.alive:
		_begin_break("OFFICER %d GEFALLEN" % (active.idx + 1), "Getroffen von einer Kugel", COL_DANGER)
		return

	for a in _all:
		a.update_motion(dt)

	if _recording():
		_record_world(_segment.tracks)
	elif phase == Phase.PLAYING:
		_record_world(_rw_tracks)

	tick += 1
	if phase == Phase.RESOLVE and tick >= _resolve_end and _bullets.is_empty() and _grenades.is_empty():
		_finish_resolve()
	elif phase == Phase.PLAYING and _solo:
		_check_solo_end()


## Wird das Geschehen gerade fürs Abschluss-Replay aufgezeichnet? In der Auswertung
## und – ohne Runden – direkt beim Spielen des letzten Officers.
func _recording() -> bool:
	return phase == Phase.RESOLVE or (phase == Phase.PLAYING and _solo)


## Ohne Runden (letzter Officer): Ist der Einsatz entschieden? Dann läuft die Welt noch
## SOLO_TAIL_TICKS in Echtzeit weiter (Figuren fallen, Kugeln schlagen ein), danach
## folgt Fehlschlag oder Abschluss-Replay.
func _check_solo_end() -> void:
	if _solo_end < 0:
		if active.alive and not _hostage_lost() and _count_alive(enemies) > 0:
			return
		_solo_end = tick + SOLO_TAIL_TICKS
		TimeControl.override_scale = TimeControl.realtime_speed
	if tick < _solo_end or not _bullets.is_empty() or not _grenades.is_empty():
		return
	if not active.alive:
		_fail("Der letzte Officer ist ausgefallen.")
	elif _hostage_lost():
		_fail("Eine Geisel wurde getötet.")
	else:
		_segment.ticks = tick
		rounds.timeline.append(_segment)
		_start_final_replay()


## Wegschieben: Officer schieben Kollegen und Geiseln, die ihnen im Weg stehen, beiseite
## (an Wänden und Möbeln gleiten sie entlang). So bleibt niemand in engen Gängen stecken,
## und man kann einen Kollegen aus der Schusslinie einer heranfliegenden Kugel schieben.
## Geschoben werden nur Figuren, die gerade NICHT von einer Aufzeichnung gesteuert werden:
##  - Geiseln
##  - Officer, deren Zug in diesem Durchlauf schon vorbei ist und die Position halten
## Der gesteuerte Officer selbst und Officer, die noch ihre Aufzeichnung abfahren, werden
## nicht geschoben (eine Aufzeichnung würde die Position ohnehin überschreiben).
## Wer im Hechtsprung ist, springt über Geduckte hinweg statt sie zu schieben.
## Feste Reihenfolge, nur Positionen als Eingabe: bleibt in jedem Zug deterministisch.
func _push_bodies() -> void:
	var pushable: Array[Actor] = []
	for o in officers:
		if o.alive and o != active and rounds.tracks.has(o.idx) \
				and tick >= (rounds.tracks[o.idx] as RoundSystem.Track).length():
			pushable.append(o)
	for h in hostages:
		if h.alive:
			pushable.append(h)
	for p in pushable:
		for q in officers:
			if q == p or not q.alive:
				continue
			if q.rolling and p is Officer and (p as Officer).crouched:
				continue
			var d := p.global_position - q.global_position
			d.y = 0.0
			var dist := d.length()
			if dist >= PUSH_GAP:
				continue
			var away := d / dist if dist > 0.001 else q.forward()
			p.move_step(away * (PUSH_GAP - dist))


## Welt-Zustand eines Ticks an eine Aufzeichnung anhängen: pro Figur x, z, yaw,
## alive, flags (Schrittweite RoundSystem.Segment.STRIDE). PackedFloat32Array ist
## ein Wert-Typ und wird deshalb nach dem append zurückgeschrieben.
func _record_world(tracks: Array) -> void:
	for i in _all.size():
		var a := _all[i]
		var t: PackedFloat32Array = tracks[i]
		t.append(a.global_position.x)
		t.append(a.global_position.z)
		t.append(a.yaw)
		t.append(1.0 if a.alive else 0.0)
		t.append(float(a.flags()))
		tracks[i] = t


## Wird von der Gegner-KI aufgerufen, wenn sie abdrückt.
## Bekannter Schuss (fiel schon in einem früheren Zug) -> Kugel fliegt los.
## Neuer Schuss -> friert die Szene ein und beendet den Zug.
## execute: Schuss auf eine Geisel (abgelaufene Frist).
func enemy_fire(e: Enemy, dir: Vector3, execute := false) -> void:
	if phase == Phase.RESOLVE or _solo or not ENEMY_SHOT_ENDS_TURN or rounds.match_enemy_shot(e.idx, tick):
		_fire_bullet(e, dir, execute)
	else:
		rounds.add_known_shot(e.idx, tick)
		_shot_fx(e, dir)
		if execute:
			_begin_break("FREEZE", "Frist abgelaufen  ·  ein Gegner schießt auf die Geisel!", COL_DANGER)
		else:
			_begin_break("FREEZE", "Ein Gegner feuert!", COL_DANGER)


## Echte Kugel mit Flugzeit abfeuern.
## Gegnerkugeln fliegen an Geiseln vorbei (er schießt über sein "Schild" hinweg),
## außer bei der Hinrichtung (hit_hostages).
## pierce: Durchschuss – die Kugel geht durch bis zu PIERCE_MAX_WALLS Wände, Möbel oder
## Türen. Metall stoppt sie (bzw. lässt sie abprallen) wie jede andere Kugel.
func _fire_bullet(shooter: Actor, dir: Vector3, hit_hostages := false, pierce := false) -> void:
	var by_enemy := shooter is Enemy
	# high: aus dem Stand geschossen – fliegt über Kisten und über geduckte Kollegen hinweg
	var high := not (shooter is Officer and (shooter as Officer).crouched)
	var mask := _bullet_mask(by_enemy and not hit_hostages)
	if not high:
		mask |= Actor.LAYER_CRATE
	var b := {"pos": shooter.eye(), "prev": shooter.eye(), "dir": dir, "skip": [shooter.get_rid()],
		"origin": shooter.eye(), "mask": mask, "high": high,
		"enemy": by_enemy, "left": SHOT_RANGE, "leg": SHOT_RANGE, "bounces": 0,
		"ghost": false, "hit_actor": false, "rec": null,
		"pierce": PIERCE_MAX_WALLS if pierce else 0}
	if _recording():
		# fürs Abschluss-Replay merken; Flugstrecke und Trefferart werden beim Einschlag ergänzt
		var rec := {"tick": tick, "who": _all.find(shooter), "from": b.pos, "dir": dir,
			"enemy": by_enemy, "dist": SHOT_RANGE, "hit_actor": false}
		_segment.shots.append(rec)
		b.rec = rec
	_bullets.append(b)
	_shot_fx(shooter, dir)
	if not by_enemy:
		for e in enemies:
			if e.alive:
				e.hear(b.pos)


## Mündungsfeuer, Schuss-Animation, kleiner Kamera-Ruck.
func _shot_fx(shooter: Actor, dir: Vector3) -> void:
	shooter.model.shoot()
	_fx.add_muzzle(shooter.eye() + dir * 0.95, dir, shooter is Enemy)
	_shake = 0.12
	_snd.play("shot_enemy" if shooter is Enemy else "shot_team", _pitch())
	if shooter is Officer:
		_rumble(0.5, 0.0, 0.07)


## Tonhöhe passend zum Spieltempo: in Zeitlupe klingen Schüsse tiefer und gedehnt.
func _pitch() -> float:
	return clampf(0.5 + 0.5 * TimeControl.current_scale(), 0.5, 1.0)


func _bullet_mask(skip_hostages: bool) -> int:
	return Actor.MASK_BULLET & ~Actor.LAYER_HOSTAGE if skip_hostages else Actor.MASK_BULLET


# --- Türen --------------------------------------------------------------------------

## Index der nächsten geschlossenen Tür in Reichweite, sonst -1.
func _near_door(o: Actor) -> int:
	var best := -1
	var best_d := DOOR_REACH
	for i in doors.size():
		var d := o.global_position.distance_to(doors[i].center)
		if not doors[i].is_open and d < best_d:
			best = i
			best_d = d
	return best


## Tür aufstoßen. Das ist laut: Gegner in Hörweite drehen sich zur Tür.
func _open_door(i: int) -> void:
	if doors[i].is_open:
		return
	doors[i].set_open(true)
	_snd.play("door", _pitch())
	if _recording():
		_segment.doors.append({"tick": tick, "door": i})
	elif phase == Phase.PLAYING:
		_rw_doors.append({"tick": tick, "door": i})
	for e in enemies:
		if e.alive:
			e.hear(doors[i].center, DOOR_NOISE)


## Kugeln einen Tick weiterbewegen; erste Kollision auf der Strecke zählt.
## Figuren sterben mit einem Treffer.
func _step_bullets(dt: float) -> void:
	var step := BULLET_SPEED * dt
	for i in range(_bullets.size() - 1, -1, -1):
		var b: Dictionary = _bullets[i]
		b.prev = b.pos
		if b.ghost:
			# Abschluss-Replay: nur Optik, Strecke und Treffer sind aufgezeichnet
			var move := minf(step, b.left)
			b.pos += b.dir * move
			b.left -= move
			if b.left <= 0.0:
				_impact(b.pos, b.hit_actor)
				if b.hit_actor:
					_hit_feedback(b.pos, not b.enemy)
				_bullets.remove_at(i)
			continue
		var to: Vector3 = b.pos + b.dir * step
		if not b.enemy:
			# knapper Fehlschuss: Gegner gehen in Deckung
			for e in enemies:
				if e.alive and Geometry3D.get_closest_point_to_segment(e.eye(), b.pos, to) \
						.distance_to(e.eye()) < NEAR_MISS:
					e.suppress(b.origin)
		var hit := _trace(b.pos, to, b.skip, b.mask)
		while hit:
			if hit.collider is Officer and _passes_over(b, hit):
				b.skip.append(hit.collider.get_rid())
			elif b.pierce > 0 and _pierceable(hit.collider):
				# Durchschuss: Wand/Möbel/Tür wird durchschlagen
				b.pierce -= 1
				b.skip.append(hit.collider.get_rid())
				_impact(hit.position, false)
			else:
				break
			hit = _trace(b.pos, to, b.skip, b.mask)
		if hit:
			var on_actor: bool = hit.collider is Actor
			var flown: float = b.pos.distance_to(hit.position)
			if b.rec:
				b.rec.dist = b.leg - b.left + flown
				b.rec.hit_actor = on_actor
			var n: Vector3 = hit.normal
			n.y = 0.0
			if _is_metal(hit.collider) and b.bounces < MAX_BOUNCES and n.length() > 0.1:
				# Abpraller: Einfallswinkel = Ausfallswinkel. Danach kann die Kugel
				# auch den Schützen selbst treffen.
				n = n.normalized()
				_impact(hit.position, false)
				_snd.play("ricochet", _pitch())
				b.pos = hit.position + n * 0.02
				b.prev = b.pos
				b.dir = (b.dir as Vector3).bounce(n)
				b.left -= flown
				b.leg = b.left
				b.bounces += 1
				b.skip = []
				if b.rec:
					# fürs Abschluss-Replay: neuer Abschnitt ohne Mündungsfeuer
					var rec := {"tick": tick, "who": -1, "from": b.pos, "dir": b.dir,
						"enemy": b.enemy, "dist": b.left, "hit_actor": false}
					_segment.shots.append(rec)
					b.rec = rec
				continue
			if on_actor:
				hit.collider.kill()
				_hit_feedback(hit.position, hit.collider is Enemy)
			_impact(hit.position, on_actor)
			_bullets.remove_at(i)
		else:
			b.pos = to
			b.left -= step
			if b.left <= 0.0:
				_bullets.remove_at(i)


## Fliegt die Kugel über diesen (geduckten) Officer hinweg?
##  - stehende Kollegen schießen über Geduckte
##  - wer geduckt direkt hinter einer Kiste sitzt, ist aus dieser Richtung nicht zu treffen
func _passes_over(b: Dictionary, hit: Dictionary) -> bool:
	var o := hit.collider as Officer
	if not o.crouched:
		return false
	if b.high and not b.enemy:
		return true
	var p := Vector3(hit.position.x, Level.CRATE_H * 0.5, hit.position.z)
	return not _ray(p, p - b.dir * CROUCH_COVER_REACH, Actor.LAYER_CRATE).is_empty()


## Kann eine Durchschuss-Kugel dieses Hindernis durchschlagen? Alles aus der Welt
## (Wände, Möbel, Kisten, Türen) außer Metall; Figuren und Schilde nicht.
func _pierceable(collider: Object) -> bool:
	return collider != null and not (collider is Actor) and not collider.get_meta("metal", false)


func _is_metal(collider: Object) -> bool:
	return collider != null and not (collider is Actor) and collider.get_meta("metal", false)


## Erste Kollision auf der Strecke: Welt, Figuren oder ein erhobenes Schild.
## Das Schild ist eine Strecke quer vor dem Officer (reine Geometrie, kein Physik-Körper).
## Liefert {} oder {position, normal, collider (null beim Schild)}.
## skip: RIDs von Figuren, die ignoriert werden (Schütze, überflogene Geduckte).
func _trace(from: Vector3, to: Vector3, skip: Array, mask := Actor.MASK_BULLET) -> Dictionary:
	var res := {}
	var best := INF
	var hit := _ray(from, to, mask, skip)
	if hit:
		best = from.distance_to(hit.position)
		res = {"position": hit.position, "normal": hit.normal, "collider": hit.collider}
	for o in officers:
		if not o.alive or not o.shield_up or o.get_rid() in skip:
			continue
		var c := o.shield_center()
		var s := o.shield_side() * Officer.SHIELD_HALF_WIDTH
		var p = Geometry2D.segment_intersects_segment(Vector2(from.x, from.z), Vector2(to.x, to.z),
				Vector2(c.x - s.x, c.z - s.z), Vector2(c.x + s.x, c.z + s.z))
		if p != null:
			var pos := Vector3(p.x, from.y, p.y)
			var d := from.distance_to(pos)
			if d < best:
				best = d
				res = {"position": pos, "normal": Vector3.ZERO, "collider": null}
	return res


# --- Blendgranate ------------------------------------------------------------------

## Zielpunkt des ersten Aufkommens: Richtung Mauszeiger, begrenzt durch die Wurfweite.
func _grenade_target(o: Officer, aim: Vector3) -> Vector3:
	var from := o.eye()
	var d := Vector3(aim.x - from.x, 0.0, aim.z - from.z)
	var dir := d.normalized() if d.length() > 0.01 else o.forward()
	return from + dir * clampf(d.length(), 0.6, GRENADE_RANGE)


## Neue Granate im Wurfbogen: Startgeschwindigkeit so, dass sie ohne Hindernis am Ziel aufkommt.
func _make_grenade(from: Vector3, target: Vector3, ghost: bool) -> Dictionary:
	var d := Vector3(target.x - from.x, 0.0, target.z - from.z)
	var t := maxf(0.3, d.length() / GRENADE_SPEED)
	var vy := (0.5 * GRENADE_GRAVITY * t * t - (from.y - 0.08)) / t
	return {"pos": from, "vel": d / t + Vector3.UP * vy, "t": 0.0, "fuse": -1.0, "ghost": ghost}


## Einen Zeitschritt fliegen: Schwerkraft, Abprallen an Wänden/Möbeln und am Boden.
## Liefert true, wenn die Granate in diesem Schritt auf dem Boden aufgekommen ist.
func _grenade_step(g: Dictionary, dt: float) -> bool:
	var v: Vector3 = g.vel
	v.y -= GRENADE_GRAVITY * dt
	var hv := Vector3(v.x, 0.0, v.z)
	var pos: Vector3 = g.pos
	if hv.length() > 0.01:
		var to := pos + hv * dt
		var hit := _ray(pos, to, Actor.LAYER_WORLD)
		var n: Vector3 = hit.normal if hit else Vector3.ZERO
		n.y = 0.0
		if hit and n.length() > 0.1:
			n = n.normalized()
			hv = hv.bounce(n) * GRENADE_KEEP
			pos = hit.position + n * 0.03
		else:
			pos = to
	pos.y += v.y * dt
	var landed := false
	if pos.y <= 0.08:
		pos.y = 0.08
		if v.y < -0.8:
			v.y = -v.y * GRENADE_BOUNCE
			hv *= GRENADE_KEEP
			landed = true
		else:
			v.y = 0.0
			hv *= pow(0.03, dt)          # ausrollen
	g.pos = pos
	g.vel = hv + Vector3.UP * v.y
	return landed


func _throw_grenade(from: Vector3, target: Vector3, ghost: bool) -> void:
	if _recording():
		_segment.grenades.append({"tick": tick, "from": from, "to": target})
	_grenades.append(_make_grenade(from, target, ghost))


## Die Granate zündet GRENADE_FUSE Spielsekunden nach dem ersten Aufkommen.
func _step_grenades(dt: float) -> void:
	for i in range(_grenades.size() - 1, -1, -1):
		var g: Dictionary = _grenades[i]
		g.t += dt
		if _grenade_step(g, dt) and g.fuse < 0.0:
			g.fuse = GRENADE_FUSE
			_snd.play("impact", _pitch(), 4.0)
		if g.fuse >= 0.0:
			g.fuse -= dt
			if g.fuse <= 0.0:
				_detonate(g)
				_grenades.remove_at(i)
		elif g.t > 5.0:
			_grenades.remove_at(i)


## Grobe Vorschau: Wurfbogen bis zum ersten Aufkommen.
func _grenade_preview(from: Vector3, target: Vector3) -> Array:
	var g := _make_grenade(from, target, true)
	var pts := [from]
	for i in 400:
		var landed := _grenade_step(g, 1.0 / 120.0)
		if i % 6 == 5 or landed:
			pts.append(g.pos)
		if landed:
			break
	return pts


## Blendet alle Gegner im Radius, die freie Sicht auf die Granate haben.
## Alle anderen in Hörweite drehen sich zum Knall.
func _detonate(g: Dictionary) -> void:
	var at := Vector3(g.pos.x, Actor.EYE_HEIGHT, g.pos.z)
	_fx.add_flash(at, FLASH_RADIUS)
	_shake = 0.2
	_snd.play("flash", _pitch())
	_rumble(0.4, 1.0, 0.3)
	if g.ghost:
		return
	for e in enemies:
		if not e.alive:
			continue
		if e.eye().distance_to(at) <= FLASH_RADIUS and los_clear(at, e.eye()):
			e.blind(FLASH_SECONDS)
		else:
			e.hear(at)


## Spürbarer Treffer an einer Figur: kurzer Bildstopp, Kamera-Ruck, eigener Ton und
## Vibration. Nur wenn die Stelle im Sichtkegel liegt – sonst bleibt der Treffer ungewiss.
## enemy_down: ein Gegner wurde getroffen (sonst Officer oder Geisel).
func _hit_feedback(pos: Vector3, enemy_down: bool) -> void:
	if not _vision.is_point_visible(pos):
		return
	_hitstop = HITSTOP_SECONDS
	_shake = maxf(_shake, 0.28)
	_snd.play("kill" if enemy_down else "loss", _pitch())
	_rumble(0.5, 0.9, 0.18)


## Controller-Vibration (nur wenn gerade mit Controller gespielt wird).
## weak/strong: Stärke der beiden Motoren 0..1.
func _rumble(weak: float, strong: float, seconds: float) -> void:
	if _pad_active:
		Input.start_joy_vibration(_pad_dev, weak, strong, seconds)


## Einschlag-Effekt, nur wenn die Stelle im Sichtkegel liegt (sonst bleibt der Treffer ungewiss).
func _impact(pos: Vector3, on_actor: bool) -> void:
	if _vision.is_point_visible(pos):
		_fx.add_impact(pos, on_actor)
	_snd.play("impact", _pitch())


func _replay_tick() -> void:
	if _rp_seg >= rounds.timeline.size():
		if _bullets.is_empty() and _grenades.is_empty():
			_show_results()
		else:
			_step_bullets(TimeControl.DT)
			_step_grenades(TimeControl.DT)
		return
	var seg := rounds.timeline[_rp_seg]
	var b := _rp_tick * RoundSystem.Segment.STRIDE
	for i in _all.size():
		var t: PackedFloat32Array = seg.tracks[i]
		var a := _all[i]
		a.apply_frame(t[b], t[b + 1], t[b + 2])
		var is_alive := t[b + 3] > 0.5
		if a.alive != is_alive:
			a.set_alive(is_alive)
			if a is Enemy and not is_alive:
				_rp_last_down = a.global_position
		a.apply_flags(int(t[b + 4]))
		a.update_motion(TimeControl.DT)
	if not _rp_final_done and _rp_elapsed > 0 and _count_alive(enemies) == 0:
		# letzter Gegner ausgeschaltet: kurze Zeitlupe, Kamera fährt heran
		_rp_final_done = true
		_rp_slow = REPLAY_KILL_SECONDS
	for s in seg.shots:
		if s.tick == _rp_tick:
			_bullets.append({"pos": s.from, "prev": s.from, "dir": s.dir, "enemy": s.enemy,
				"left": s.dist, "ghost": true, "hit_actor": s.hit_actor})
			_fx.add_trail(s.from, s.from + s.dir * s.dist, s.enemy)
			if s.who >= 0:
				_shot_fx(_all[s.who], s.dir)
	for d in seg.doors:
		if d.tick == _rp_tick:
			_open_door(d.door)
	for g in seg.grenades:
		if g.tick == _rp_tick:
			_grenades.append(_make_grenade(g.from, g.to, true))
	_step_bullets(TimeControl.DT)
	_step_grenades(TimeControl.DT)
	_rp_tick += 1
	_rp_elapsed += 1
	if _rp_tick >= seg.ticks:
		_rp_seg += 1
		_rp_tick = 0


# =============================================================================
#  Eingabe
# =============================================================================

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventJoypadButton:
		_use_pad(event.device)
		if event.pressed:
			_pad_button(event.button_index)
		return
	if event is InputEventJoypadMotion:
		if absf(event.axis_value) > PAD_TRIGGER:
			_use_pad(event.device)
		if event.axis == JOY_AXIS_TRIGGER_RIGHT and event.device == _pad_dev:
			var down: bool = event.axis_value > PAD_TRIGGER
			if down and not _pad_fire_down:
				request_fire()
			_pad_fire_down = down
		return
	if event is InputEventMouseMotion:
		if event.relative.length() > 2.0:
			_pad_active = false          # Maus bewegt: wieder mit dem Mauszeiger zielen
		return
	if event is InputEventMouseButton and event.pressed:
		_pad_active = false
		if event.button_index == MOUSE_BUTTON_LEFT:
			request_fire()
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP:
			TimeControl.adjust(0.01)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			TimeControl.adjust(-0.01)
	elif event is InputEventKey and event.pressed and not event.echo:
		_pad_active = false
		match event.physical_keycode:
			KEY_SPACE:
				request_action()
			KEY_F, KEY_ENTER:
				if HOLD_KEY_ENABLED:
					request_hold()
			KEY_SHIFT:
				request_roll()
			KEY_E:
				request_door()
			KEY_C, KEY_CTRL:
				request_crouch()
			KEY_1:
				TimeControl.adjust(-0.01)
			KEY_2:
				TimeControl.adjust(0.01)
			KEY_R:
				_retry_or_replay()
			KEY_N:
				_new_mission()
			# ESC gehört dem Pausemenü (scripts/pause_menu.gd)


## Controller-Taste gedrückt (Namen nach Lage wie beim Xbox-Pad: A unten, Y oben).
## A und Y haben nach Fehlschlag/Ergebnis die Rolle von R und N.
## Start gehört dem Pausemenü (scripts/pause_menu.gd).
func _pad_button(button: int) -> void:
	var ended := phase == Phase.FAILED or phase == Phase.RESULTS
	match button:
		JOY_BUTTON_RIGHT_SHOULDER:
			request_fire()
		JOY_BUTTON_A:
			if ended:
				_retry_or_replay()
			else:
				request_action()
		JOY_BUTTON_B:
			request_crouch()
		JOY_BUTTON_X:
			request_door()
		JOY_BUTTON_Y:
			if ended:
				_new_mission()
			else:
				request_roll()
		JOY_BUTTON_DPAD_UP:
			TimeControl.adjust(0.01)
		JOY_BUTTON_DPAD_DOWN:
			TimeControl.adjust(-0.01)


func _use_pad(device: int) -> void:
	if device != _pad_dev or not _pad_active:
		_set_pad_kind(device)
	_pad_active = true
	_pad_dev = device


## Bauart des Controllers am Gerätenamen erkennen und die Tastenanzeige im HUD anpassen.
## Unbekannte Controller (und device < 0 = keiner angeschlossen) gelten als Xbox-Pad.
func _set_pad_kind(device: int) -> void:
	var n := Input.get_joy_name(device).to_lower() if device >= 0 else ""
	_pad_kind = "xbox"
	if device >= 0 and Pad.is_nintendo(device):
		_pad_kind = "switch"
	for word: String in ["playstation", "dualsense", "dualshock", "sony", "ps4", "ps5"]:
		if n.contains(word):
			_pad_kind = "ps"
	_hud.set_pad_labels(PAD_LABELS[_pad_kind])


## Beschriftung einer Controller-Taste für die erkannte Bauart (key: Schlüssel in PAD_LABELS).
func _pad_lbl(key: String) -> String:
	return PAD_LABELS[_pad_kind][key]


## R bzw. A: nach Fehlschlag den Durchlauf wiederholen, im Ergebnis das Replay erneut zeigen.
func _retry_or_replay() -> void:
	if phase == Phase.FAILED:
		rounds.retry_pass()
		_start_turn()
	elif phase == Phase.RESULTS:
		_start_final_replay()


## N bzw. Y: neue Mission (nach Fehlschlag oder Ergebnis).
func _new_mission() -> void:
	if phase == Phase.FAILED or phase == Phase.RESULTS:
		TimeControl.override_scale = -1.0
		get_tree().reload_current_scene()


func request_fire() -> void:
	if phase == Phase.PLAYING and _taken:
		_fire_req = true


## Aktionstaste (Spezialfähigkeit) angetippt. Gehalten wird sie über _read_input().
func request_action() -> void:
	if phase == Phase.PLAYING and _taken:
		_action_latch = true


## Umschalttaste: Hechtsprung.
func request_roll() -> void:
	if phase == Phase.PLAYING and _taken:
		_roll_req = true


## C: ducken / aufstehen.
func request_crouch() -> void:
	if phase == Phase.PLAYING and _taken:
		_crouch_req = true


## E: nächste geschlossene Tür in Reichweite öffnen.
func request_door() -> void:
	if phase == Phase.PLAYING and _taken:
		_door_req = true


func request_hold() -> void:
	if phase == Phase.PLAYING and _taken:
		_hold_req = true


func _read_input() -> Dictionary:
	if input_provider.is_valid():
		return input_provider.call()
	var move := Vector2.ZERO
	if Input.is_physical_key_pressed(KEY_W): move.y -= 1.0
	if Input.is_physical_key_pressed(KEY_S): move.y += 1.0
	if Input.is_physical_key_pressed(KEY_A): move.x -= 1.0
	if Input.is_physical_key_pressed(KEY_D): move.x += 1.0
	var action := Input.is_physical_key_pressed(KEY_SPACE)
	var aim_hold := Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT)
	if not _pad_active:
		return {"move": move.limit_length(1.0), "aim": _mouse_world_point(), "action": action,
				"aim_hold": aim_hold}
	# Controller: linker Stick bewegt (analog), A = Aktionstaste, LT oder LB = Waffe anlegen
	var stick := Vector2(Input.get_joy_axis(_pad_dev, JOY_AXIS_LEFT_X), Input.get_joy_axis(_pad_dev, JOY_AXIS_LEFT_Y))
	if stick.length() > PAD_MOVE_DEADZONE:
		move += stick
	move = move.limit_length(1.0)
	action = action or Input.is_joy_button_pressed(_pad_dev, JOY_BUTTON_A)
	aim_hold = aim_hold or Input.get_joy_axis(_pad_dev, JOY_AXIS_TRIGGER_LEFT) > PAD_TRIGGER \
			or Input.is_joy_button_pressed(_pad_dev, JOY_BUTTON_LEFT_SHOULDER)
	# Drehung beim Controller in ECHTER Zeit: ein Tick dauert in der Zeitlupe länger
	var real_tick := TimeControl.DT / maxf(TimeControl.current_scale(), 0.01)
	var pad_turn := deg_to_rad(PAD_TURN_SPEED) * real_tick
	return {"move": move, "aim": _pad_aim_point(), "action": action, "aim_hold": aim_hold,
			"pad_turn": pad_turn}


## Ziel-Stick auslesen (pro Frame, in echter Zeit). Wie bei Twin-Stick-Shootern üblich:
## die Richtung des rechten Sticks IST die Blickrichtung (radiale Totzone, nur die Richtung
## zählt), und nach dem Loslassen bleibt die zuletzt gehaltene Richtung stehen. Der Officer
## dreht sich in echter Zeit dorthin und hält dann an (siehe pad_turn in _read_input).
## Damit das Zurückschnappen des Sticks die Richtung nicht verreißt, zählt eine Auslenkung
## nur, solange sie nicht gerade schnell abfällt.
## Die Auslenkung bestimmt außerdem die Wurfweite der Granate.
func _update_pad_aim() -> void:
	var r := Vector2(Input.get_joy_axis(_pad_dev, JOY_AXIS_RIGHT_X), Input.get_joy_axis(_pad_dev, JOY_AXIS_RIGHT_Y))
	var deflect := r.length()
	if deflect > PAD_AIM_DEADZONE and deflect >= _pad_prev_deflect - PAD_RELEASE_DROP:
		_pad_aim_dir = Vector3(r.x, 0.0, r.y).normalized()
		_pad_aim_dist = GRENADE_RANGE * clampf(inverse_lerp(PAD_AIM_DEADZONE, 0.95, deflect), 0.2, 1.0)
	_pad_prev_deflect = deflect


## Zielpunkt per Controller: vom Officer aus in die zuletzt mit dem rechten Stick
## gehaltene Richtung (vor der ersten Eingabe: seine Blickrichtung).
func _pad_aim_point() -> Vector3:
	if _pad_aim_dir == Vector3.ZERO:
		_pad_aim_dir = active.forward()
	var p := active.global_position + _pad_aim_dir * maxf(_pad_aim_dist, 1.0)
	return Vector3(p.x, Actor.EYE_HEIGHT, p.z)


## Mauszeiger auf die Ebene in Schusshöhe projiziert.
func _mouse_world_point() -> Vector3:
	var mp := get_viewport().get_mouse_position()
	var from := _camera.project_ray_origin(mp)
	var dir := _camera.project_ray_normal(mp)
	if absf(dir.y) < 0.001:
		return active.global_position + active.forward()
	return from + dir * ((Actor.EYE_HEIGHT - from.y) / dir.y)


# =============================================================================
#  Darstellung (pro Frame, unabhängig vom Simulations-Takt)
# =============================================================================

## Nach dem Aufheben der Pause: echte Zeitmessung neu starten, damit _process
## nach dem Fortsetzen keinen Zeitsprung sieht.
func _notification(what: int) -> void:
	if what == NOTIFICATION_UNPAUSED:
		_last_usec = Time.get_ticks_usec()


func _process(_delta: float) -> void:
	var now := Time.get_ticks_usec()
	var real_dt := minf((now - _last_usec) / 1000000.0, 0.1)
	_last_usec = now
	_time += real_dt
	TimeControl.aiming = phase == Phase.PLAYING and _taken and active != null and active.alive and active.aiming

	# Vorlauf in Echtzeit, dann Countdown mit Abbremsen auf Zeitlupe
	if phase == Phase.PLAYING and not _taken:
		_update_countdown(real_dt)
	elif phase == Phase.PLAYING and _pad_active:
		_update_pad_aim()

	if phase == Phase.INTRO:
		_update_intro(real_dt)
	_hitstop = maxf(0.0, _hitstop - real_dt)
	if phase == Phase.FINAL_REPLAY:
		# Abschluss-Replay: Echtzeit-Tempo, beim letzten Treffer kurz Zeitlupe
		_rp_slow = maxf(0.0, _rp_slow - real_dt)
		var want := REPLAY_KILL_SCALE if _rp_slow > 0.0 else TimeControl.realtime_speed
		TimeControl.override_scale = move_toward(TimeControl.override_scale, want, real_dt * 8.0)
	_update_go(real_dt)

	if phase == Phase.BREAK:
		_break_left -= real_dt
		if _break_left <= 0.0:
			_cut = {}
			_start_rewind()

	if phase == Phase.REWIND:
		_update_rewind(real_dt)

	# Im Standbild stehen auch Animationen und Effekte still
	var anim_scale := TimeControl.current_scale()
	if phase == Phase.REWIND:
		# Animationen laufen im Rückspul-Tempo
		anim_scale = _rw_rate / TimeControl.SIM_HZ
	elif phase == Phase.BREAK or phase == Phase.FAILED or phase == Phase.RESULTS:
		# ... außer in der Nahaufnahme (Clip): dort läuft alles in extremer Zeitlupe weiter
		anim_scale = 0.0 if _cut.is_empty() else 0.035
	for a in _all:
		# während des Granaten-Clips läuft die Wurfbewegung der gezeigten Figur mit eigenem Tempo
		var a_scale := anim_scale
		if phase == Phase.BREAK and _cut.get("kind", "") == "grenade" and _cut.get("actor") == a:
			a_scale = CUT_ANIM_SCALE
		a.model.update(a.speed, a_scale, real_dt * a_scale)
	for d in doors:
		d.animate(real_dt * anim_scale)

	# Schild-Optik (rein visuell): während des Schild-Clips fährt das Schild in den ersten 60 % hoch
	for o in officers:
		if o.role != "shield":
			continue
		var r := 1.0
		if phase == Phase.BREAK and _cut.get("kind", "") == "shield" and _cut.get("actor") == o:
			r = smoothstep(0.0, 1.0, clampf((1.0 - _break_left / ABILITY_CUT_SECONDS) / 0.6, 0.0, 1.0))
		o.set_shield_raise(r)

	_update_camera(real_dt)
	_update_vision_and_lasers()
	_update_fx(real_dt * anim_scale, real_dt)
	_update_hud(real_dt)


## Feste Kamera: Abstand so gewählt, dass die ganze Wohnung ins Fenster passt.
func _update_camera(real_dt: float) -> void:
	var bd: Array = Level.BOUNDS
	var center := _level_center()
	var screen := get_viewport().get_visible_rect().size
	var aspect := screen.x / maxf(screen.y, 1.0)
	var half := tan(deg_to_rad(CAM_FOV) * 0.5)
	var p := deg_to_rad(CAM_PITCH_DEG)
	# Tiefe erscheint durch die Neigung verkürzt, dazu kommt die Wandhöhe
	var depth: float = (bd[3] - bd[1]) * sin(p) + Level.WALL_H * cos(p)
	var dist := maxf(depth / (2.0 * half), (bd[2] - bd[0]) / (2.0 * half * aspect)) * 1.16
	_shake = maxf(0.0, _shake - real_dt * 0.8)
	var jitter := Vector3(randf_range(-1, 1), 0.0, randf_range(-1, 1)) * _shake
	var back := Vector3(0.0, sin(p), cos(p))
	var overview := center + back * dist
	# Nahaufnahme beim Schuss: weich an den Schützen heranfahren und wieder zurück
	_cam_k = lerpf(_cam_k, 0.0 if _cut.is_empty() else 1.0, 1.0 - exp(-4.0 * real_dt))
	var close := Vector3(_cam_focus.x, 0.8, _cam_focus.z) + back * dist * CUT_ZOOM
	# Abschluss-Replay: die Kamera folgt dem Team; beim letzten Treffer fährt sie nah heran
	var in_replay := phase == Phase.FINAL_REPLAY
	var follow_w := 1.0 - exp(-3.0 * real_dt)
	_rp_cam_k = lerpf(_rp_cam_k, 1.0 if in_replay else 0.0, 1.0 - exp(-2.5 * real_dt))
	if in_replay:
		var kill_shot := _rp_slow > 0.0
		var target := _rp_last_down if kill_shot else center.lerp(_squad_center(center), 0.7)
		_rp_focus = _rp_focus.lerp(target, follow_w)
		_rp_zoom = lerpf(_rp_zoom, REPLAY_KILL_ZOOM if kill_shot else REPLAY_ZOOM, follow_w)
	var follow := Vector3(_rp_focus.x, 0.0, _rp_focus.z) + back * dist * _rp_zoom
	var pos := overview.lerp(follow, smoothstep(0.0, 1.0, _rp_cam_k))
	_camera.global_position = pos.lerp(close, smoothstep(0.0, 1.0, _cam_k)) + jitter


func _level_center() -> Vector3:
	var bd: Array = Level.BOUNDS
	return Vector3((bd[0] + bd[2]) * 0.5, 0.0, (bd[1] + bd[3]) * 0.5)


## Mittelpunkt der lebenden Officer (fallback, wenn keiner lebt).
func _squad_center(fallback: Vector3) -> Vector3:
	var sum := Vector3.ZERO
	var n := 0
	for o in officers:
		if o.alive:
			sum += o.global_position
			n += 1
	return sum / n if n > 0 else fallback


func _update_vision_and_lasers() -> void:
	var space := get_world_3d().direct_space_state

	# Sichtkegel aller lebenden Officer (geteilte Squad-Sicht)
	var sources := []
	var poses := []                      # interpolierte Pose je Officer, auch für die Laser
	for o in officers:
		var t := o.get_global_transform_interpolated()
		var pose := {"pos": t.origin, "yaw": atan2(t.basis.z.x, t.basis.z.z)}
		poses.append(pose)
		if o.alive:
			sources.append(pose)
	_vision.update(_camera, sources, space)

	_fx.arc = {}
	_fx.marker = {}
	_active_ring.visible = false
	for i in officers.size():
		var o := officers[i]
		var beam := _officer_lasers[i]
		var beam2 := _reflect_lasers[i]
		# Officer, die gerade nicht gespielt werden, treten optisch zurück
		var dim := active != null and o != active and (phase == Phase.PLAYING or phase == Phase.BREAK or phase == Phase.REWIND)
		o.set_dim(dim)
		# Laser nur, wenn der Officer lebt UND die Waffe angelegt hat
		beam.visible = o.alive and o.aiming
		beam2.visible = false
		if not o.alive:
			continue
		var ends := _laser_ends(o, poses[i].pos, poses[i].yaw)
		if beam.visible:
			beam.set_alpha(0.3 if dim else 0.9)
			beam.set_points(ends[0], ends[1])
			if ends.size() > 2:
				# Laser spiegelt sich an Metall: zeigt, wohin ein Abpraller fliegen würde
				beam2.visible = true
				beam2.set_alpha(0.15 if dim else 0.55)
				beam2.set_points(ends[1], ends[2])
		if o == active and (phase == Phase.PLAYING or phase == Phase.BREAK or phase == Phase.REWIND):
			_highlight_active(o, poses[i], ends)

	var threats := []
	for i in enemies.size():
		var e := enemies[i]
		var shown := _vision.is_point_visible(e.global_position)
		e.set_shown(shown)
		var beam := _enemy_lasers[i]
		beam.visible = false
		if e.alive:
			var t := e.get_global_transform_interpolated()
			# Der Laser erscheint erst, wenn der Gegner einen Officer gesichtet hat –
			# dann aber auch aus dem Dunkeln, zusammen mit dem Ring "Schuss in …".
			if e.vis_engage:
				var ends := _laser_ends(e, t.origin, atan2(t.basis.z.x, t.basis.z.z))
				beam.set_points(ends[0], ends[1])
				beam.visible = true
				# gelockt: Laser flackert hell – die Richtung steht fest, jetzt ausweichen
				beam.set_alpha(1.0 if e.vis_locked and fmod(_time, 0.12) < 0.06 else 0.9)
				if phase != Phase.FINAL_REPLAY and phase != Phase.RESULTS:
					threats.append({"pos": t.origin, "aim": e.vis_aim, "blind": false, "locked": e.vis_locked})
			elif e.vis_blind and shown:
				threats.append({"pos": t.origin, "aim": 0.0, "blind": true})
	_fx.threats = threats

	for h in hostages:
		h.set_shown(_vision.is_point_visible(h.global_position))
	_update_hints()


## Fristen bedrohter Geiseln, Tür-Hinweis, Vorschau früherer Officer, Wurf-Vorschau.
func _update_hints() -> void:
	var in_game := phase == Phase.PLAYING or phase == Phase.BREAK or phase == Phase.RESOLVE
	var deadlines := []
	if in_game:
		for e in enemies:
			var frac := e.threat_fraction()
			if e.alive and frac >= 0.0:
				deadlines.append({"pos": hostages[e.hostage_index()].global_position, "frac": frac,
					"seconds": frac * e.threat_time})
	if deadlines.size() > _deadline_count:
		_snd.play("alarm")
	_deadline_count = deadlines.size()
	_fx.deadlines = deadlines

	_fx.prompts = []
	_fx.ghosts = []
	_fx.throw_preview = {}
	if phase != Phase.PLAYING or not _taken or not active.alive:
		return
	var di := _near_door(active)
	if di >= 0:
		_fx.prompts = [{"pos": doors[di].center + Vector3(0, 2.0, 0), "text": _pad_lbl("x") if _pad_active else "E"}]

	var list := []
	for g in _ghosts:
		var pts := []
		for p in g.pts:
			if p.tick >= tick:
				pts.append(p.pos)
		var shots := []
		for sh in g.shots:
			if sh.tick >= tick:
				shots.append(sh)
		if pts.size() > 0 or shots.size() > 0:
			list.append({"color": g.color, "points": pts, "shots": shots})
	_fx.ghosts = list

	if active.role == "flash" and active.grenades > 0:
		var aim := _last_aim if input_provider.is_valid() or _pad_active else _mouse_world_point()
		var arc := _grenade_preview(active.eye(), _grenade_target(active, aim))
		_fx.throw_preview = {"arc": arc, "to": arc[arc.size() - 1], "radius": FLASH_RADIUS}


## Aktiver Officer: pulsierender Bodenring, Pfeil über dem Kopf und (sobald er
## gesteuert wird) der Streubogen am Laser-Ende.
func _highlight_active(o: Officer, pose: Dictionary, ends: Array) -> void:
	var col := o.color.lightened(0.45)
	_active_ring.visible = true
	_active_ring.global_position = Vector3(pose.pos.x, 0.06, pose.pos.z)
	var pulse := 1.0 + 0.12 * sin(_time * 6.0)
	_active_ring.scale = Vector3(pulse, 0.15, pulse)
	(_active_ring.material_override as StandardMaterial3D).albedo_color = col
	_fx.marker = {"pos": pose.pos, "color": col}
	if _taken and o.aiming:
		# Streuung: Bogen mit Radius = Entfernung zum Laser-Ende, Öffnung = ± Streuwinkel
		_fx.arc = {"origin": ends[0], "yaw": pose.yaw, "spread": o.current_spread(),
			"dist": (ends[0] as Vector3).distance_to(ends[1])}


## Laser bis zur ersten Kollision (Wand, Möbel, Figur, Schild). Trifft er Metall,
## kommt als dritter Punkt das Ende des gespiegelten Strahls dazu.
func _laser_ends(a: Actor, pos: Vector3, p_yaw: float) -> Array:
	var from := Vector3(pos.x, Actor.EYE_HEIGHT, pos.z)
	var dir := Vector3(sin(p_yaw), 0.0, cos(p_yaw))
	var mask := _bullet_mask(a is Enemy)
	var skip := [a.get_rid()]
	if a is Officer:
		if (a as Officer).crouched:
			mask |= Actor.LAYER_CRATE      # geduckt kommt man nicht über die Kiste
		else:
			for o in officers:             # stehend zielt man über geduckte Kollegen hinweg
				if o != a and o.alive and o.crouched:
					skip.append(o.get_rid())
	var hit := _trace(from, from + dir * SHOT_RANGE, skip, mask)
	# Durchschuss-Modus: der Laser zeigt, wohin die Kugel durch die Wände fliegt
	var pierce := PIERCE_MAX_WALLS if a is Officer and (a as Officer).pierce_mode else 0
	while pierce > 0 and not hit.is_empty() and _pierceable(hit.collider):
		pierce -= 1
		skip.append(hit.collider.get_rid())
		hit = _trace(from, from + dir * SHOT_RANGE, skip, mask)
	if hit.is_empty():
		return [from, from + dir * SHOT_RANGE]
	var pts := [from, hit.position]
	var n: Vector3 = hit.normal
	n.y = 0.0
	if _is_metal(hit.collider) and n.length() > 0.1:
		n = n.normalized()
		var from2: Vector3 = hit.position + n * 0.02
		var dir2 := dir.bounce(n)
		var hit2 := _trace(from2, from2 + dir2 * SHOT_RANGE, [], mask)
		pts.append(hit2.position if not hit2.is_empty() else from2 + dir2 * SHOT_RANGE)
	return pts


func _update_fx(game_dt: float, real_dt: float) -> void:
	# Kugeln zwischen zwei Simulations-Ticks interpolieren, damit sie weich fliegen
	var f := Engine.get_physics_interpolation_fraction()
	var list := []
	for b in _bullets:
		list.append({"pos": (b.prev as Vector3).lerp(b.pos, f), "dir": b.dir, "enemy": b.enemy})
	var cut_kind: String = _cut.get("kind", "")
	if cut_kind == "shot":
		# Nahaufnahme: die Kugel löst sich und fliegt ihren ersten Meter
		var k := clampf(1.0 - _break_left / SHOT_CUT_SECONDS, 0.0, 1.0)
		var flown := CUT_BULLET_METERS * k
		list.append({"pos": _cut.from + _cut.dir * (0.95 + flown), "dir": _cut.dir, "enemy": false,
			"tail": minf(flown, 0.5)})
	_fx.bullets = list
	var glist := []
	for g in _grenades:
		glist.append({"ground": Vector3(g.pos.x, 0.05, g.pos.z), "pos": g.pos})
	if cut_kind == "grenade" and _cut.has("path"):
		# Nahaufnahme: die Granate fliegt das erste Stück ihrer echten Flugbahn entlang
		var k := clampf(1.0 - _break_left / ABILITY_CUT_SECONDS, 0.0, 1.0)
		if k >= 0.25:
			# in den ersten 25 % des Clips Ausholbewegung, danach fliegt sie los (k auf 0..1 umrechnen)
			var kk := clampf((k - 0.25) / 0.75, 0.0, 1.0)
			var path: Array = _cut.path
			var want := 2.5 * kk              # höchstens die ersten 2,5 m der Bahn
			var acc := 0.0
			var pos: Vector3 = path[path.size() - 1]
			for i in range(1, path.size()):
				var seg: float = (path[i] as Vector3).distance_to(path[i - 1] as Vector3)
				if seg > 0.0 and acc + seg >= want:
					pos = (path[i - 1] as Vector3).lerp(path[i] as Vector3, (want - acc) / seg)
					break
				acc += seg
				pos = path[i]
			glist.append({"ground": Vector3(pos.x, 0.05, pos.z), "pos": pos})
	_fx.grenades = glist
	_fx.advance(game_dt, real_dt)


func _update_hud(real_dt: float) -> void:
	_hud.tick(real_dt)
	var hz := float(TimeControl.SIM_HZ)
	var playing := phase == Phase.PLAYING or phase == Phase.BREAK

	match phase:
		Phase.PLAYING:
			if _taken and _solo:
				_hud.set_phase("LETZTER OFFICER  ·  KEINE RUNDEN", COL_DANGER)
			elif _taken:
				_hud.set_phase("DEIN ZUG  ·  OFFICER %d" % (active.idx + 1), COL_GO)
			else:
				_hud.set_phase("VORLAUF IN ECHTZEIT", COL_REALTIME)
		Phase.BREAK:
			_hud.set_phase("FREEZE", COL_FREEZE)
		Phase.RESOLVE:
			_hud.set_phase("AUSWERTUNG  ·  DURCHLAUF %d" % rounds.pass_index, Color.WHITE)
		Phase.FAILED:
			_hud.set_phase("MISSION FAILED", COL_DANGER)
		Phase.FINAL_REPLAY:
			_hud.set_phase("EINSATZ-REPLAY", COL_REALTIME)
		Phase.RESULTS:
			_hud.set_phase("ERGEBNIS", Color.WHITE)
		Phase.INTRO:
			_hud.set_phase("ZUGRIFF", COL_REALTIME)
		Phase.MENU:
			_hud.set_phase("", Color.WHITE)
		Phase.REWIND:
			_hud.set_phase("ZURÜCKSPULEN", COL_REALTIME)

	var chips := []
	for o in officers:
		var state := "wait"
		var word := "wartet"
		if not o.alive and (phase != Phase.PLAYING or o != active):
			state = "dead"
			word = "Ausfall"
		elif o == active and playing:
			state = "active"
			word = "AKTIV"
		elif rounds.tracks.has(o.idx):
			state = "done"
			word = "fertig"
		chips.append({"text": "%d %s · %s" % [o.idx + 1, ROLE_SHORT[o.role], word],
			"color": o.color, "state": state, "role": o.role, "name": ROLE_SHORT[o.role]})
	_hud.set_squad(chips)

	if playing:
		_hud.set_stats(active.ammo, active.max_ammo, active.stability, _taken, _special_text(active))
	else:
		_hud.set_stats(0, 0, 0.0, false)
	_hud.set_hint_visible(playing)

	var seconds := (_rp_elapsed if phase == Phase.FINAL_REPLAY or phase == Phase.RESULTS else tick) / hz
	var scale := TimeControl.current_scale()
	var tempo := "TEMPO %d %%" % roundi(scale * 100.0)
	if scale > 1.05:
		tempo = "ECHTZEIT × %s" % String.num(scale, 1)
	elif scale > 0.95:
		tempo = "ECHTZEIT"
	if phase == Phase.BREAK:
		tempo = "STANDBILD"
	elif phase == Phase.REWIND:
		tempo = "◀◀ × %.0f" % (_rw_rate / TimeControl.SIM_HZ)
	_hud.set_clock("DURCHLAUF %d   ·   %.2f s\n%s" % [rounds.pass_index, seconds, tempo])

	# Übernahme-Timer: während Vorlauf und Countdown, bis der Spieler die Kontrolle hat
	if phase == Phase.PLAYING and not _taken:
		var left := _count_left
		if _count_left < 0.0:
			# Countdown läuft noch nicht: Vorlauf in Echtzeit (override_scale 1.0) + Countdown
			left = float(maxi(0, _count_start - tick)) / (TimeControl.SIM_HZ * TimeControl.realtime_speed) + COUNT_TOTAL
		_hud.set_takeover_timer(left, _lead_total, active.color)
	else:
		_hud.set_takeover_timer(-1.0, 1.0, Color.WHITE)


func _special_text(o: Officer) -> String:
	# Tastennamen passend zum zuletzt benutzten Eingabegerät
	var k_act := _pad_lbl("a") if _pad_active else "LEERTASTE"
	var k_roll := _pad_lbl("y") if _pad_active else "UMSCHALT"
	var k_crouch := _pad_lbl("b") if _pad_active else "C"
	var k_aim := _pad_lbl("lt") if _pad_active else "RECHTE MAUSTASTE"
	var k_fire := _pad_lbl("rt") if _pad_active else "Linksklick"
	var text := ""
	match o.role:
		"flash":
			text = "%s   Blendgranate × %d" % [k_act, o.grenades] \
					+ ("  (beendet den Zug)" if GRENADE_ENDS_TURN and not _solo else "")
		"shield":
			text = "%s   Schild heben" % k_act + ("  (beendet den Zug)" if SHIELD_ENDS_TURN and not _solo else "")
		"pierce":
			var mode := "aus"
			if o.pierce_mode:
				mode = "AN  (durch Wände, Streuung × %s)" % String.num(o.pierce_spread_factor, 1)
			text = "%s   Durchschuss  ·  %s" % [k_act, mode]
	var roll_state := "bereit" if o.roll_ready() >= 1.0 else "lädt …"
	if o.shield_up:
		roll_state = "nicht mit Schild"
	text += "\n%s   Hechtsprung  ·  %s" % [k_roll, roll_state]
	var aim_line := "WAFFE ANGELEGT  ·  %s schießt" % k_fire if o.aiming \
			else "%s halten: Waffe anlegen" % k_aim
	return text + ("\nGEDUCKT  ·  %s zum Aufstehen" % k_crouch if o.crouched else "\n%s zum Ducken" % k_crouch) \
			+ "\n" + aim_line


# --- Hilfen ---------------------------------------------------------------------

func _ray(from: Vector3, to: Vector3, mask: int, exclude: Array = []) -> Dictionary:
	var q := PhysicsRayQueryParameters3D.create(from, to, mask)
	var rids: Array[RID] = []
	rids.assign(exclude)
	q.exclude = rids
	return get_world_3d().direct_space_state.intersect_ray(q)


## Freie Sichtlinie (nur Wände/Möbel blockieren). Wird von der Gegner-KI genutzt.
func los_clear(from: Vector3, to: Vector3) -> bool:
	return _ray(from, to, Actor.LAYER_WORLD).is_empty()


## Ist eine Geisel getroffen worden UND lässt das die Mission scheitern?
## Mit fail_on_hostage_hit = false (gameplay_tweaks.cfg) läuft der Einsatz weiter.
func _hostage_lost() -> bool:
	return FAIL_ON_HOSTAGE_HIT and _count_alive(hostages) < hostages.size()


func _count_alive(list: Array) -> int:
	var n := 0
	for a in list:
		if a.alive:
			n += 1
	return n
