class_name CharacterModel
extends Node3D
## Animierte 3D-Figur. Modelle und Animationen stammen aus dem "Toon Shooter Game Kit"
## von Quaternius (CC0, quaternius.com), siehe assets/characters/.
##
## Rein optisch: Die Simulation kennt nur Position, Blickrichtung und "lebt/tot".
## Dieses Skript wählt daraus die passende Animation. Die Abspielgeschwindigkeit
## wird an den Zeitfaktor des Spiels gekoppelt, damit Schritte in Zeitlupe langsam sind.

const SCENES := {
	"officer": preload("res://assets/characters/Character_Soldier.gltf"),
	"enemy": preload("res://assets/characters/Character_Enemy.gltf"),
	"hostage": preload("res://assets/characters/Character_Hazmat.gltf"),
}
## Waffe, die sichtbar bleibt ("" = unbewaffnet). Alle anderen Waffen-Meshes werden versteckt.
const WEAPON := {"officer": "SMG", "enemy": "AK", "hostage": ""}
const ALL_WEAPONS := ["AK", "GrenadeLauncher", "Knife_1", "Knife_2", "Pistol", "Revolver",
	"Revolver_Small", "RocketLauncher", "ShortCannon", "Shotgun", "Shovel", "SMG", "Sniper", "Sniper_2"]
const LOOPING := ["Idle", "Walk", "Run", "Run_Gun", "Run_Shoot", "Walk_Shoot"]
## Materialien, die mit der Teamfarbe eingefärbt werden.
const TINT_MATERIALS := ["Character_Main", "Hazmat_Main"]
const MODEL_SCALE := 0.85
const RUN_SPEED := 1.5          # ab dieser Geschwindigkeit (m/s) Lauf- statt Geh-Animation

var _anim: AnimationPlayer
var _armed := false
var _aiming := false         # Waffe angelegt (Zielhaltung); nur optisch
var _state := ""
var _dead := false
var _inst: Node3D
var _meshes: Array[MeshInstance3D] = []
var _dim_mat: StandardMaterial3D
var _dimmed := false
var _rolling := false
var _crouched := false
var _roll_angle := 0.0

const ROLL_TURNS_PER_SEC := 2.2  # Überschläge pro Spielsekunde während der Hechtrolle
const ROLL_PIVOT := 0.55         # Höhe des Drehpunkts


func build(kind: String, tint: Color) -> void:
	var inst: Node3D = SCENES[kind].instantiate()
	inst.scale = Vector3.ONE * MODEL_SCALE
	add_child(inst)
	_inst = inst
	_dim_mat = StandardMaterial3D.new()
	_dim_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_dim_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_dim_mat.albedo_color = Color(0.0, 0.0, 0.02, 0.74)
	_anim = inst.find_child("AnimationPlayer", true, false)
	_armed = WEAPON[kind] != ""
	for w in ALL_WEAPONS:
		var node := inst.find_child(w, true, false) as Node3D
		if node:
			node.visible = w == WEAPON[kind]
	for a in LOOPING:
		if _anim.has_animation(a):
			_anim.get_animation(a).loop_mode = Animation.LOOP_LINEAR
	_apply_tint(inst, tint)
	reset()


func _apply_tint(node: Node, tint: Color) -> void:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		_meshes.append(mi)
		for s in mi.mesh.get_surface_count():
			var mat := mi.mesh.surface_get_material(s) as StandardMaterial3D
			if mat and mat.resource_name in TINT_MATERIALS:
				var copy := mat.duplicate() as StandardMaterial3D
				copy.albedo_color = tint
				mi.set_surface_override_material(s, copy)
	for c in node.get_children():
		_apply_tint(c, tint)


## Pro Frame: Bewegungsanimation passend zur Geschwindigkeit, Tempo passend zur Spielzeit.
## game_dt: seit dem letzten Frame vergangene Spielzeit (treibt den Überschlag der Rolle).
func update(speed: float, time_scale: float, game_dt := 0.0) -> void:
	_anim.speed_scale = time_scale
	if _dead:
		return
	if _rolling:
		_roll_angle += TAU * ROLL_TURNS_PER_SEC * game_dt
		_apply_roll()
		return
	if _state == "shoot" and _anim.is_playing():
		return
	if _crouched:
		if _state != "crouch":
			_state = "crouch"
			_anim.play("Duck", 0.1, 0.0)
			_anim.seek(_anim.get_animation("Duck").length * 0.5, true)
		return
	var want := "stand"
	if speed > RUN_SPEED:
		want = "run"
	elif speed > 0.1:
		want = "walk"
	if want != _state:
		_enter(want)


## Waffe anlegen/gesenkt. Merkt den Wert und wechselt sofort die Pose, solange die
## Figur steht, geht oder läuft; bei toten/rollenden Figuren wird nur der Wert gemerkt.
func set_aiming(on: bool) -> void:
	if on == _aiming:
		return
	_aiming = on
	if _state == "stand" or _state == "walk" or _state == "run":
		_enter(_state)


## Abdunkeln über ein halbtransparentes schwarzes Overlay auf allen Meshes.
func set_dim(on: bool) -> void:
	if on == _dimmed:
		return
	_dimmed = on
	for mi in _meshes:
		mi.material_overlay = _dim_mat if on else null


## Hechtrolle: geduckte Haltung, das ganze Modell überschlägt sich nach vorn.
## Das Kit hat keine Roll-Animation, deshalb wird die Drehung per Code erzeugt.
func set_rolling(on: bool) -> void:
	if on == _rolling or _dead:
		return
	_rolling = on
	_roll_angle = 0.0
	if on:
		_state = "roll"
		_anim.play("Duck", 0.05, 0.0)
		_anim.seek(_anim.get_animation("Duck").length * 0.5, true)
	else:
		_state = ""
	_apply_roll()


func _apply_roll() -> void:
	var b := Basis(Vector3.RIGHT, _roll_angle)
	var pivot := Vector3(0.0, ROLL_PIVOT, 0.0)
	_inst.transform = Transform3D(b.scaled(Vector3.ONE * MODEL_SCALE), pivot - b * pivot)


## Geduckte Haltung (auch in Bewegung: das Kit hat keinen Schleich-Gang).
func set_crouched(on: bool) -> void:
	_crouched = on
	if not on and _state == "crouch":
		_state = ""


## Einmaliger Stoß nach vorn (Rammbock).
func punch() -> void:
	if _dead:
		return
	_state = "shoot"
	_anim.play("Punch", 0.05, 1.3)
	_anim.seek(0.0, true)


## Wurfbewegung für die Blendgranate.
func throw() -> void:
	if _dead or _rolling:
		return
	_state = "shoot"
	_anim.play("Punch", 0.05, 1.0)
	_anim.seek(0.0, true)


func shoot() -> void:
	if _dead or _rolling or _crouched or not _armed or _state == "run" or _state == "walk":
		return   # im Laufen zeigt die Lauf-Animation bereits die Schusshaltung
	_state = "shoot"
	_anim.play("Idle_Shoot", 0.0, 1.0)
	_anim.seek(0.0, true)


func die(instant := false) -> void:
	set_rolling(false)
	_dead = true
	_state = "dead"
	_anim.play("Death", 0.0 if instant else 0.05)
	if instant:
		_anim.seek(_anim.get_animation("Death").length, true)


## Zurück in die Grundhaltung (Checkpoint-Reset, Wiederbelebung im Replay).
func reset() -> void:
	_dead = false
	_rolling = false
	_crouched = false
	_roll_angle = 0.0
	_apply_roll()
	_state = ""
	_enter("stand", 0.0)


func _enter(state: String, blend := 0.12) -> void:
	_state = state
	match state:
		"run":
			if _armed:
				_anim.play("Run_Shoot" if _aiming else "Run_Gun", blend)
			else:
				_anim.play("Run", blend)
		"walk":
			if _armed:
				_anim.play("Walk_Shoot" if _aiming else "Walk", blend)
			else:
				_anim.play("Walk", blend)
		"stand":
			if _armed:
				if _aiming:
					# Zielhaltung = erstes Bild der Schuss-Animation. Standbilder mit
					# Abspieltempo 0 (statt pause()), damit das Überblenden aus der
					# vorigen Animation trotzdem zu Ende läuft.
					_anim.play("Idle_Shoot", blend, 0.0)
					_anim.seek(0.0, true)
				else:
					# Waffe gesenkt: normale Stand-Animation, loopt
					_anim.play("Idle", blend)
			else:
				# Geiseln kauern am Boden
				_anim.play("Duck", 0.0, 0.0)
				_anim.seek(_anim.get_animation("Duck").length * 0.5, true)
