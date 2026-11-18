class_name Officer
extends Actor
## Ein SEK-Officer. Wird entweder vom Spieler gesteuert (control_tick) oder
## vom GameManager aus einer Aufzeichnung nachgefahren (Actor.apply_frame + apply_flags).
##
## Zielen: Rechte Maustaste halten legt die Waffe an (Laser, Streubogen, Schießen).
## Jeder Officer hat eine Spezialfähigkeit auf der Aktionstaste (Leertaste):
##   "flash"  – wirft eine Blendgranate zum Mauszeiger
##   "shield" – hält, solange die Taste gedrückt ist, ein Schild vor sich
##   "pierce" – schaltet den Durchschuss-Modus um: Kugeln gehen durch Wände (nicht
##              durch Metall), dafür ist die Streuung größer
## Alle können einen Hechtsprung in Laufrichtung machen (eigene Taste, nicht mit Schild).

const ROLE_NAMES := {"flash": "Blendgranate", "shield": "Schild", "pierce": "Durchschuss"}
const FLAG_SHIELD := 1
const FLAG_ROLL := 2
const FLAG_CROUCH := 4
const FLAG_AIM := 8
const FLAG_PIERCE := 16
## Schild als Strecke quer vor dem Officer (für die Kugel-Berechnung im GameManager).
const SHIELD_DIST := 0.5
const SHIELD_HALF_WIDTH := 0.7

@export var move_speed := 3.2            # m pro Spielsekunde
## Wie schnell die Zielrichtung dem Mauszeiger folgt (1/s Spielzeit).
## Klein = träge. Da in Spielzeit gerechnet wird, wirkt es in Zeitlupe zäh.
@export var aim_follow := 6.0
@export var stabilize_time := 0.6        # Spielsekunden Stillstand bis volle Stabilität
@export var spread_max_deg := 7.0        # Streuung direkt nach Bewegung (± Grad)
@export var spread_min_deg := 0.4        # Streuung bei voller Stabilität
@export var max_ammo := 12
@export var max_grenades := 2
@export var shield_speed_factor := 0.55  # Lauftempo mit erhobenem Schild
@export var aim_move_speed_factor := 1.0 # Lauftempo mit angelegter Waffe
@export var crouch_speed_factor := 0.7   # Lauftempo geduckt
@export var roll_speed_factor := 2.0     # Tempo der Rolle als Vielfaches von move_speed
@export var roll_time := 0.42            # Dauer der Rolle
@export var roll_cooldown := 1.5         # Spielsekunden bis zur nächsten Rolle
@export var roll_recover := 0.4          # danach so lange maximale Streuung
@export var pierce_spread_factor := 3.0  # Streuung im Durchschuss-Modus (Vielfaches)

var role := ""
var ammo := 12
var grenades := 0
## 0..1, lädt beim Stillstehen auf, Bewegung setzt sie zurück.
var stability := 0.0
var shield_up := false
var aiming := false                       # Waffe angelegt
var rolling := false
var pierce_mode := false                  # Durchschuss-Modus an (nur Rolle "pierce")
var crouched := false
var ram: Node3D                          # Rammbock (nur im Intro sichtbar)

var _roll_left := 0.0
var _roll_cd := 0.0
var _recover := 0.0
var _roll_dir := Vector3.ZERO
var _shield_mesh: Node3D
var _shield_raise := 1.0                 # letzter an set_shield_raise übergebener Wert


## Übernimmt alle Gameplay-Werte des Officers aus den Tweaks (Sektion "player").
func apply_tweaks() -> void:
	move_speed = Tweaks.num("player", "move_speed", 3.2)
	crouch_speed_factor = Tweaks.num("player", "crouch_speed_factor", 0.7)
	shield_speed_factor = Tweaks.num("player", "shield_speed_factor", 0.55)
	aim_move_speed_factor = Tweaks.num("player", "aim_move_speed_factor", 1.0)
	aim_follow = Tweaks.num("player", "aim_turn_speed", 6.0)
	stabilize_time = Tweaks.num("player", "aim_steady_time", 0.6)
	spread_max_deg = Tweaks.num("player", "spread_max_deg", 7.0)
	spread_min_deg = Tweaks.num("player", "spread_min_deg", 0.4)
	max_ammo = Tweaks.whole("player", "max_ammo", 12)
	max_grenades = Tweaks.whole("player", "max_grenades", 2)
	roll_speed_factor = Tweaks.num("player", "roll_speed_factor", 2.0)
	roll_time = Tweaks.num("player", "roll_time", 0.42)
	roll_cooldown = Tweaks.num("player", "roll_cooldown", 1.5)
	roll_recover = Tweaks.num("player", "roll_recover", 0.4)
	pierce_spread_factor = Tweaks.num("player", "pierce_spread_factor", 3.0)


func set_role(p_role: String) -> void:
	role = p_role
	grenades = max_grenades if role == "flash" else 0
	if role == "shield":
		_build_shield()


## Einen Simulations-Tick lang steuern. aim_held: rechte Maustaste gehalten (Waffe
## anlegen). action_held/action_pressed: Aktionstaste (Leertaste, Spezialfähigkeit).
## roll_pressed: Taste für den Hechtsprung.
## pad_turn: >= 0 beim Controller – so viele Radiant darf sich der Officer in diesem Tick
## höchstens drehen (vom GameManager aus echter Zeit berechnet, also auch in der Zeitlupe
## schnell). < 0 bei der Maus: träges Nachziehen in Spielzeit wie bisher.
## Liefert true, wenn in diesem Tick eine Blendgranate geworfen wird.
func control_tick(move: Vector2, aim_point: Vector3, aim_held: bool, action_held: bool, action_pressed: bool,
		crouch_toggle: bool, roll_pressed: bool, dt: float, pad_turn := -1.0) -> bool:
	if crouch_toggle:
		set_crouched(not crouched)
	# Zielrichtung folgt dem Mauszeiger verzögert (exponentielles Nachziehen).
	var to_aim := aim_point - global_position
	if Vector2(to_aim.x, to_aim.z).length() > 0.3:
		var want := atan2(to_aim.x, to_aim.z)
		if pad_turn >= 0.0:
			# Controller: mit fester Winkelgeschwindigkeit genau bis zur Stick-Richtung, kein Nachlaufen
			set_yaw(rotate_toward(yaw, want, pad_turn))
		else:
			set_yaw(lerp_angle(yaw, want, 1.0 - exp(-aim_follow * dt)))

	_roll_cd = maxf(0.0, _roll_cd - dt)
	var thrown := false
	match role:
		"flash":
			if action_pressed and grenades > 0:
				grenades -= 1
				thrown = true
		"shield":
			# einmal oben bleibt es oben (das Heben beendet den Zug, siehe GameManager)
			_set_shield(shield_up or action_held)
		"pierce":
			if action_pressed:
				pierce_mode = not pierce_mode

	# Hechtsprung: für alle, aber nicht mit erhobenem Schild
	if roll_pressed and can_roll():
		_roll_left = roll_time
		_roll_cd = roll_cooldown
		_roll_dir = Vector3(move.x, 0.0, move.y).normalized() if move.length_squared() > 0.001 else forward()
		_set_rolling(true)

	# Waffe anlegen: nur mit gehaltener Ziel-Taste, nie mit erhobenem Schild oder während der Rolle
	_set_aiming(aim_held and not shield_up and not rolling)

	if _roll_left > 0.0:
		# Rolle: fester Satz in Startrichtung, nicht lenkbar
		move_step(_roll_dir * move_speed * roll_speed_factor * dt)
		_roll_left -= dt
		stability = 0.0
		if _roll_left <= 0.0:
			_set_rolling(false)
			_recover = roll_recover
		return false

	var factor := shield_speed_factor if shield_up else 1.0
	if aiming:
		factor *= aim_move_speed_factor
	if crouched:
		factor *= crouch_speed_factor
	move_step(Vector3(move.x, 0.0, move.y) * move_speed * factor * dt)

	_recover = maxf(0.0, _recover - dt)
	# Stabilität lädt nur mit angelegter Waffe und im Stillstand auf
	if not aiming or move.length_squared() > 0.001 or shield_up or _recover > 0.0:
		stability = 0.0
	else:
		stability = minf(1.0, stability + dt / stabilize_time)
	return thrown


func can_roll() -> bool:
	return _roll_left <= 0.0 and _roll_cd <= 0.0 and not shield_up


func can_fire() -> bool:
	return ammo > 0 and aiming and not shield_up and not rolling


## 0..1: wie weit die Rolle wieder bereit ist.
func roll_ready() -> float:
	return 1.0 - _roll_cd / roll_cooldown


## Aktuelle Streuung als Halbwinkel in Radiant.
## Im Durchschuss-Modus um pierce_spread_factor größer.
func current_spread() -> float:
	var s := deg_to_rad(lerpf(spread_max_deg, spread_min_deg, stability))
	return s * pierce_spread_factor if pierce_mode else s


## Würfelt die tatsächliche Schussrichtung innerhalb der aktuellen Streuung.
func roll_shot_dir(rng: RandomNumberGenerator) -> Vector3:
	var s := current_spread()
	var a := yaw + rng.randf_range(-s, s)
	return Vector3(sin(a), 0.0, cos(a))


## Mittelpunkt und Querrichtung des erhobenen Schilds.
func shield_center() -> Vector3:
	return eye() + forward() * SHIELD_DIST


func shield_side() -> Vector3:
	return Vector3(cos(yaw), 0.0, -sin(yaw))


func flags() -> int:
	return (FLAG_AIM if aiming else 0) | (FLAG_SHIELD if shield_up else 0) \
			| (FLAG_ROLL if rolling else 0) | (FLAG_CROUCH if crouched else 0) \
			| (FLAG_PIERCE if pierce_mode else 0)


func apply_flags(f: int) -> void:
	_set_aiming(f & FLAG_AIM != 0)
	_set_shield(f & FLAG_SHIELD != 0)
	_set_rolling(f & FLAG_ROLL != 0)
	set_crouched(f & FLAG_CROUCH != 0)
	pierce_mode = f & FLAG_PIERCE != 0


func set_crouched(on: bool) -> void:
	crouched = on
	model.set_crouched(on)


## Rammbock: ein dunkler Zylinder, den der Officer vor sich hält.
func build_ram() -> void:
	ram = Node3D.new()
	ram.position = Vector3(0.28, 0.85, 0.35)
	_visual.add_child(ram)
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.11
	cm.bottom_radius = 0.11
	cm.height = 1.1
	mi.mesh = cm
	mi.rotation_degrees.x = 90.0
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.12, 0.12, 0.14)
	mat.metallic = 0.5
	mi.material_override = mat
	ram.add_child(mi)
	ram.visible = false


func _set_aiming(on: bool) -> void:
	aiming = on
	model.set_aiming(on)


func _set_shield(on: bool) -> void:
	shield_up = on
	if _shield_mesh:
		_shield_mesh.visible = on and alive


func _set_rolling(on: bool) -> void:
	rolling = on
	model.set_rolling(on)


func set_alive(value: bool, instant := false) -> void:
	super(value, instant)
	if not value:
		_set_aiming(false)
		_set_shield(false)
		rolling = false


## Rein optisch: Schild-Haltung zwischen gesenkt (k = 0) und normal (k = 1).
## Ändert NICHTS an der Simulation (shield_up, shield_center() usw. bleiben unverändert).
## Wird jeden Frame aufgerufen: bei unverändertem k früh zurückkehren.
func set_shield_raise(k: float) -> void:
	if not _shield_mesh:
		return
	k = clampf(k, 0.0, 1.0)
	if k == _shield_raise:
		return
	_shield_raise = k
	if k >= 1.0:
		# exakt die Normalhaltung aus _build_shield()
		_shield_mesh.position = Vector3(0.0, 0.85, SHIELD_DIST)
		_shield_mesh.rotation = Vector3.ZERO
		_shield_mesh.scale = Vector3.ONE
	else:
		# gesenkt: tiefere Position, Oberkante kippt nach vorn, etwas kleiner
		_shield_mesh.position = Vector3(0.0, lerpf(0.30, 0.85, k), SHIELD_DIST)
		_shield_mesh.rotation = Vector3(deg_to_rad(65.0) * (1.0 - k), 0.0, 0.0)
		_shield_mesh.scale = Vector3.ONE * lerpf(0.85, 1.0, k)


func _build_shield() -> void:
	_shield_mesh = Node3D.new()
	_shield_mesh.position = Vector3(0.0, 0.85, SHIELD_DIST)
	_visual.add_child(_shield_mesh)
	var plate := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(SHIELD_HALF_WIDTH * 2.0, 1.25, 0.07)
	plate.mesh = bm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.13, 0.16, 0.22)
	mat.metallic = 0.6
	mat.roughness = 0.45
	plate.material_override = mat
	_shield_mesh.add_child(plate)
	var slit := MeshInstance3D.new()          # Sichtfenster
	var sm := BoxMesh.new()
	sm.size = Vector3(0.6, 0.16, 0.09)
	slit.mesh = sm
	var smat := StandardMaterial3D.new()
	smat.albedo_color = Color(0.55, 0.8, 1.0)
	smat.emission_enabled = true
	smat.emission = Color(0.3, 0.55, 0.8)
	slit.material_override = smat
	slit.position.y = 0.33
	_shield_mesh.add_child(slit)
	_shield_mesh.visible = false


func get_state() -> Dictionary:
	var s := super()
	s["ammo"] = ammo
	s["grenades"] = grenades
	s["crouched"] = crouched
	return s


func set_state(s: Dictionary) -> void:
	super(s)
	ammo = s.ammo
	grenades = s.grenades
	stability = 0.0
	_roll_left = 0.0
	_roll_cd = 0.0
	_recover = 0.0
	_set_aiming(false)
	_set_shield(false)
	_set_rolling(false)
	pierce_mode = false
	set_crouched(s.crouched and alive)
