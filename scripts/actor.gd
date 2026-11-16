class_name Actor
extends CharacterBody3D
## Basisklasse für alle Figuren (Officer, Gegner, Geiseln).
## Kollisionskapsel + animiertes Modell; kapselt Blickrichtung, Tod und das
## Sichern/Wiederherstellen des Zustands für die Checkpoints.

const EYE_HEIGHT := 1.0      # Höhe, auf der gezielt, geschossen und gesehen wird
const RADIUS := 0.35
const HEIGHT := 1.8

# Kollisions-Layer (Bitwerte)
const LAYER_WORLD := 1
const LAYER_OFFICER := 2
const LAYER_ENEMY := 4
const LAYER_HOSTAGE := 8
const LAYER_CRATE := 16      # niedrige Kisten: blockieren den Weg, Kugeln nur bedingt
const MASK_BULLET := 15      # Kugeln und Laser treffen Welt + alle Figuren

var idx := 0
var alive := true
## Blickrichtung als Winkel um die Y-Achse. forward() = (sin, 0, cos).
var yaw := 0.0
## Aktuelle Geschwindigkeit in m pro Spielsekunde (nur für die Animation).
var speed := 0.0
var color := Color.WHITE
var model: CharacterModel

var _layer := 0
var _visual: Node3D
var _label: Label3D
var _prev_pos := Vector3.ZERO


## kind: Schlüssel in CharacterModel.MODELS ("officer_flash", "officer_shield",
## "officer_pierce", "enemy" oder "hostage"), wählt Modell und Waffe.
func setup(p_idx: int, kind: String, p_color: Color, layer: int, label := "") -> void:
	idx = p_idx
	color = p_color
	_layer = layer
	collision_layer = layer
	collision_mask = LAYER_WORLD | LAYER_CRATE   # Figuren blockieren sich gegenseitig nicht
	motion_mode = CharacterBody3D.MOTION_MODE_FLOATING

	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = RADIUS
	capsule.height = HEIGHT
	shape.shape = capsule
	shape.position.y = HEIGHT * 0.5
	add_child(shape)

	_visual = Node3D.new()
	add_child(_visual)
	model = CharacterModel.new()
	_visual.add_child(model)
	model.build(kind, p_color)

	if label != "":
		var l := Label3D.new()
		l.text = label
		l.font_size = 96
		l.pixel_size = 0.0035
		l.outline_size = 24
		l.modulate = p_color.lightened(0.5)
		l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		l.no_depth_test = true
		l.position.y = HEIGHT + 0.75
		_visual.add_child(l)
		_label = l


func forward() -> Vector3:
	return Vector3(sin(yaw), 0.0, cos(yaw))


func eye() -> Vector3:
	return Vector3(global_position.x, EYE_HEIGHT, global_position.z)


func set_yaw(value: float) -> void:
	yaw = wrapf(value, -PI, PI)
	rotation.y = yaw


func yaw_to(point: Vector3) -> float:
	return atan2(point.x - global_position.x, point.z - global_position.z)


## Bewegt die Figur um `motion` und gleitet an Wänden entlang. Bewusst ohne
## move_and_slide(), damit die Schrittweite nur vom festen Simulations-Tick abhängt.
func move_step(motion: Vector3) -> void:
	for i in 3:
		var col := move_and_collide(motion)
		if col == null:
			break
		motion = col.get_remainder().slide(col.get_normal())
		motion.y = 0.0
	global_position.y = 0.0


## Einmal pro Simulations-Tick: Geschwindigkeit für die Animation ermitteln.
func update_motion(dt: float) -> void:
	speed = global_position.distance_to(_prev_pos) / dt
	_prev_pos = global_position


## Zusatz-Zustände für Aufzeichnung und Replay als Bitmaske (siehe Officer/Enemy).
func flags() -> int:
	return 0


func apply_flags(_f: int) -> void:
	pass


## Abdunkeln (Officer, die gerade nicht gespielt werden).
func set_dim(on: bool) -> void:
	model.set_dim(on)
	if _label:
		_label.modulate = color.lightened(0.5) * (Color(0.35, 0.35, 0.35) if on else Color.WHITE)


func kill() -> void:
	if alive:
		set_alive(false)


## Sichtbarkeit der Grafik (Gegner/Geiseln außerhalb der Sichtkegel werden versteckt).
func set_shown(value: bool) -> void:
	_visual.visible = value


## instant: ohne Sterbe-Animation direkt in den Endzustand (beim Checkpoint-Reset).
func set_alive(value: bool, instant := false) -> void:
	alive = value
	collision_layer = _layer if value else 0   # Tote blockieren keine Kugeln
	if value:
		model.reset()
	else:
		model.die(instant)


# --- Zustand für Checkpoints -------------------------------------------------

func get_state() -> Dictionary:
	return {"pos": global_position, "yaw": yaw, "alive": alive}


func set_state(s: Dictionary) -> void:
	global_position = s.pos
	_prev_pos = s.pos
	speed = 0.0
	set_yaw(s.yaw)
	set_alive(s.alive, true)
	reset_physics_interpolation()   # Teleport: nicht vom alten Ort her interpolieren


## Direktes Setzen aus einer Aufzeichnung (Replay), ohne Interpolations-Reset.
func apply_frame(x: float, z: float, p_yaw: float) -> void:
	global_position = Vector3(x, 0.0, z)
	set_yaw(p_yaw)
