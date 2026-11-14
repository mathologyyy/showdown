class_name VisionSystem
extends CanvasLayer
## Sichtkegel + Abdunkelung.
##
## Pro Officer wird per Raycast-Fächer ein Sichtpolygon auf dem Boden berechnet
## (Wände und Möbel blockieren), auf den Bildschirm projiziert und weiß in einen
## kleinen SubViewport gezeichnet. Ein bildschirmfüllendes ColorRect mit Shader
## (shaders/fog.gdshader) dunkelt alles außerhalb dieser Maske ab.
## Dieselben Kegel entscheiden über is_point_visible(), ob Gegner/Geiseln
## überhaupt gerendert werden.

@export var cone_deg := 20.0          # gesamter Öffnungswinkel
@export var view_range := 16.0
@export var near_radius := 1.2        # kleiner Kreis um jeden Officer, damit man sich selbst sieht
@export var ray_count := 28
@export var wall_reveal := 0.7       # wie weit über den Trefferpunkt hinaus aufgedeckt wird (zeigt die Wand)

const MASK_SCALE := 0.5

var enabled := true : set = set_enabled

var _viewport: SubViewport
var _fog: ColorRect
var _polys: Array[Polygon2D] = []
var _sources: Array = []              # [{pos: Vector3, yaw: float}] der lebenden Officer
var _space: PhysicsDirectSpaceState3D


func _ready() -> void:
	layer = 1
	_viewport = SubViewport.new()
	_viewport.disable_3d = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_viewport)
	var bg := ColorRect.new()
	bg.color = Color.BLACK
	bg.size = Vector2(8192, 8192)
	_viewport.add_child(bg)

	_fog = ColorRect.new()
	_fog.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_fog.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/fog.gdshader")
	mat.set_shader_parameter("mask_tex", _viewport.get_texture())
	_fog.material = mat
	add_child(_fog)


func set_enabled(value: bool) -> void:
	enabled = value
	if _fog:
		_fog.visible = value


## Pro Frame aufrufen. sources: [{pos, yaw}] aller lebenden Officer.
func update(camera: Camera3D, sources: Array, space: PhysicsDirectSpaceState3D) -> void:
	_sources = sources
	_space = space
	if not enabled:
		return
	var screen := get_viewport().get_visible_rect().size
	var msize := Vector2i(screen * MASK_SCALE)
	if _viewport.size != msize:
		_viewport.size = msize

	# zwei Polygone pro Officer: Kegel und Nahbereichs-Kreis
	while _polys.size() < sources.size() * 2:
		var p := Polygon2D.new()
		p.color = Color.WHITE
		_viewport.add_child(p)
		_polys.append(p)
	for i in _polys.size():
		_polys[i].visible = i < sources.size() * 2

	var half := deg_to_rad(cone_deg) * 0.5
	for i in sources.size():
		var origin: Vector3 = sources[i].pos
		var eye := Vector3(origin.x, Actor.EYE_HEIGHT, origin.z)
		var yaw: float = sources[i].yaw

		var cone := PackedVector2Array()
		cone.append(_project(camera, origin))
		for r in ray_count + 1:
			var a := yaw - half + (2.0 * half) * float(r) / float(ray_count)
			var dir := Vector3(sin(a), 0.0, cos(a))
			var end := eye + dir * view_range
			var hit := _space.intersect_ray(
					PhysicsRayQueryParameters3D.create(eye, end, Actor.LAYER_WORLD))
			if hit:
				end = hit.position + dir * wall_reveal
			cone.append(_project(camera, end))
		_polys[i * 2].polygon = cone

		var circle := PackedVector2Array()
		for c in 20:
			var a := TAU * float(c) / 20.0
			circle.append(_project(camera, origin + Vector3(cos(a), 0.0, sin(a)) * near_radius))
		_polys[i * 2 + 1].polygon = circle


func _project(camera: Camera3D, p: Vector3) -> Vector2:
	return camera.unproject_position(Vector3(p.x, 0.0, p.z)) * MASK_SCALE


## Liegt ein Punkt (Figur) in einem Sichtkegel und ist nicht durch die Welt verdeckt?
func is_point_visible(p: Vector3) -> bool:
	if not enabled:
		return true
	if _space == null:
		return false
	var half := deg_to_rad(cone_deg) * 0.5
	var target := Vector3(p.x, Actor.EYE_HEIGHT, p.z)
	for s in _sources:
		var eye := Vector3(s.pos.x, Actor.EYE_HEIGHT, s.pos.z)
		var d := target - eye
		var dist := d.length()
		if dist <= near_radius + Actor.RADIUS:
			return true
		if dist > view_range:
			continue
		# Figur zählt als sichtbar, sobald ihr Rand in den Kegel ragt
		var margin := atan2(Actor.RADIUS, dist)
		if absf(angle_difference(s.yaw, atan2(d.x, d.z))) > half + margin:
			continue
		if _space.intersect_ray(PhysicsRayQueryParameters3D.create(eye, target, Actor.LAYER_WORLD)):
			continue
		return true
	return false
