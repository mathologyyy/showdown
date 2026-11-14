class_name Enemy
extends Actor
## Einfache, deterministische Gegner-KI.
##  GUARD  – bewacht: schwenkt den Blick oder patrouilliert langsam
##  ALERT  – hat etwas gehört / Ziel verloren: dreht sich zur Stelle
##  ENGAGE – sieht einen Officer: dreht sich hin, feuert nach Reaktionszeit
##
## Zusätzliche Reaktionen:
##  Geisel als Schild – beim ersten Alarm stellt er sich hinter eine nahe Geisel
##  Geisel bedrohen   – ab dann läuft eine Frist; ist sie um, erschießt er die Geisel
##  Deckung           – nach einem eigenen Schuss oder einem knappen Fehlschuss weicht er
##                      hinter ein Möbelstück aus und kommt nach kurzer Zeit zurück
##
##  Waffe: im Zustand GUARD ist sie gesenkt und wird bei Alarm (Sichtung/Geräusch) gezogen.
##
## Kein Zufall außer der Streuung, und die wird aus (Gegner, Tick) geseedet.
## Gleiche Lage ergibt also in jeder Runde exakt dasselbe Verhalten.

enum State { GUARD, ALERT, ENGAGE }
enum Mode { NONE, GO, WAIT, RETURN }

const FLAG_BLIND := 4
const FLAG_ENGAGE := 8
const FLAG_ARMED := 16

@export var view_range := 10.0
@export var fov_half_deg := 50.0
@export var reaction_time := 0.7        # Spielsekunden von Sichtkontakt bis Schuss
@export var draw_time := 0.4            # Spielsekunden bis die Waffe im Anschlag ist
@export var fire_cooldown := 1.0
@export var turn_speed_deg := 220.0
@export var patrol_speed := 0.6
@export var run_speed := 2.6            # Tempo beim Ausweichen
@export var spread_deg := 2.0
@export var hearing_range := 14.0
@export var scan_amp_deg := 25.0
@export var scan_speed := 0.6
@export var cover_search := 4.0         # so weit sucht er nach einem Möbelstück als Deckung
@export var cover_wait := 1.0           # Spielsekunden hinter der Deckung
@export var cover_cooldown := 4.0       # frühestens dann geht er erneut in Deckung
@export var hostage_range := 5.0        # so nah muss eine Geisel sein (mit Sichtlinie)
@export var threat_time := 10.0         # Frist in Spielsekunden, bis er die Geisel erschießt

var game                                  # GameManager (liefert Officer, Geiseln, Sichtlinien, Tick)
var state := State.GUARD
var home_yaw := 0.0
var patrol: Array = []                    # optionale Wegpunkte (Vector3)

## Nur für die Anzeige (werden pro Tick bzw. im Replay aus den Flags gesetzt):
var vis_engage := false                   # hat einen Officer gesichtet -> Laser sichtbar
var vis_blind := false
var vis_aim := 0.0                        # 0..1, bei 1 fällt der nächste Schuss
var vis_armed := false                    # Waffe im Anschlag (für Anzeige und Replay)

var _scan_phase := 0.0
var _patrol_i := 0
var _react := 0.0
var _cooldown := 0.0
var _alert_pos := Vector3.ZERO
var _alert_time := 0.0
var _blind := 0.0                         # verbleibende Blend-Zeit (Spielsekunden)
var _draw := 0.4                          # verbleibende Zieh-Zeit (Spielsekunden)
var _alerted := false                     # war schon einmal alarmiert
var _hostage := -1                        # Index der bedrohten Geisel
var _exec := 0.0                          # verbleibende Frist
var _mode := Mode.NONE                    # Ausweichbewegung (Deckung / hinter die Geisel)
var _mode_t := 0.0
var _goal := Vector3.ZERO
var _return_pos := Vector3.ZERO
var _wait_after := 0.0
var _cover_cd := 0.0
var _rng := RandomNumberGenerator.new()


## Übernimmt alle Gameplay-Werte des Gegners aus den Tweaks (Sektion "enemy").
func apply_tweaks() -> void:
	reaction_time = Tweaks.num("enemy", "reaction_time", 0.7)
	fire_cooldown = Tweaks.num("enemy", "fire_cooldown", 1.0)
	turn_speed_deg = Tweaks.num("enemy", "aim_turn_speed_deg", 220.0)
	spread_deg = Tweaks.num("enemy", "aim_spread_deg", 2.0)
	view_range = Tweaks.num("enemy", "view_range", 10.0)
	fov_half_deg = Tweaks.num("enemy", "fov_half_deg", 50.0)
	hearing_range = Tweaks.num("enemy", "hearing_range", 14.0)
	patrol_speed = Tweaks.num("enemy", "patrol_speed", 0.6)
	run_speed = Tweaks.num("enemy", "run_speed", 2.6)
	cover_wait = Tweaks.num("enemy", "cover_wait", 1.0)
	cover_cooldown = Tweaks.num("enemy", "cover_cooldown", 4.0)
	threat_time = Tweaks.num("enemy", "threat_time", 10.0)
	draw_time = Tweaks.num("enemy", "weapon_draw_time", 0.4)
	_draw = draw_time


func sim_tick(dt: float) -> void:
	_cooldown = maxf(0.0, _cooldown - dt)
	_cover_cd = maxf(0.0, _cover_cd - dt)
	_think(dt)
	if state == State.GUARD:
		_draw = draw_time            # Waffe gesenkt; beim nächsten Alarm neu ziehen
	else:
		_draw = maxf(0.0, _draw - dt)
	vis_armed = state != State.GUARD and _draw <= 0.0
	model.set_aiming(vis_armed)
	vis_blind = _blind > 0.0
	vis_engage = vis_armed and state == State.ENGAGE and _mode == Mode.NONE and not vis_blind
	vis_aim = 0.0
	if vis_engage:
		vis_aim = 1.0 - maxf(maxf(_react / reaction_time, _cooldown / fire_cooldown), _draw / maxf(draw_time, 0.001))


func _think(dt: float) -> void:
	if _blind > 0.0:
		# Geblendet: sieht nichts, zielt nicht, schießt nicht; auch die Frist steht still.
		_blind -= dt
		if state == State.ENGAGE:
			state = State.ALERT
			_alert_time = 3.0
		return

	if state != State.GUARD and not _alerted:
		_alerted = true
		_take_hostage()

	if _hostage >= 0:
		var h: Actor = game.hostages[_hostage]
		if not h.alive:
			_hostage = -1
		else:
			_exec -= dt
			if _exec <= 0.0 and _mode == Mode.NONE and _draw <= 0.0:
				# Frist abgelaufen: Waffe auf die Geisel, Schuss
				var want := yaw_to(h.global_position)
				_turn(want, dt)
				if absf(angle_difference(yaw, want)) < deg_to_rad(2.5):
					_hostage = -1
					game.enemy_fire(self, (h.eye() - eye()).normalized(), true)
				return

	if _mode != Mode.NONE:
		_move_mode(dt)
		return

	var target := _find_target()
	if target:
		if state != State.ENGAGE:
			state = State.ENGAGE
			_react = reaction_time
		_alert_pos = target.global_position
		var want := yaw_to(target.global_position)
		_turn(want, dt)
		_react = maxf(0.0, _react - dt)
		if _react <= 0.0 and _cooldown <= 0.0 and _draw <= 0.0 \
				and absf(angle_difference(yaw, want)) < deg_to_rad(2.5):
			_cooldown = fire_cooldown
			game.enemy_fire(self, _spread_dir())
			_take_cover()
		return

	match state:
		State.ENGAGE:
			state = State.ALERT
			_alert_time = 3.0
		State.ALERT:
			_turn(yaw_to(_alert_pos), dt)
			_alert_time -= dt
			if _alert_time <= 0.0:
				state = State.GUARD
		State.GUARD:
			_guard(dt)


## Ein Geräusch in Hörweite (Schuss, Granate, Tür): zur Stelle drehen.
## radius: Reichweite des Geräuschs (Standard: volle Hörweite, Türen sind leiser).
func hear(pos: Vector3, radius := -1.0) -> void:
	if state == State.ENGAGE:
		return
	if global_position.distance_to(pos) > (radius if radius > 0.0 else hearing_range):
		return
	state = State.ALERT
	_alert_pos = pos
	_alert_time = 3.0


## Blendgranate: für `seconds` Spielsekunden handlungsunfähig.
func blind(seconds: float) -> void:
	_blind = maxf(_blind, seconds)


## Eine Officer-Kugel ist knapp vorbeigeflogen.
func suppress(from: Vector3) -> void:
	if state == State.GUARD:
		hear(from)
	else:
		_alert_pos = from
	_take_cover()


## Restliche Frist für die bedrohte Geisel als Anteil 0..1, oder -1 ohne Geisel.
func threat_fraction() -> float:
	return clampf(_exec / threat_time, 0.0, 1.0) if _hostage >= 0 else -1.0


func hostage_index() -> int:
	return _hostage


func flags() -> int:
	return (FLAG_BLIND if vis_blind else 0) | (FLAG_ENGAGE if vis_engage else 0) \
		| (FLAG_ARMED if vis_armed else 0)


func apply_flags(f: int) -> void:
	vis_blind = f & FLAG_BLIND != 0
	vis_armed = f & FLAG_ARMED != 0
	vis_engage = vis_armed and f & FLAG_ENGAGE != 0
	vis_aim = 0.0
	model.set_aiming(vis_armed)


# --- Reaktionen -----------------------------------------------------------------

## Beim ersten Alarm: nächste freie Geisel in der Nähe als Schild nehmen und bedrohen.
func _take_hostage() -> void:
	var best := -1
	var best_d := hostage_range
	for i in game.hostages.size():
		var h: Actor = game.hostages[i]
		if not h.alive:
			continue
		var taken := false
		for other: Enemy in game.enemies:
			if other != self and other.alive and other.hostage_index() == i:
				taken = true
		var d := global_position.distance_to(h.global_position)
		if taken or d > best_d or not game.los_clear(eye(), h.eye()):
			continue
		best = i
		best_d = d
	if best < 0:
		return
	_hostage = best
	_exec = threat_time
	# hinter die Geisel, von der Gefahr aus gesehen
	var hp: Vector3 = game.hostages[best].global_position
	var away := hp - _alert_pos
	away.y = 0.0
	if away.length() < 0.1:
		away = hp - global_position
	_goal = hp + away.normalized() * 0.85
	_mode = Mode.GO
	_mode_t = 2.5
	_wait_after = 0.0


## Hinter das nächste Möbelstück ausweichen, das Sichtschutz gegen die Gefahr bietet.
func _take_cover() -> void:
	if _mode != Mode.NONE or _cover_cd > 0.0 or _hostage >= 0:
		return
	var threat := Vector3(_alert_pos.x, EYE_HEIGHT, _alert_pos.z)
	var best := Vector3.ZERO
	var best_d := cover_search
	for box in Level.FURNITURE + Level.METAL:
		var c := Vector3(box[0], 0.0, box[1])
		var away := c - _alert_pos
		away.y = 0.0
		if away.length() < 0.5:
			continue
		var p: Vector3 = c + away.normalized() * (maxf(box[2], box[3]) * 0.5 + 0.55)
		var d := global_position.distance_to(p)
		var p_eye := Vector3(p.x, EYE_HEIGHT, p.z)
		# erreichbar (freie Linie dorthin) und von der Gefahr aus verdeckt
		if d < best_d and game.los_clear(eye(), p_eye) and not game.los_clear(threat, p_eye):
			best = p
			best_d = d
	if best_d >= cover_search:
		return
	_return_pos = global_position
	_goal = best
	_mode = Mode.GO
	_mode_t = 1.5
	_wait_after = cover_wait
	_cover_cd = cover_cooldown


func _move_mode(dt: float) -> void:
	match _mode:
		Mode.GO, Mode.RETURN:
			var to := _goal - global_position
			to.y = 0.0
			_mode_t -= dt
			if to.length() < 0.12 or _mode_t <= 0.0:
				if _mode == Mode.GO and _wait_after > 0.0:
					_mode = Mode.WAIT
					_mode_t = _wait_after
				else:
					_mode = Mode.NONE
					_react = reaction_time * 0.6   # muss neu anvisieren
				return
			_turn(yaw_to(_goal), dt * 2.0)
			move_step(to.normalized() * minf(run_speed * dt, to.length()))
		Mode.WAIT:
			_turn(yaw_to(_alert_pos), dt)
			_mode_t -= dt
			if _mode_t <= 0.0:
				_mode = Mode.RETURN
				_goal = _return_pos
				_mode_t = 1.5


func _guard(dt: float) -> void:
	if patrol.size() >= 2:
		var wp: Vector3 = patrol[_patrol_i]
		var to_wp := wp - global_position
		to_wp.y = 0.0
		if to_wp.length() < 0.15:
			_patrol_i = (_patrol_i + 1) % patrol.size()
			return
		_turn(yaw_to(wp), dt)
		move_step(to_wp.normalized() * patrol_speed * dt)
	else:
		_scan_phase += dt * scan_speed
		_turn(home_yaw + sin(_scan_phase) * deg_to_rad(scan_amp_deg), dt)


func _turn(want: float, dt: float) -> void:
	var diff := angle_difference(yaw, want)
	var step := deg_to_rad(turn_speed_deg) * dt
	set_yaw(yaw + clampf(diff, -step, step))


## Nächster lebender Officer in Reichweite, im Sichtfeld und ohne Wand dazwischen.
func _find_target() -> Officer:
	var best: Officer = null
	var best_d := view_range
	for o: Officer in game.officers:
		if not o.alive:
			continue
		var d := global_position.distance_to(o.global_position)
		if d > best_d:
			continue
		if absf(angle_difference(yaw, yaw_to(o.global_position))) > deg_to_rad(fov_half_deg):
			continue
		if not game.los_clear(eye(), o.eye()):
			continue
		best = o
		best_d = d
	return best


func _spread_dir() -> Vector3:
	_rng.seed = hash(Vector2i(idx, game.tick))
	var s := deg_to_rad(spread_deg)
	var a := yaw + _rng.randf_range(-s, s)
	return Vector3(sin(a), 0.0, cos(a))


func get_state() -> Dictionary:
	var s := super()
	s.merge({
		"state": state, "scan": _scan_phase, "patrol_i": _patrol_i, "react": _react,
		"cooldown": _cooldown, "alert_pos": _alert_pos, "alert_time": _alert_time, "blind": _blind,
		"alerted": _alerted, "hostage": _hostage, "exec": _exec, "mode": _mode, "mode_t": _mode_t,
		"goal": _goal, "return_pos": _return_pos, "wait_after": _wait_after, "cover_cd": _cover_cd,
		"draw": _draw,
	})
	return s


func set_state(s: Dictionary) -> void:
	super(s)
	state = s.state
	_scan_phase = s.scan
	_patrol_i = s.patrol_i
	_react = s.react
	_cooldown = s.cooldown
	_alert_pos = s.alert_pos
	_alert_time = s.alert_time
	_blind = s.blind
	_alerted = s.alerted
	_hostage = s.hostage
	_exec = s.exec
	_mode = s.mode
	_mode_t = s.mode_t
	_goal = s.goal
	_return_pos = s.return_pos
	_wait_after = s.wait_after
	_cover_cd = s.cover_cd
	_draw = s.draw
	vis_blind = _blind > 0.0
	vis_armed = state != State.GUARD and _draw <= 0.0
	vis_engage = vis_armed and state == State.ENGAGE and _mode == Mode.NONE and not vis_blind
	vis_aim = 0.0
	model.set_aiming(vis_armed)
