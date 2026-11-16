class_name Level
extends Node3D
## Handgebaute, kompakte Test-Wohnung aus Quadern. Sie ist so klein gehalten, dass
## sie komplett ins Bild passt (feste Kamera, nichts liegt außerhalb des Bildschirms).
## Koordinaten: X nach rechts, Z nach unten (zum Betrachter).
## Wohnung x -8..8, z -4.5..4.5, Treppenhaus mit Eingangstür unten in der Mitte.
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

## Bereich, den die feste Kamera vollständig zeigen muss: [x_min, z_min, x_max, z_max]
const BOUNDS := [-8.4, -4.9, 8.4, 7.3]

## Wände als Achsen-parallele Strecken [x1, z1, x2, z2]. Lücken = Türen.
const WALLS := [
	# Außenwände
	[-8, -4.5, 8, -4.5], [-8, -4.5, -8, 4.5], [8, -4.5, 8, 4.5],
	[-8, 4.5, -1.1, 4.5], [1.1, 4.5, 8, 4.5],
	# Treppenhaus
	[-2.2, 4.5, -2.2, 7], [2.2, 4.5, 2.2, 7], [-2.2, 7, 2.2, 7],
	# Flur links (Türen zu Schlaf- und Wohnzimmer)
	[-1.25, -4.5, -1.25, -3.4], [-1.25, -1.2, -1.25, 1.1], [-1.25, 3.3, -1.25, 4.5],
	# Flur rechts (Türen zu Küche und Büro)
	[1.25, -4.5, 1.25, -2.1], [1.25, 0.1, 1.25, 1.9], [1.25, 4.1, 1.25, 4.5],
	# Trennwand Schlafzimmer / Wohnzimmer mit Durchgang
	[-8, 0, -6.3, 0], [-4.9, 0, -1.25, 0],
	# Trennwand Küche / Büro
	[1.25, 0.3, 8, 0.3],
]

## Doppeltüren [x1, z1, x2, z2] in den Wandlücken (gut 2 m breit). Zu Beginn geschlossen,
## Officer öffnen sie mit E; den Eingang (Index 0) rammt Officer 3 im Intro auf.
## Der Durchgang Schlaf-/Wohnzimmer hat keine Tür.
const DOORS := [
	[-0.975, 4.5, 0.975, 4.5],        # Eingang
	[-1.25, -3.275, -1.25, -1.325],   # Schlafzimmer
	[-1.25, 1.225, -1.25, 3.175],     # Wohnzimmer
	[1.25, -1.975, 1.25, -0.025],     # Küche
	[1.25, 2.025, 1.25, 3.975],       # Büro
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
	[-1.8, -4.0, 0.7, 0.8],   # Kleiderschrank
	[4.6, -2.0, 2.0, 0.9],    # Kücheninsel
	[5.2, -4.15, 4.5, 0.6],   # Küchenzeile
	[5.4, 1.7, 2.0, 0.8],     # Schreibtisch
]

## Metall-Objekte [x, z, Breite(x), Tiefe(z)]: Kugeln prallen daran ab (Einfallswinkel =
## Ausfallswinkel). Nur hier sind Schüsse "um die Ecke" möglich.
const METAL := [
	[0.9, 0.9, 0.45, 1.1],    # Stahlspind im Flur  -> Bande ins Schlaf- oder Wohnzimmer
	[-0.95, -0.6, 0.35, 1.2], # Heizkörper im Flur  -> Bande in Küche oder Büro
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
		{"pos": Vector3(0.5, 0, -3.9), "look": Vector3(-1.25, 0, -2.3)},
	],
	[   # Wohnzimmer
		{"pos": Vector3(-6.6, 0, 1.2), "look": Vector3(-1.25, 0, 2.2)},
		{"pos": Vector3(-2.4, 0, 3.7), "look": Vector3(-1.25, 0, 2.2)},
		{"pos": Vector3(-6.9, 0, 3.6), "look": Vector3(-1.25, 0, 2.2)},
	],
	[   # Schlafzimmer
		{"pos": Vector3(-2.8, 0, -1.2), "look": Vector3(-7.0, 0, -1.2),
			"patrol": [Vector3(-6.8, 0, -1.2), Vector3(-2.8, 0, -1.2)]},
		{"pos": Vector3(-4.8, 0, -1.0), "look": Vector3(-1.25, 0, -2.3)},
		{"pos": Vector3(-3.0, 0, -3.6), "look": Vector3(-1.25, 0, -2.3)},
	],
	[   # Küche
		{"pos": Vector3(4.6, 0, -3.2), "look": Vector3(1.25, 0, -1.0)},
		{"pos": Vector3(6.8, 0, -1.9), "look": Vector3(1.25, 0, -1.0)},
		{"pos": Vector3(3.0, 0, -0.5), "look": Vector3(1.25, 0, -1.0)},
	],
	[   # Büro
		{"pos": Vector3(6.2, 0, 3.3), "look": Vector3(1.25, 0, 3.0)},
		{"pos": Vector3(3.2, 0, 1.2), "look": Vector3(1.25, 0, 3.0)},
		{"pos": Vector3(4.0, 0, 3.9), "look": Vector3(1.25, 0, 3.0)},
	],
]

const HOSTAGES := [
	Vector3(-3.2, 0, 0.9),    # H1 Wohnzimmer
	Vector3(-4.2, 0, -3.8),   # H2 Schlafzimmer
	Vector3(6.9, 0, 1.2),     # H3 Büro, neben dem Schreibtisch
]


func build() -> void:
	_add_floor(Vector3(0, -0.05, 0), Vector3(16, 0.1, 9), Color(0.30, 0.28, 0.25))
	_add_floor(Vector3(0, -0.05, 5.75), Vector3(4.4, 0.1, 2.5), Color(0.20, 0.20, 0.22))
	for w in WALLS:
		var a := Vector3(w[0], 0, w[1])
		var b := Vector3(w[2], 0, w[3])
		var size := Vector3(absf(b.x - a.x) + WALL_T, WALL_H, absf(b.z - a.z) + WALL_T)
		_add_box((a + b) * 0.5 + Vector3(0, WALL_H * 0.5, 0), size, Color(0.62, 0.62, 0.66))
	for f in FURNITURE:
		_add_box(Vector3(f[0], FURN_H * 0.5, f[1]), Vector3(f[2], FURN_H, f[3]), Color(0.45, 0.30, 0.18))
	for c in CRATES:
		_add_box(Vector3(c[0], CRATE_H * 0.5, c[1]), Vector3(c[2], CRATE_H, c[3]), CRATE_COLOR,
				false, Actor.LAYER_CRATE)
	for m in METAL:
		_add_box(Vector3(m[0], FURN_H * 0.5, m[1]), Vector3(m[2], FURN_H, m[3]), METAL_COLOR, true)

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


## Massiver Quader: blockiert Bewegung, Sicht und Kugeln.
## metal: Kugeln prallen ab (der GameManager fragt das Meta-Feld "metal" ab).
func _add_box(center: Vector3, size: Vector3, color: Color, metal := false,
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
	var mesh := _box_mesh(size, color)
	if metal:
		var mat := mesh.material_override as StandardMaterial3D
		mat.metallic = 0.85
		mat.roughness = 0.25
		mat.emission_enabled = true          # leichtes Eigenleuchten: als Bande erkennbar
		mat.emission = color * 0.25
	body.add_child(mesh)
	add_child(body)


func _add_floor(center: Vector3, size: Vector3, color: Color) -> void:
	var mi := _box_mesh(size, color)
	mi.position = center
	add_child(mi)


func _box_mesh(size: Vector3, color: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mi.material_override = mat
	return mi
