class_name CharacterModel
extends Node3D
## Animierte 3D-Figur. Modelle und Animationen stammen aus dem "Toon Shooter Game Kit"
## von Quaternius (CC0, quaternius.com), siehe assets/characters/.
##
## Rein optisch: Die Simulation kennt nur Position, Blickrichtung und "lebt/tot".
## Dieses Skript wählt daraus die passende Animation. Die Abspielgeschwindigkeit
## wird an den Zeitfaktor des Spiels gekoppelt, damit Schritte in Zeitlupe langsam sind.

## Ein Eintrag pro Figurenart – hier werden Modelle ausgetauscht.
##   scene   Modell-Datei (Pflicht)
##   weapon  Name des Waffen-Knotens, der sichtbar bleibt ("" = unbewaffnet)
## Optional, wenn ein Modell nicht aus dem Quaternius-Kit stammt:
##   scale   Größe (Standard MODEL_SCALE)
##   anims   {Rolle der Animation: Name im Modell}, überschreibt einzelne Einträge von ANIMS
##   tint    Namen der Materialien, die die Teamfarbe bekommen (Standard TINT_MATERIALS)
## Die drei Officer haben je einen eigenen Eintrag, zeigen aber noch auf dasselbe Modell.
const MODELS := {
	"officer_flash": {"scene": preload("res://assets/characters/Character_Soldier.gltf"), "weapon": "SMG"},
	"officer_shield": {"scene": preload("res://assets/characters/Character_Soldier.gltf"), "weapon": "SMG"},
	"officer_pierce": {"scene": preload("res://assets/characters/Character_Soldier.gltf"), "weapon": "SMG"},
	"enemy": {"scene": preload("res://assets/characters/Character_Enemy.gltf"), "weapon": "AK"},
	"hostage": {"scene": preload("res://assets/characters/Character_Hazmat.gltf"), "weapon": ""},
}
## Welche Animation des Modells welche Rolle spielt (Namen des Quaternius-Kits).
## Fehlt eine Animation im Modell, wird sie einfach nicht abgespielt.
const ANIMS := {
	"idle": "Idle",             # stehen, Waffe gesenkt
	"walk": "Walk",
	"run": "Run",               # laufen, unbewaffnet
	"run_gun": "Run_Gun",       # laufen, Waffe gesenkt
	"walk_aim": "Walk_Shoot",   # gehen, Waffe angelegt
	"run_aim": "Run_Shoot",     # laufen, Waffe angelegt
	"aim_shoot": "Idle_Shoot",  # erstes Bild = Zielhaltung, abgespielt = Schuss
	"duck": "Duck",             # Mitte der Animation = geduckte Haltung
	"punch": "Punch",           # Rammbock-Stoß und Granatenwurf
	"death": "Death",
}
## Diese Rollen laufen in Schleife.
const LOOPING := ["idle", "walk", "run", "run_gun", "walk_aim", "run_aim"]
## Alle Waffen-Knoten des Kits: bis auf die gewählte werden sie versteckt.
const ALL_WEAPONS := ["AK", "GrenadeLauncher", "Knife_1", "Knife_2", "Pistol", "Revolver",
	"Revolver_Small", "RocketLauncher", "ShortCannon", "Shotgun", "Shovel", "SMG", "Sniper", "Sniper_2"]
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
var _names := {}             # Rolle der Animation -> Name im Modell (ANIMS + Überschreibungen)
var _tint_names: Array = TINT_MATERIALS
var _scale := MODEL_SCALE

const ROLL_HOP := 0.55           # Scheitelhöhe des Hechtsprungs (m)
const ROLL_HOP_TURNS := 0.9      # nach so vielen Überschlägen ist die Figur wieder am Boden
const ROLL_TURNS_PER_SEC := 2.2  # Überschläge pro Spielsekunde während der Hechtrolle
const ROLL_PIVOT := 0.55         # Höhe des Drehpunkts


func build(kind: String, tint: Color) -> void:
	var def: Dictionary = MODELS[kind]
	_names = ANIMS.duplicate()
	_names.merge(def.get("anims", {}), true)
	_tint_names = def.get("tint", TINT_MATERIALS)
	_scale = def.get("scale", MODEL_SCALE)
	var weapon: String = def.get("weapon", "")
	var inst: Node3D = def.scene.instantiate()
	inst.scale = Vector3.ONE * _scale
	add_child(inst)
	_inst = inst
	_dim_mat = StandardMaterial3D.new()
	_dim_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_dim_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_dim_mat.albedo_color = Color(0.0, 0.0, 0.02, 0.74)
	_anim = inst.find_child("AnimationPlayer", true, false)
	_armed = weapon != ""
	for w in ALL_WEAPONS:
		var node := inst.find_child(w, true, false) as Node3D
		if node:
			node.visible = w == weapon
	for key in LOOPING:
		if _has(key):
			_anim.get_animation(_names[key]).loop_mode = Animation.LOOP_LINEAR
	_apply_tint(inst, tint)
	reset()


## Hat das Modell die Animation für diese Rolle?
func _has(key: String) -> bool:
	return _anim != null and _anim.has_animation(_names.get(key, ""))


## Animation einer Rolle abspielen (blend/speed wie AnimationPlayer.play).
func _play(key: String, blend := -1.0, speed := 1.0) -> void:
	if _has(key):
		_anim.play(_names[key], blend, speed)


## Abspielposition setzen: frac 0 = Anfang, 1 = Ende der Animation dieser Rolle.
func _seek(key: String, frac: float) -> void:
	if _has(key):
		_anim.seek(_anim.get_animation(_names[key]).length * frac, true)


## Standbild: ein Bild aus der Animation als Pose (Abspieltempo 0, damit das
## Überblenden aus der vorigen Animation trotzdem zu Ende läuft).
func _pose(key: String, frac: float, blend: float) -> void:
	_play(key, blend, 0.0)
	_seek(key, frac)


func _apply_tint(node: Node, tint: Color) -> void:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		_meshes.append(mi)
		for s in mi.mesh.get_surface_count():
			var mat := mi.mesh.surface_get_material(s) as StandardMaterial3D
			if mat and mat.resource_name in _tint_names:
				var copy := mat.duplicate() as StandardMaterial3D
				copy.albedo_color = tint
				mi.set_surface_override_material(s, copy)
	for c in node.get_children():
		_apply_tint(c, tint)


## Pro Frame: Bewegungsanimation passend zur Geschwindigkeit, Tempo passend zur Spielzeit.
## game_dt: seit dem letzten Frame vergangene Spielzeit (treibt den Überschlag der Rolle).
func update(speed: float, time_scale: float, game_dt := 0.0) -> void:
	if _anim:
		_anim.speed_scale = time_scale
	if _dead:
		return
	if _rolling:
		_roll_angle += TAU * ROLL_TURNS_PER_SEC * game_dt
		_apply_roll()
		return
	if _state == "shoot" and _anim != null and _anim.is_playing():
		return
	if _crouched:
		if _state != "crouch":
			_state = "crouch"
			_pose("duck", 0.5, 0.1)
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
		_pose("duck", 0.5, 0.05)
	else:
		_state = ""
	_apply_roll()


func _apply_roll() -> void:
	var b := Basis(Vector3.RIGHT, _roll_angle)
	var pivot := Vector3(0.0, ROLL_PIVOT, 0.0)
	# Hechtsprung: die Figur hebt im Bogen ab (rein optisch), so fliegt sie sichtbar
	# über geduckte Kollegen hinweg
	var hop := ROLL_HOP * sin(clampf(_roll_angle / (TAU * ROLL_HOP_TURNS), 0.0, 1.0) * PI)
	_inst.transform = Transform3D(b.scaled(Vector3.ONE * _scale), pivot - b * pivot + Vector3(0.0, hop, 0.0))


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
	_play("punch", 0.05, 1.3)
	_seek("punch", 0.0)


## Wurfbewegung für die Blendgranate.
func throw() -> void:
	if _dead or _rolling:
		return
	_state = "shoot"
	_play("punch", 0.05, 1.0)
	_seek("punch", 0.0)


func shoot() -> void:
	if _dead or _rolling or _crouched or not _armed or _state == "run" or _state == "walk":
		return   # im Laufen zeigt die Lauf-Animation bereits die Schusshaltung
	_state = "shoot"
	_play("aim_shoot", 0.0, 1.0)
	_seek("aim_shoot", 0.0)


func die(instant := false) -> void:
	set_rolling(false)
	_dead = true
	_state = "dead"
	_play("death", 0.0 if instant else 0.05)
	if instant:
		_seek("death", 1.0)


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
				_play("run_aim" if _aiming else "run_gun", blend)
			else:
				_play("run", blend)
		"walk":
			if _armed:
				_play("walk_aim" if _aiming else "walk", blend)
			else:
				_play("walk", blend)
		"stand":
			if _armed:
				if _aiming:
					# Zielhaltung = erstes Bild der Schuss-Animation. Standbilder mit
					# Abspieltempo 0 (statt pause()), damit das Überblenden aus der
					# vorigen Animation trotzdem zu Ende läuft.
					_pose("aim_shoot", 0.0, blend)
				else:
					# Waffe gesenkt: normale Stand-Animation, loopt
					_play("idle", blend)
			else:
				# Geiseln kauern am Boden
				_pose("duck", 0.5, 0.0)
