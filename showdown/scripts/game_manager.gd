extends Node3D
## GameManager: baut die Szene auf und steuert den gesamten Ablauf.
##
## Ablauf eines Durchlaufs:
##   Checkpoint (T0) ─► Zug Officer 1 ─► Freeze ─► Reset auf T0 ─► Zug Officer 2 ─► …
##   … ─► Auswertung (alle Aufzeichnungen laufen gemeinsam durch) ─► neuer Checkpoint
##
## Ab dem zweiten Zug läuft das bisher Aufgezeichnete zuerst in ECHTZEIT ab. Kurz vor
## dem Moment, an dem der vorige Zug endete, bremst die Zeit auf Zeitlupe herunter
## und der Spieler übernimmt den nächsten Officer ("Übernahme"). Vor jeder Übernahme
## läuft ein Countdown 3 – 2 – 1 – GO GO GO.
##
## Spezialfähigkeiten (Leertaste): Blendgranate, Schild, Hechtrolle – siehe officer.gd.
## Rechte Maustaste halten legt die Waffe an (Laser, Streubogen, Schießen).
## Kugeln prallen an Metall-Objekten (Level.METAL) ab.
##
## Sind in einer Auswertung alle Gegner ausgeschaltet, folgt das Abschluss-Replay
## in Echtzeit und der Ergebnis-Screen.
##
## Die Simulation läuft ausschließlich in _physics_process mit festem Zeitschritt
## (deterministisch, siehe time_control.gd), alles Sichtbare in _process.

enum Phase { PLAYING, BREAK, RESOLVE, FAILED, FINAL_REPLAY, RESULTS, INTRO }

## Was einen Zug beendet (zum Ausprobieren umschaltbar):
const ENEMY_SHOT_ENDS_TURN := false   # Gegnerschüsse frieren nicht mehr ein, die Kugel fliegt sofort
const SHIELD_ENDS_TURN := true        # Schild heben beendet den Zug
const GRENADE_ENDS_TURN := true       # Granatenwurf beendet den Zug (sie fliegt ab dem nächsten Zug)

const OFFICER_COLORS := [
	Color(0.15, 0.40, 1.00), Color(0.10, 0.75, 0.55), Color(0.55, 0.35, 1.00),
]
const ROLE_SHORT := {"flash": "Blend", "shield": "Schild", "roll": "Rolle"}
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
var RESOLVE_TIME_SCALE: float = 0.6 # Tempo der Auswertung; aus Tweaks "tempo"
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
const CUT_ZOOM := 0.42              # Kameraabstand in der Nahaufnahme (Anteil der Totalen)
const CUT_BULLET_METERS := 1.0      # so weit fliegt die Kugel in der Nahaufnahme
const INTRO_SECONDS := 2.4          # Rammbock-Intro
const CROUCH_COVER_REACH := 1.6     # so nah muss die Kiste vor dem Geduckten stehen
var FLASH_RADIUS: float = 4.5       # Blendradius (nur mit Sichtlinie zur Granate); aus Tweaks "weapons"
var FLASH_SECONDS: float = 2.5      # so lange sind Gegner geblendet (Spielzeit); aus Tweaks "weapons"
var MAX_BOUNCES: int = 2            # so oft prallt eine Kugel höchstens an Metall ab; aus Tweaks "weapons"
const DOOR_REACH := 1.7             # so nah muss ein Officer an der Tür stehen, um sie zu öffnen
const DOOR_NOISE := 6.0             # so weit hört man eine aufgestoßene Tür
const NEAR_MISS := 0.9              # fliegt eine Team-Kugel so knapp vorbei, geht der Gegner in Deckung
const GHOST_STEP := 12              # Vorschau früherer Officer: ein Wegpunkt alle so viele Ticks
## Wertung: je ein Stern für Einsatzdauer, Team-Schüsse und Durchläufe unter diesen Grenzen.
const STAR_SECONDS := 15.0
const STAR_EXTRA_SHOTS := 2         # erlaubte Schüsse = Zahl der Gegner + so viele
const STAR_PASSES := 4
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
var _cut: Dictionary = {}            # Nahaufnahme beim Schuss: {from, dir}
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
var _takeover_tick := 0              # ab diesem Tick steuert der Spieler
var _taken := false
var _fire_req := false
var _hold_req := false
var _settle := 0                     # Ticks Pause nach einem Reset (Physik übernimmt Teleports)
var _break_left := 0.0
var _last_usec := 0
var _shake := 0.0
var _time := 0.0
var _rp_seg := 0
var _rp_tick := 0
var _rp_elapsed := 0


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
	RESOLVE_TIME_SCALE = Tweaks.num("tempo", "resolve_speed", 0.6)
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

	_last_usec = Time.get_ticks_usec()
	_start_intro()


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
		o.setup(i, "officer", OFFICER_COLORS[i], Actor.LAYER_OFFICER, str(i + 1))
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
	_takeover_tick = maxi(0, prev_end - TAKEOVER_LEAD_TICKS)
	_taken = false
	_count_left = -1.0
	_count_digit = 0
	# Während des Countdowns vergeht (wegen des Abbremsens) so viel Spielzeit:
	var ramp_ticks := int(COUNT_TOTAL * (1.0 + TimeControl.slowmo_scale) * 0.5 * TimeControl.SIM_HZ)
	_count_start = maxi(0, _takeover_tick - ramp_ticks)
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
		TimeControl.override_scale = 1.0
		if tick >= _count_start and _settle == 0:
			_count_left = COUNT_TOTAL
			if _takeover_tick > 0:
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
	TimeControl.override_scale = lerpf(1.0, TimeControl.slowmo_scale, smoothstep(0.0, 1.0, k))


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
	if _count_alive(hostages) < hostages.size():
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
	_hud.set_panel_text("MISSION FAILED\n\n%s\n\n[R] Durchlauf wiederholen      [N] Neue Mission" % reason)


## Abschluss-Replay: die Timeline aller Auswertungen in Echtzeit, ohne Sichtkegel.
func _start_final_replay() -> void:
	phase = Phase.FINAL_REPLAY
	active = null
	_rp_seg = 0
	_rp_tick = 0
	_rp_elapsed = 0
	_bullets.clear()
	_grenades.clear()
	_fx.clear()
	TimeControl.override_scale = 1.0
	_vision.enabled = false
	for i in doors.size():
		doors[i].set_open(_initial_doors[i], true)
	_hud.set_panel_text("")
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
			+ "[R] Replay erneut      [N] Neue Mission") % [
			stars.strip_edges(), lines, enemy_shots,
			_count_alive(hostages), hostages.size(),
			_count_alive(officers), officers.size()])


# =============================================================================
#  Simulation (fester Zeitschritt)
# =============================================================================

func _physics_process(_delta: float) -> void:
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
				var shield_before := o.shield_up
				var thrown := o.control_tick(inp.move, inp.aim, inp.get("aim_hold", false), held, pressed, crouch, dt)
				_track.add_frame(o)
				if thrown:
					var target := _grenade_target(o, inp.aim)
					_track.throws.append({"tick": tick, "target": target})
					if GRENADE_ENDS_TURN:
						_begin_break("GRANATE GEWORFEN", "Officer %d  ·  Wirkung ungewiss" % (o.idx + 1), COL_FREEZE)
						return
					_throw_grenade(o.eye(), target, false)
				if SHIELD_ENDS_TURN and o.shield_up and not shield_before:
					_begin_break("SCHILD OBEN", "Officer %d deckt ab jetzt nach vorn" % (o.idx + 1), COL_FREEZE)
					return
			else:
				_track.add_frame(o)
			if _taken and _hold_req:
				_begin_break("POSITION GEHALTEN", "Officer %d sichert" % (o.idx + 1), Color.WHITE)
				return
			if _taken and _fire_req:
				_fire_req = false
				if o.can_fire():
					o.ammo -= 1
					var dir := o.roll_shot_dir(_rng)
					_track.shots.append({"tick": tick, "dir": dir})
					_shot_fx(o, dir)
					# Nahaufnahme: Mündungsfeuer und die Kugel auf ihrem ersten Meter
					_cut = {"from": o.eye(), "dir": dir}
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
					_throw_grenade(o.eye(), s.target, false)
			for s in tr.shots:
				if s.tick == tick and o.ammo > 0:
					o.ammo -= 1
					_fire_bullet(o, s.dir)

	# --- Gegner: jede Runde live simuliert ---
	for e in enemies:
		if e.alive:
			e.sim_tick(dt)
			if phase == Phase.BREAK:
				return

	_step_bullets(dt)
	_step_grenades(dt)

	if phase == Phase.PLAYING and not active.alive:
		_begin_break("OFFICER %d GEFALLEN" % (active.idx + 1), "Getroffen von einer Kugel", COL_DANGER)
		return

	for a in _all:
		a.update_motion(dt)

	if phase == Phase.RESOLVE:
		for i in _all.size():
			var a := _all[i]
			var t: PackedFloat32Array = _segment.tracks[i]
			t.append(a.global_position.x)
			t.append(a.global_position.z)
			t.append(a.yaw)
			t.append(1.0 if a.alive else 0.0)
			t.append(float(a.flags()))
			_segment.tracks[i] = t

	tick += 1
	if phase == Phase.RESOLVE and tick >= _resolve_end and _bullets.is_empty() and _grenades.is_empty():
		_finish_resolve()


## Wird von der Gegner-KI aufgerufen, wenn sie abdrückt.
## Bekannter Schuss (fiel schon in einem früheren Zug) -> Kugel fliegt los.
## Neuer Schuss -> friert die Szene ein und beendet den Zug.
## execute: Schuss auf eine Geisel (abgelaufene Frist).
func enemy_fire(e: Enemy, dir: Vector3, execute := false) -> void:
	if phase == Phase.RESOLVE or not ENEMY_SHOT_ENDS_TURN or rounds.match_enemy_shot(e.idx, tick):
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
func _fire_bullet(shooter: Actor, dir: Vector3, hit_hostages := false) -> void:
	var by_enemy := shooter is Enemy
	# high: aus dem Stand geschossen – fliegt über Kisten und über geduckte Kollegen hinweg
	var high := not (shooter is Officer and (shooter as Officer).crouched)
	var mask := _bullet_mask(by_enemy and not hit_hostages)
	if not high:
		mask |= Actor.LAYER_CRATE
	var b := {"pos": shooter.eye(), "prev": shooter.eye(), "dir": dir, "skip": [shooter.get_rid()],
		"origin": shooter.eye(), "mask": mask, "high": high,
		"enemy": by_enemy, "left": SHOT_RANGE, "leg": SHOT_RANGE, "bounces": 0,
		"ghost": false, "hit_actor": false, "rec": null}
	if phase == Phase.RESOLVE:
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
	if phase == Phase.RESOLVE:
		_segment.doors.append({"tick": tick, "door": i})
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
		while hit and hit.collider is Officer and _passes_over(b, hit):
			b.skip.append(hit.collider.get_rid())
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
	if phase == Phase.RESOLVE:
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
	if g.ghost:
		return
	for e in enemies:
		if not e.alive:
			continue
		if e.eye().distance_to(at) <= FLASH_RADIUS and los_clear(at, e.eye()):
			e.blind(FLASH_SECONDS)
		else:
			e.hear(at)


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
		a.apply_flags(int(t[b + 4]))
		a.update_motion(TimeControl.DT)
	for s in seg.shots:
		if s.tick == _rp_tick:
			_bullets.append({"pos": s.from, "prev": s.from, "dir": s.dir, "enemy": s.enemy,
				"left": s.dist, "ghost": true, "hit_actor": s.hit_actor})
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
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			request_fire()
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP:
			TimeControl.adjust(0.01)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			TimeControl.adjust(-0.01)
	elif event is InputEventKey and event.pressed and not event.echo:
		match event.physical_keycode:
			KEY_SPACE:
				request_action()
			KEY_F, KEY_ENTER:
				request_hold()
			KEY_E:
				request_door()
			KEY_C, KEY_CTRL:
				request_crouch()
			KEY_1:
				TimeControl.adjust(-0.01)
			KEY_2:
				TimeControl.adjust(0.01)
			KEY_R:
				if phase == Phase.FAILED:
					rounds.retry_pass()
					_start_turn()
				elif phase == Phase.RESULTS:
					_start_final_replay()
			KEY_N:
				if phase == Phase.FAILED or phase == Phase.RESULTS:
					TimeControl.override_scale = -1.0
					get_tree().reload_current_scene()
			KEY_ESCAPE:
				get_tree().quit()


func request_fire() -> void:
	if phase == Phase.PLAYING and _taken:
		_fire_req = true


## Aktionstaste (Spezialfähigkeit) angetippt. Gehalten wird sie über _read_input().
func request_action() -> void:
	if phase == Phase.PLAYING and _taken:
		_action_latch = true


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
	return {"move": move.normalized(), "aim": _mouse_world_point(), "action": action,
			"aim_hold": Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT)}


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

func _process(_delta: float) -> void:
	var now := Time.get_ticks_usec()
	var real_dt := minf((now - _last_usec) / 1000000.0, 0.1)
	_last_usec = now
	_time += real_dt

	# Vorlauf in Echtzeit, dann Countdown mit Abbremsen auf Zeitlupe
	if phase == Phase.PLAYING and not _taken:
		_update_countdown(real_dt)

	if phase == Phase.INTRO:
		_update_intro(real_dt)
	_update_go(real_dt)

	if phase == Phase.BREAK:
		_break_left -= real_dt
		if _break_left <= 0.0:
			_cut = {}
			_next_turn()

	# Im Standbild stehen auch Animationen und Effekte still
	var anim_scale := TimeControl.current_scale()
	if phase == Phase.BREAK or phase == Phase.FAILED or phase == Phase.RESULTS:
		# ... außer in der Schuss-Nahaufnahme: dort läuft alles in extremer Zeitlupe weiter
		anim_scale = 0.0 if _cut.is_empty() else 0.035
	for a in _all:
		a.model.update(a.speed, anim_scale, real_dt * anim_scale)
	for d in doors:
		d.animate(real_dt * anim_scale)

	_update_camera(real_dt)
	_update_vision_and_lasers()
	_update_fx(real_dt * anim_scale, real_dt)
	_update_hud(real_dt)


## Feste Kamera: Abstand so gewählt, dass die ganze Wohnung ins Fenster passt.
func _update_camera(real_dt: float) -> void:
	var bd: Array = Level.BOUNDS
	var center := Vector3((bd[0] + bd[2]) * 0.5, 0.0, (bd[1] + bd[3]) * 0.5)
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
	_camera.global_position = overview.lerp(close, smoothstep(0.0, 1.0, _cam_k)) + jitter


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
		var dim := active != null and o != active and (phase == Phase.PLAYING or phase == Phase.BREAK)
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
		if o == active and (phase == Phase.PLAYING or phase == Phase.BREAK):
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
				if phase != Phase.FINAL_REPLAY and phase != Phase.RESULTS:
					threats.append({"pos": t.origin, "aim": e.vis_aim, "blind": false})
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
		_fx.prompts = [{"pos": doors[di].center + Vector3(0, 2.0, 0), "text": "E"}]

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
		var aim := _last_aim if input_provider.is_valid() else _mouse_world_point()
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
	if not _cut.is_empty():
		# Nahaufnahme: die Kugel löst sich und fliegt ihren ersten Meter
		var k := clampf(1.0 - _break_left / SHOT_CUT_SECONDS, 0.0, 1.0)
		var flown := CUT_BULLET_METERS * k
		list.append({"pos": _cut.from + _cut.dir * (0.95 + flown), "dir": _cut.dir, "enemy": false,
			"tail": minf(flown, 0.5)})
	_fx.bullets = list
	var glist := []
	for g in _grenades:
		glist.append({"ground": Vector3(g.pos.x, 0.05, g.pos.z), "pos": g.pos})
	_fx.grenades = glist
	_fx.advance(game_dt, real_dt)


func _update_hud(real_dt: float) -> void:
	_hud.tick(real_dt)
	var hz := float(TimeControl.SIM_HZ)
	var playing := phase == Phase.PLAYING or phase == Phase.BREAK

	match phase:
		Phase.PLAYING:
			if _taken:
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
			"color": o.color, "state": state})
	_hud.set_squad(chips)

	if playing:
		_hud.set_stats(active.ammo, active.max_ammo, active.stability, _taken, _special_text(active))
	else:
		_hud.set_stats(0, 0, 0.0, false)
	_hud.set_hint_visible(playing)

	var seconds := (_rp_elapsed if phase == Phase.FINAL_REPLAY or phase == Phase.RESULTS else tick) / hz
	var scale := TimeControl.current_scale()
	var tempo := "ECHTZEIT" if scale > 0.95 else "TEMPO %d %%" % roundi(scale * 100.0)
	if phase == Phase.BREAK:
		tempo = "STANDBILD"
	_hud.set_clock("DURCHLAUF %d   ·   %.2f s\n%s" % [rounds.pass_index, seconds, tempo])


func _special_text(o: Officer) -> String:
	var text := ""
	match o.role:
		"flash":
			text = "LEERTASTE   Blendgranate × %d" % o.grenades \
					+ ("  (beendet den Zug)" if GRENADE_ENDS_TURN else "")
		"shield":
			text = "LEERTASTE   Schild heben" + ("  (beendet den Zug)" if SHIELD_ENDS_TURN else "")
		"roll":
			text = "LEERTASTE   Hechtrolle  ·  " + ("bereit" if o.roll_ready() >= 1.0 else "lädt …")
	var aim_line := "WAFFE ANGELEGT  ·  Linksklick schießt" if o.aiming \
			else "RECHTE MAUSTASTE halten: Waffe anlegen"
	return text + ("\nGEDUCKT  ·  C zum Aufstehen" if o.crouched else "\nC zum Ducken") + "\n" + aim_line


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


func _count_alive(list: Array) -> int:
	var n := 0
	for a in list:
		if a.alive:
			n += 1
	return n
