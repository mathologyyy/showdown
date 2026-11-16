class_name Level
extends Node3D
## Handgebaute, kompakte Test-Wohnung. Sie ist so klein gehalten, dass sie komplett
## ins Bild passt (feste Kamera, nichts liegt außerhalb des Bildschirms).
## Koordinaten: X nach rechts, Z nach unten (zum Betrachter).
## Wohnung x -8..8, z -4.5..4.5, Treppenhaus mit Eingangstür unten in der Mitte.
##
## Der Grundriss liegt auf einem 0,5-m-Raster. Sichtbar wird er aus austauschbaren
## Bausteinen (Szenen in assets/props/, siehe dort README.md) zusammengesetzt:
## Wände aus Modulen von 3 m, 1 m und 0,5 m, Böden aus 3×3, 3×1 und 1×1 m.
## Kollision, Deckung und Abpraller rechnet der Code unabhängig davon mit Quadern.
##
##   z=-4.5 ┌───────────┬────┬───────────┐
##          │ Schlafzi. │ E1 │  Küche    │
##          │   E3  H2  D    D    E4     │
##   z= 0   ├── D ──────┤Flur├───────────┤
##          │ Wohnzi.   │    │  Büro     │
##          │  E2   H1  D    D   E5  H3  │
##   z= 4.5 └───────────┴ D ─┴───────────┘
##                   Treppenhaus (Squad)

const WALL_H := 1.6
const WALL_T := 0.25
const FURN_H := 1.2     # höher als die Schusslinie (1.0): Möbel sind echte Deckung

const PROP_DIR := "res://assets/props/"
## Wand-Module, längstes zuerst: [Länge in m, Szenenname]
const WALL_MODULES := [[3.0, "wall_3m"], [1.0, "wall_1m"], [0.5, "wall_05m"]]

## Bereich, den die feste Kamera vollständig zeigen muss: [x_min, z_min, x_max, z_max]
const BOUNDS := [-8.4, -4.9, 8.4, 7.8]

## Bodenflächen [x1, z1, x2, z2], Kantenlängen in ganzen Metern.
const FLOORS := [
	[-8, -4.5, 8, 4.5],      # Wohnung
	[-2, 4.5, 2, 7.5],       # Treppenhaus
]

## Wände als achsenparallele Strecken [x1, z1, x2, z2] auf dem 0,5-m-Raster. Lücken = Türen.
const WALLS := [
	# Außenwände
	[-8, -4.5, 8, -4.5], [-8, -4.5, -8, 4.5], [8, -4.5, 8, 4.5],
	[-8, 4.5, -1, 4.5], [1, 4.5, 8, 4.5],
	# Treppenhaus
	[-2, 4.5, -2, 7.5], [2, 4.5, 2, 7.5], [-2, 7.5, 2, 7.5],
	# Flur links (Türen zu Schlaf- und Wohnzimmer)
	[-1.5, -4.5, -1.5, -3.5], [-1.5, -1.5, -1.5, 1.5], [-1.5, 3.5, -1.5, 4.5],
	# Flur rechts (Türen zu Küche und Büro)
	[1.5, -4.5, 1.5, -2], [1.5, 0, 1.5, 2], [1.5, 4, 1.5, 4.5],
	# Trennwand Schlafzimmer / Wohnzimmer mit Durchgang
	[-8, 0, -6.5, 0], [-5, 0, -1.5, 0],
	# Trennwand Küche / Büro
	[1.5, 0.5, 8, 0.5],
]

## Doppeltüren [x1, z1, x2, z2] in den 2 m breiten Wandlücken (je 0,125 m Abstand zum
## Wandende, weil die Wand-Kollision so weit in die Lücke ragt). Zu Beginn geschlossen,
## Officer öffnen sie mit E; den Eingang (Index 0) rammt Officer 3 im Intro auf.
## Der Durchgang Schlaf-/Wohnzimmer hat keine Tür.
const DOORS := [
	[-0.875, 4.5, 0.875, 4.5],      # Eingang
	[-1.5, -3.375, -1.5, -1.625],   # Schlafzimmer
	[-1.5, 1.625, -1.5, 3.375],     # Wohnzimmer
	[1.5, -1.875, 1.5, -0.125],     # Küche
	[1.5, 2.125, 1.5, 3.875],       # Büro
]

## Kisten [x, z, Breite(x), Tiefe(z)]: niedrige Deckung. Sie blockieren den Weg, aber
## weder Sicht noch Kugeln stehender Schützen. Wer geduckt direkt dahinter sitzt, kann
## nicht getroffen werden – muss zum Schießen aber aufstehen.
const CRATES := [
	[-0.5, 2.6, 0.9, 0.45],    # Flur vorn
	[0.5, -1.0, 0.9, 0.45],    # Flur hinten
	[-3.0, 2.2, 0.5, 1.0],     # Wohnzimmer
	[-2.6, -2.3, 0.5, 1.0],    # Schlafzimmer
	[2.3, -1.2, 0.5, 1.0],     # Küche
	[2.6, 3.0, 0.5, 1.0],      # Büro
]
const CRATE_H := 0.75
const CRATE_COLOR := Color(0.62, 0.50, 0.26)

## Möbel [x, z, Breite(x), Tiefe(z)]
const FURNITURE := [
	[-5.0, 3.9, 2.4, 0.8],    # Sofa
	[-4.8, 2.2, 1.3, 0.8],    # Couchtisch
	[-7.6, 2.4, 0.5, 1.8],    # Regal
	[-6.6, -3.3, 2.0, 2.0],   # Bett
	[-2.0, -4.0, 0.7, 0.8],   # Kleiderschrank
	[4.6, -2.0, 2.0, 0.9],    # Kücheninsel
	[5.2, -4.15, 4.5, 0.6],   # Küchenzeile
	[5.4, 1.7, 2.0, 0.8],     # Schreibtisch
]

## Metall-Objekte [x, z, Breite(x), Tiefe(z)]: Kugeln prallen daran ab (Einfallswinkel =
## Ausfallswinkel). Nur hier sind Schüsse "um die Ecke" möglich.
const METAL := [
	[1.15, 0.9, 0.45, 1.1],   # Stahlspind im Flur  -> Bande ins Schlaf- oder Wohnzimmer
	[-1.2, -0.6, 0.35, 1.2],  # Heizkörper im Flur  -> Bande in Küche oder Büro
	[7.5, -0.4, 0.7, 0.7],    # Kühlschrank
	[7.5, 3.5, 0.7, 1.5],     # Aktenschrank
	[-7.6, -0.9, 0.5, 1.4],   # Tresor im Schlafzimmer
]
const METAL_COLOR := Color(0.55, 0.72, 0.85)

## Squad startet im Treppenhaus seitlich der Tür (außer Sicht), Blick nach -Z (yaw = PI).
## Reihenfolge = Zugreihenfolge: vorn Blendgranate, Mitte Schild, hinten Durchschuss.
const OFFICER_SPAWNS := [
	Vector3(-1.4, 0, 5.2), Vector3(1.4, 0, 5.5), Vector3(-1.4, 0, 6.3),
]
const OFFICER_ROLES := ["flash", "shield", "pierce"]

## Gegner: pro Gegner mehrere mögliche Startplätze (Position, Blickpunkt, optionale
## Patrouille). Bei jeder neuen Mission wird je einer ausgelost.
const ENEMY_SPOTS := [
	[   # Flur
		{"pos": Vector3(0.0, 0, -3.7), "look": Vector3(0.0, 0, 4.5)},
		{"pos": Vector3(-0.5, 0, -2.4), "look": Vector3(0.0, 0, 4.5)},
		{"pos": Vector3(0.5, 0, -3.9), "look": Vector3(-1.5, 0, -2.5)},
	],
	[   # Wohnzimmer
		{"pos": Vector3(-6.6, 0, 1.2), "look": Vector3(-1.5, 0, 2.5)},
		{"pos": Vector3(-2.4, 0, 3.7), "look": Vector3(-1.5, 0, 2.5)},
		{"pos": Vector3(-6.9, 0, 3.6), "look": Vector3(-1.5, 0, 2.5)},
	],
	[   # Schlafzimmer
		{"pos": Vector3(-2.8, 0, -1.2), "look": Vector3(-7.0, 0, -1.2),
			"patrol": [Vector3(-6.8, 0, -1.2), Vector3(-2.8, 0, -1.2)]},
		{"pos": Vector3(-4.8, 0, -1.0), "look": Vector3(-1.5, 0, -2.5)},
		{"pos": Vector3(-3.0, 0, -3.6), "look": Vector3(-1.5, 0, -2.5)},
	],
	[   # Küche
		{"pos": Vector3(4.6, 0, -3.2), "look": Vector3(1.5, 0, -1.0)},
		{"pos": Vector3(6.8, 0, -1.9), "look": Vector3(1.5, 0, -1.0)},
		{"pos": Vector3(3.0, 0, -0.5), "look": Vector3(1.5, 0, -1.0)},
	],
	[   # Büro
		{"pos": Vector3(6.2, 0, 3.3), "look": Vector3(1.5, 0, 3.0)},
		{"pos": Vector3(3.2, 0, 1.2), "look": Vector3(1.5, 0, 3.0)},
		{"pos": Vector3(4.0, 0, 3.9), "look": Vector3(1.5, 0, 3.0)},
	],
]

const HOSTAGES := [
	Vector3(-3.2, 0, 0.9),    # H1 Wohnzimmer
	Vector3(-4.2, 0, -3.8),   # H2 Schlafzimmer
	Vector3(6.9, 0, 1.2),     # H3 Büro, neben dem Schreibtisch
]


var _scenes := {}                # Szenenname -> PackedScene (oder null, wenn die Datei fehlt)


func build() -> void:
	for f in FLOORS:
		_lay_floor(f[0], f[1], f[2], f[3])
	var posts := {}                  # Wandenden (jedes nur einmal): dort steht ein Pfosten
	for w in WALLS:
		var a := Vector3(w[0], 0, w[1])
		var b := Vector3(w[2], 0, w[3])
		# Kollision: ein Quader pro Strecke, an beiden Enden um die halbe Wandstärke länger
		var size := Vector3(absf(b.x - a.x) + WALL_T, WALL_H, absf(b.z - a.z) + WALL_T)
		_add_collider((a + b) * 0.5 + Vector3(0, WALL_H * 0.5, 0), size)
		_lay_wall(a, b)
		posts[a] = true
		posts[b] = true
	for p: Vector3 in posts:
		_place("wall_post", p)
	for f in FURNITURE:
		_add_prop("furniture", f, FURN_H)
	for c in CRATES:
		_add_prop("crate", c, CRATE_H, false, Actor.LAYER_CRATE)
	for m in METAL:
		_add_prop("metal_cabinet", m, FURN_H, true)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-60, 35, 0)
	sun.light_energy = 1.1
	sun.shadow_enabled = true
	add_child(sun)

	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.02, 0.02, 0.03)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.75, 0.78, 0.85)
	env.ambient_light_energy = 0.6
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)


## Wandstrecke a–b mit Modulen belegen: längste zuerst, lückenlos von einem Ende zum anderen.
func _lay_wall(a: Vector3, b: Vector3) -> void:
	var along_x := absf(b.x - a.x) > absf(b.z - a.z)
	var start := a if a.x + a.z <= b.x + b.z else b
	var dir := Vector3.RIGHT if along_x else Vector3.BACK
	var yaw := 0.0 if along_x else PI * 0.5
	var units := roundi(a.distance_to(b) * 2.0)      # Länge in halben Metern
	var cursor := 0.0
	for m in WALL_MODULES:
		var length: float = m[0]
		var prop: String = m[1]
		var u := roundi(length * 2.0)
		while units >= u:
			_place(prop, start + dir * (cursor + length * 0.5), yaw)
			cursor += length
			units -= u


## Bodenfläche mit 3×3-, 3×1- und 1×1-Platten belegen (Kanten in ganzen Metern).
func _lay_floor(x1: float, z1: float, x2: float, z2: float) -> void:
	var w := roundi(x2 - x1)
	var d := roundi(z2 - z1)
	var x := 0
	while x < w:
		var sx := 3 if w - x >= 3 else 1
		var z := 0
		while z < d:
			var sz := 3 if d - z >= 3 else 1
			var c := Vector3(x1 + x + sx * 0.5, 0.0, z1 + z + sz * 0.5)
			if sx == 3 and sz == 3:
				_place("floor_3x3", c)
			elif sx == 3:
				_place("floor_3x1", c)
			elif sz == 3:
				_place("floor_3x1", c, PI * 0.5)
			else:
				_place("floor_1x1", c)
			z += sz
		x += sx


## Möbel, Kiste oder Metall-Objekt aus einer Tabellenzeile [x, z, Breite(x), Tiefe(z)]:
## Kollisions-Quader plus der auf diese Maße gestreckte Baustein.
func _add_prop(prop: String, e: Array, height: float, metal := false,
		layer := Actor.LAYER_WORLD) -> void:
	var size := Vector3(e[2], height, e[3])
	_add_collider(Vector3(e[0], height * 0.5, e[1]), size, metal, layer)
	_place(prop, Vector3(e[0], 0.0, e[1]), 0.0, size)


## Baustein (Szene aus assets/props/) an eine Stelle setzen. Ursprung der Szene =
## Bodenmitte. Fehlt die Datei, bleibt die Stelle unsichtbar (Warnung), die Kollision steht.
func _place(prop: String, pos: Vector3, yaw := 0.0, scl := Vector3.ONE) -> Node3D:
	if not _scenes.has(prop):
		var path := PROP_DIR + prop + ".tscn"
		_scenes[prop] = load(path) if ResourceLoader.exists(path) else null
		if _scenes[prop] == null:
			push_warning("Level: Baustein %s fehlt." % path)
	var ps: PackedScene = _scenes[prop]
	if ps == null:
		return null
	var n := ps.instantiate() as Node3D
	add_child(n)
	n.position = pos
	n.rotation.y = yaw
	n.scale = scl
	return n


## Unsichtbarer massiver Quader: blockiert Bewegung, Sicht und Kugeln.
## metal: Kugeln prallen ab (der GameManager fragt das Meta-Feld "metal" ab).
func _add_collider(center: Vector3, size: Vector3, metal := false,
		layer := Actor.LAYER_WORLD) -> void:
	var body := StaticBody3D.new()
	body.set_meta("metal", metal)
	body.collision_layer = layer
	body.collision_mask = 0
	body.position = center
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	cs.shape = shape
	body.add_child(cs)
	add_child(body)
