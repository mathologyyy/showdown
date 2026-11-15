class_name LaserBeam
extends Node3D
## Dünner Laserstrahl zwischen zwei Punkten. Wird pro Frame vom GameManager
## gesetzt, deshalb ohne Physik-Interpolation.

var _beam: MeshInstance3D


func _init(color: Color, thickness := 0.03) -> void:
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF

	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = color
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA

	_beam = MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(thickness, thickness, 1.0)
	_beam.mesh = bm
	_beam.material_override = mat
	_beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_beam)


func set_alpha(a: float) -> void:
	(_beam.material_override as StandardMaterial3D).albedo_color.a = a


func set_points(from: Vector3, to: Vector3) -> void:
	var d := to - from
	var length := d.length()
	if length < 0.01:
		_beam.visible = false
		return
	_beam.visible = true
	_beam.global_transform = Transform3D(Basis.looking_at(d / length, Vector3.UP), (from + to) * 0.5)
	_beam.scale = Vector3(1.0, 1.0, length)
