class_name Door
extends StaticBody3D
## Doppeltür in einer Wandlücke. Geschlossen blockiert sie Bewegung, Sicht, Kugeln und
## Granaten (Kollisions-Layer "Welt"). Offen ist sie nur noch Optik: die beiden
## Flügel schwingen um ihre Angeln an den Enden der Lücke zur selben Seite auf.

const THICKNESS := 0.12
const OPEN_ANGLE := PI * 0.47
const SWING_SPEED := 9.0        # Radiant pro Spielsekunde

var is_open := false
var center := Vector3.ZERO

var _pivots: Array[Node3D] = []
var _angle := 0.0
var _target := 0.0


## a, b: Endpunkte der Lücke am Boden (achsenparallel).
func setup(a: Vector3, b: Vector3) -> void:
	collision_layer = Actor.LAYER_WORLD
	collision_mask = 0
	center = (a + b) * 0.5
	var along_x := absf(b.x - a.x) > absf(b.z - a.z)
	var length := a.distance_to(b)

	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = _size(length, along_x)
	cs.shape = shape
	cs.position = center + Vector3(0, Level.WALL_H * 0.5, 0)
	add_child(cs)

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.72, 0.42, 0.16)
	for hinge in [a, b]:
		var pivot := Node3D.new()
		pivot.position = hinge
		pivot.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
		add_child(pivot)
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = _size(length * 0.5 - 0.02, along_x)
		mi.mesh = bm
		mi.material_override = mat
		# Flügel reicht von der Angel bis zur Mitte der Lücke
		mi.position = (center - hinge) * 0.5 + Vector3(0, Level.WALL_H * 0.5, 0)
		pivot.add_child(mi)
		_pivots.append(pivot)


func _size(length: float, along_x: bool) -> Vector3:
	return Vector3(length, Level.WALL_H, THICKNESS) if along_x else Vector3(THICKNESS, Level.WALL_H, length)


## instant: ohne Schwung direkt in die Endstellung (Checkpoint-Reset).
func set_open(value: bool, instant := false) -> void:
	is_open = value
	collision_layer = 0 if value else Actor.LAYER_WORLD
	_target = OPEN_ANGLE if value else 0.0
	if instant:
		_angle = _target
		_apply()


## Pro Frame: Flügel in Spielzeit aufschwingen lassen.
func animate(game_dt: float) -> void:
	_angle = move_toward(_angle, _target, SWING_SPEED * game_dt)
	_apply()


func _apply() -> void:
	_pivots[0].rotation.y = _angle
	_pivots[1].rotation.y = -_angle
