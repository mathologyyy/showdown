class_name FxOverlay
extends Control
## 2D-Effektebene ÜBER der Abdunkelung: Kugeln, Mündungsfeuer, Einschläge,
## Streubogen und die Markierung des aktiven Officers. Weltpunkte werden per Kamera
## auf den Bildschirm projiziert. Weil die Ebene über dem Sichtkegel-Nebel liegt,
## sieht man Mündungsfeuer und anfliegende Kugeln auch aus dem Dunkeln.

const MUZZLE_LIFE := 0.07       # Spielsekunden
const SPARK_LIFE := 0.16
const BLOOD_LIFE := 0.30
const PULSE_LIFE := 0.9         # echte Sekunden
const TRAIL_LIFE := 0.7         # echte Sekunden: so lange bleibt eine Schussbahn im Replay stehen
const BULLET_TAIL := 0.9        # sichtbare Länge der Leuchtspur in Metern

var camera: Camera3D
## Pro Frame vom GameManager gesetzt: [{pos: Vector3, dir: Vector3, enemy: bool}]
var bullets: Array = []
## Streubogen des aktiven Officers: {origin: Vector3, yaw, spread, dist} oder leer.
var arc: Dictionary = {}
## Markierung über dem aktiven Officer: {pos: Vector3, color: Color} oder leer.
var marker: Dictionary = {}
## Blendgranaten im Flug: [{pos: Vector3 (mit Flughöhe), ground: Vector3}]
var grenades: Array = []
## Anzeige über Gegnern: [{pos: Vector3, aim: 0..1 (bei 1 fällt der Schuss), blind: bool}]
var threats: Array = []
## Vorschau früherer Officer: [{color, points: [Vector3], shots: [{pos, dir}]}]
var ghosts: Array = []
## Wurf-Vorschau der Blendgranate: {from, to, radius} oder leer.
var throw_preview: Dictionary = {}
## Fristen über bedrohten Geiseln: [{pos, frac (0..1), seconds}]
var deadlines: Array = []
## Tasten-Hinweise in der Welt: [{pos, text}]
var prompts: Array = []

var _effects: Array = []        # [{kind, pos, dir, age, life, real, seed, color}]
var _time := 0.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func add_muzzle(pos: Vector3, dir: Vector3, enemy: bool) -> void:
	_effects.append({"kind": "muzzle", "pos": pos, "dir": dir, "age": 0.0, "life": MUZZLE_LIFE,
		"real": false, "color": Color(1.0, 0.7, 0.25) if enemy else Color(1.0, 0.95, 0.6)})


## on_body: Treffer an einer Figur (rot) statt an Wand/Möbel (Funken).
func add_impact(pos: Vector3, on_body: bool) -> void:
	_effects.append({"kind": "blood" if on_body else "spark", "pos": pos, "dir": Vector3.ZERO,
		"age": 0.0, "life": BLOOD_LIFE if on_body else SPARK_LIFE, "real": false,
		"seed": randi(), "color": Color(0.9, 0.05, 0.05) if on_body else Color(1.0, 0.9, 0.6)})


## Sich ausbreitender Ring auf dem Boden (Übernahme der Kontrolle).
func add_pulse(pos: Vector3, color: Color) -> void:
	_effects.append({"kind": "pulse", "pos": pos, "dir": Vector3.ZERO, "age": 0.0,
		"life": PULSE_LIFE, "real": true, "color": color})


## Blendgranate zündet: heller Blitz, der sich bis `radius` ausbreitet.
func add_flash(pos: Vector3, radius: float) -> void:
	_effects.append({"kind": "flash", "pos": pos, "dir": Vector3.ZERO, "age": 0.0,
		"life": 0.7, "real": true, "radius": radius, "color": Color.WHITE})


## Schussbahn, die kurz stehen bleibt und verblasst (Abschluss-Replay).
func add_trail(from: Vector3, to: Vector3, enemy: bool) -> void:
	_effects.append({"kind": "trail", "pos": from, "dir": to, "age": 0.0, "life": TRAIL_LIFE,
		"real": true, "color": Color(1.0, 0.55, 0.1) if enemy else Color(1.0, 1.0, 0.65)})


func clear() -> void:
	_effects.clear()
	bullets = []
	grenades = []
	threats = []
	ghosts = []
	throw_preview = {}
	deadlines = []
	prompts = []


## game_dt: vergangene Spielzeit (0 im Standbild), real_dt: echte Sekunden.
func advance(game_dt: float, real_dt: float) -> void:
	_time += real_dt
	for i in range(_effects.size() - 1, -1, -1):
		var e: Dictionary = _effects[i]
		e.age += real_dt if e.real else game_dt
		if e.age >= e.life:
			_effects.remove_at(i)
	queue_redraw()


func _draw() -> void:
	if camera == null:
		return
	for g in ghosts:
		_draw_ghost(g)
	_draw_throw()
	_draw_arc()
	for b in bullets:
		_draw_bullet(b)
	for e in _effects:
		match e.kind:
			"muzzle": _draw_muzzle(e)
			"spark": _draw_spark(e)
			"blood": _draw_blood(e)
			"pulse": _draw_pulse(e)
			"flash": _draw_flash(e)
			"trail": _draw_trail(e)
	for g in grenades:
		_draw_grenade(g)
	for t in threats:
		_draw_threat(t)
	for d in deadlines:
		_draw_deadline(d)
	for pr in prompts:
		_draw_prompt(pr)
	_draw_marker()


func _px(p: Vector3) -> Vector2:
	return camera.unproject_position(p)


## Pixel pro Meter an einer Weltposition.
func _scale_at(p: Vector3) -> float:
	return _px(p).distance_to(_px(p + Vector3.RIGHT))


func _draw_bullet(b: Dictionary) -> void:
	var head := _px(b.pos)
	var tail := _px(b.pos - b.dir * b.get("tail", BULLET_TAIL))
	var col: Color = Color(1.0, 0.55, 0.1) if b.enemy else Color(1.0, 1.0, 0.65)
	draw_line(tail, head, Color(col, 0.25), 9.0, true)
	draw_line(tail.lerp(head, 0.4), head, col, 3.5, true)
	draw_circle(head, 3.5, Color.WHITE)


func _draw_trail(e: Dictionary) -> void:
	var k: float = 1.0 - e.age / e.life
	var col: Color = e.color
	var a := _px(e.pos)
	var b := _px(e.dir)                       # "dir" trägt hier den Endpunkt
	draw_line(a, b, Color(col, 0.12 * k), 8.0, true)
	draw_line(a, b, Color(col, 0.5 * k), 2.0, true)


func _draw_muzzle(e: Dictionary) -> void:
	var t: float = e.age / e.life
	var c := _px(e.pos)
	var s := _scale_at(e.pos)
	var fwd := (_px(e.pos + e.dir) - c).normalized()
	var side := Vector2(-fwd.y, fwd.x)
	var col := Color(e.color, 1.0 - t * 0.6)
	var grow := 0.6 + 0.4 * t
	# Hauptflamme nach vorn, zwei kleine seitlich
	draw_colored_polygon([c - side * 0.13 * s, c + fwd * 1.0 * s * grow, c + side * 0.13 * s], col)
	for sgn in [-1.0, 1.0]:
		var d: Vector2 = (fwd * 0.55 + side * sgn * 0.75).normalized()
		draw_colored_polygon([c - fwd * 0.08 * s, c + d * 0.5 * s * grow, c + fwd * 0.12 * s], col)
	draw_circle(c, 0.2 * s, Color(1, 1, 1, 1.0 - t))


func _draw_spark(e: Dictionary) -> void:
	var t: float = e.age / e.life
	var c := _px(e.pos)
	var s := _scale_at(e.pos)
	var rng := RandomNumberGenerator.new()
	rng.seed = e.seed
	for i in 7:
		var d := Vector2.from_angle(rng.randf() * TAU)
		var length := rng.randf_range(0.25, 0.7) * s
		draw_line(c + d * length * t * 0.6, c + d * length * t, Color(e.color, 1.0 - t), 2.0, true)
	draw_circle(c, 0.12 * s * (1.0 - t), Color(1, 1, 1, 1.0 - t))


func _draw_blood(e: Dictionary) -> void:
	var t: float = e.age / e.life
	var c := _px(e.pos)
	var s := _scale_at(e.pos)
	var rng := RandomNumberGenerator.new()
	rng.seed = e.seed
	draw_circle(c, (0.15 + 0.35 * t) * s, Color(e.color, 0.7 * (1.0 - t)))
	for i in 9:
		var d := Vector2.from_angle(rng.randf() * TAU)
		var dist := rng.randf_range(0.2, 0.8) * s * t
		draw_circle(c + d * dist, rng.randf_range(0.03, 0.08) * s, Color(e.color, 1.0 - t))


func _draw_pulse(e: Dictionary) -> void:
	var t: float = e.age / e.life
	var radius := 0.4 + 5.0 * ease(t, 0.35)
	var pts := PackedVector2Array()
	for i in 49:
		var a := TAU * i / 48.0
		pts.append(_px(e.pos + Vector3(cos(a), 0.0, sin(a)) * radius + Vector3(0, 0.05, 0)))
	draw_polyline(pts, Color(e.color, 1.0 - t), 4.0 * (1.0 - t) + 1.0, true)


func _ground_circle(center: Vector3, radius: float, n := 40) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in n:
		var a := TAU * i / float(n)
		pts.append(_px(center + Vector3(cos(a), 0.0, sin(a)) * radius))
	return pts


func _draw_flash(e: Dictionary) -> void:
	var t: float = e.age / e.life
	var center := Vector3(e.pos.x, 0.05, e.pos.z)
	# Blitz über das ganze Bild, klingt schnell ab
	draw_rect(Rect2(Vector2.ZERO, size), Color(1, 1, 1, 0.55 * pow(1.0 - t, 3.0)))
	var r: float = e.radius * ease(t, 0.3)
	draw_colored_polygon(_ground_circle(center, r), Color(1, 1, 0.9, 0.5 * (1.0 - t)))
	var ring := _ground_circle(center, e.radius)
	ring.append(ring[0])
	draw_polyline(ring, Color(1, 1, 1, 0.9 * (1.0 - t)), 2.5, true)


func _draw_grenade(g: Dictionary) -> void:
	var shadow := _px(g.ground)
	var p := _px(g.pos)
	draw_circle(shadow, 5.0, Color(0, 0, 0, 0.45))
	draw_circle(p, 6.5, Color(0.1, 0.12, 0.1))
	draw_circle(p, 4.5, Color(0.75, 0.85, 0.7))
	draw_arc(p, 10.0 + 3.0 * sin(_time * 18.0), 0.0, TAU, 20, Color(1, 1, 1, 0.7), 1.5, true)


## Ring über einem Gegner, der einen Officer gesichtet hat: füllt sich bis zum Schuss.
## Geblendete Gegner bekommen stattdessen kreisende Sterne.
func _draw_threat(t: Dictionary) -> void:
	var p := _px(t.pos + Vector3(0, 2.7, 0))
	if t.blind:
		for i in 3:
			var a := _time * 4.0 + TAU * i / 3.0
			var c := p + Vector2(cos(a) * 16.0, sin(a) * 6.0)
			draw_line(c - Vector2(5, 0), c + Vector2(5, 0), Color.WHITE, 2.0, true)
			draw_line(c - Vector2(0, 5), c + Vector2(0, 5), Color.WHITE, 2.0, true)
		return
	var aim: float = clampf(t.aim, 0.0, 1.0)
	var col := Color(1.0, 0.75, 0.1).lerp(Color(1.0, 0.1, 0.05), aim)
	var radius := 15.0
	draw_circle(p, radius + 3.0, Color(0, 0, 0, 0.7))
	draw_arc(p, radius, 0.0, TAU, 32, Color(1, 1, 1, 0.22), 4.0, true)
	if aim > 0.01:
		draw_arc(p, radius, -PI * 0.5, -PI * 0.5 + TAU * aim, 32, col, 5.0, true)
	if aim > 0.85 and fmod(_time, 0.16) < 0.08:
		draw_circle(p, radius - 4.0, Color(1.0, 0.1, 0.05, 0.9))
	var font := ThemeDB.fallback_font
	draw_string(font, p + Vector2(-radius, 8.0), "!", HORIZONTAL_ALIGNMENT_CENTER, radius * 2.0, 22, Color.WHITE)


## Streuung als Kreisbogen um den Schützen in Zielentfernung: breit bei Bewegung,
## schrumpft beim Stillstehen zu einem Punkt.
func _draw_arc() -> void:
	if arc.is_empty():
		return
	var origin: Vector3 = arc.origin
	var spread: float = arc.spread
	var dist: float = maxf(arc.dist, 1.2)
	var white := Color(1, 1, 1, 0.95)
	if spread < deg_to_rad(0.7):
		var p := _px(origin + Vector3(sin(arc.yaw), 0.0, cos(arc.yaw)) * dist)
		draw_circle(p, 5.0, white)
		draw_arc(p, 9.0, 0.0, TAU, 24, Color(1, 1, 1, 0.5), 1.5, true)
		return
	var pts := PackedVector2Array()
	var n := 20
	for i in n + 1:
		var a: float = arc.yaw - spread + 2.0 * spread * i / n
		pts.append(_px(origin + Vector3(sin(a), 0.0, cos(a)) * dist))
	var o := _px(origin)
	# zarte Schenkel zeigen, dass der Bogen zum Schützen gehört
	draw_line(o.lerp(pts[0], 0.25), pts[0], Color(1, 1, 1, 0.16), 1.5, true)
	draw_line(o.lerp(pts[n], 0.25), pts[n], Color(1, 1, 1, 0.16), 1.5, true)
	draw_polyline(pts, white, 3.0, true)
	draw_circle(pts[0], 3.5, white)
	draw_circle(pts[n], 3.5, white)


## Hüpfender Pfeil über dem aktiven Officer.
func _draw_marker() -> void:
	if marker.is_empty():
		return
	var p := _px(marker.pos + Vector3(0, 3.0, 0)) + Vector2(0, sin(_time * 5.0) * 5.0)
	var tri := PackedVector2Array([p + Vector2(-13, -18), p + Vector2(13, -18), p])
	draw_colored_polygon(tri, marker.color)
	tri.append(tri[0])
	draw_polyline(tri, Color.WHITE, 2.5, true)


# --- Vorschauen und Hinweise --------------------------------------------------------

func _dashed(a: Vector3, b: Vector3, col: Color, width: float, dash := 0.35) -> void:
	var n := maxi(1, int(a.distance_to(b) / dash))
	for i in range(0, n, 2):
		draw_line(_px(a.lerp(b, float(i) / n)), _px(a.lerp(b, float(i + 1) / n)), col, width, true)


## Was die schon gespielten Officer noch tun werden: restlicher Weg, Endposition,
## und die Schusslinie ihrer noch kommenden Schüsse.
func _draw_ghost(g: Dictionary) -> void:
	var col: Color = g.color
	var pts: Array = g.points
	if pts.size() >= 2:
		var line := PackedVector2Array()
		for p in pts:
			line.append(_px(p))
		draw_polyline(line, Color(col, 0.55), 2.5, true)
	if pts.size() >= 1:
		var ring := _ground_circle(pts[pts.size() - 1], 0.45, 20)
		ring.append(ring[0])
		draw_polyline(ring, Color(col, 0.8), 2.0, true)
	for s in g.shots:
		var from: Vector3 = s.pos
		_dashed(from, from + s.dir * 7.0, Color(1.0, 0.95, 0.5, 0.75), 2.0)
		var c := _px(from)
		draw_line(c + Vector2(-6, -6), c + Vector2(6, 6), Color(1, 0.95, 0.5), 2.5, true)
		draw_line(c + Vector2(-6, 6), c + Vector2(6, -6), Color(1, 0.95, 0.5), 2.5, true)


## Blendgranate: Wurflinie, Landepunkt und Blendradius.
func _draw_throw() -> void:
	if throw_preview.is_empty():
		return
	var to: Vector3 = throw_preview.to
	var ground := Vector3(to.x, 0.05, to.z)
	# Wurfbogen bis zum ersten Aufkommen (danach springt die Granate weiter)
	var arc_pts: Array = throw_preview.arc
	for i in range(0, arc_pts.size() - 1, 2):
		draw_line(_px(arc_pts[i]), _px(arc_pts[i + 1]), Color(1, 1, 1, 0.6), 2.0, true)
	var ring := _ground_circle(ground, throw_preview.radius)
	ring.append(ring[0])
	draw_polyline(ring, Color(1, 1, 1, 0.35), 1.5, true)
	draw_circle(_px(ground), 4.0, Color(1, 1, 1, 0.8))


## Frist über einer bedrohten Geisel: roter Ring, der abläuft.
func _draw_deadline(d: Dictionary) -> void:
	var p := _px(d.pos + Vector3(0, 1.7, 0))
	var frac: float = d.frac
	var blink := frac < 0.3 and fmod(_time, 0.3) < 0.15
	draw_circle(p, 19.0, Color(0.5, 0.0, 0.0, 0.85) if not blink else Color(1.0, 0.15, 0.1, 0.95))
	draw_arc(p, 15.0, -PI * 0.5, -PI * 0.5 + TAU * frac, 32, Color(1.0, 0.9, 0.3), 5.0, true)
	draw_string(ThemeDB.fallback_font, p + Vector2(-19.0, 7.0), "%.1f" % d.seconds,
			HORIZONTAL_ALIGNMENT_CENTER, 38.0, 16, Color.WHITE)


## Tasten-Hinweis an einer Stelle in der Welt (z. B. "E" an einer Tür).
func _draw_prompt(pr: Dictionary) -> void:
	var p := _px(pr.pos)
	var r := Rect2(p - Vector2(15, 15), Vector2(30, 30))
	draw_rect(r, Color(0.05, 0.06, 0.08, 0.9))
	draw_rect(r, Color(1.0, 0.85, 0.2), false, 2.0)
	draw_string(ThemeDB.fallback_font, p + Vector2(-15.0, 8.0), pr.text,
			HORIZONTAL_ALIGNMENT_CENTER, 30.0, 22, Color(1.0, 0.85, 0.2))
