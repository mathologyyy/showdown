extends CanvasLayer
## Hauptmenü und Einweisung. Liegt als eigene Ebene über dem (noch stehenden) Spiel.
##  - Menü: „Spiel starten“, „So wird gespielt“, „Beenden“
##  - Einweisung: drei Tafeln mit je einer gezeichneten Grafik, die das Runden-Prinzip
##    erklären. Jeder Tastendruck/Klick blättert weiter, Esc bzw. Start überspringt alles.
##    Sie erscheint automatisch vor der ersten Mission und danach nur noch auf Wunsch.
## Der GameManager lädt dieses Skript per preload und wartet auf start_requested.
## Alles per Code aufgebaut (Stil wie pause_menu.gd).

signal start_requested

const OFFICER_COLORS := [
	Color(0.15, 0.40, 1.00), Color(0.10, 0.75, 0.55), Color(0.55, 0.35, 1.00),
]
const ENEMY_COLOR := Color(0.75, 0.08, 0.06)
const GOLD := Color(1.0, 0.85, 0.2)
const PAGE_W := 760.0

const PAGES := [
	{"title": "1 · EIN ZUG PRO OFFICER",
		"text": "Du steuerst deine drei Officer nacheinander. Ein Zug endet mit deinem Schuss, dem Wurf der Blendgranate oder dem Heben des Schilds. Ob der Schuss trifft, erfährst du noch nicht."},
	{"title": "2 · ZURÜCKSPULEN",
		"text": "Nach jedem Zug wird die Zeit zurückgespult. Der nächste Officer startet im selben Moment wie der vorige – dessen Zug läuft als Aufzeichnung mit, und seine Kugeln fliegen jetzt wirklich. So greifen alle drei gleichzeitig an."},
	{"title": "3 · AUSWERTUNG UND REPLAY",
		"text": "Zum Schluss laufen alle Züge gemeinsam ab. Sind alle Gegner ausgeschaltet und die Geiseln unverletzt, siehst du den ganzen Einsatz in Echtzeit – und bekommst Sterne für Tempo, wenige Schüsse und wenige Durchläufe."},
]

## Einweisung wurde schon gezeigt (statisch: bleibt über das Neuladen der Szene erhalten).
static var briefing_seen := false

var _menu_box: VBoxContainer
var _start: Button
var _brief: PanelContainer
var _b_title: Label
var _b_text: Label
var _b_dots: Label
var _diagram: Diagram
var _page := 0
var _brief_then_start := false     # nach der Einweisung direkt ins Spiel (sonst zurück ins Menü)


## Grafik einer Einweisungs-Tafel (page 0..2), komplett gezeichnet.
class Diagram extends Control:
	const W := 760.0
	const H := 250.0
	const COLORS := [
		Color(0.15, 0.40, 1.00), Color(0.10, 0.75, 0.55), Color(0.55, 0.35, 1.00),
	]
	const RED := Color(0.85, 0.15, 0.1)
	const GOLD := Color(1.0, 0.85, 0.2)
	const GRAY := Color(0.6, 0.63, 0.68)

	var page := 0

	func _init() -> void:
		custom_minimum_size = Vector2(W, H)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func set_page(p: int) -> void:
		page = p
		queue_redraw()

	func _draw() -> void:
		draw_rect(Rect2(0, 0, W, H), Color(0.08, 0.09, 0.12, 0.9))
		match page:
			0:
				_draw_turns()
			1:
				_draw_rewind()
			_:
				_draw_resolve()

	# Tafel 1: drei Officer, jeder mit eigenem Weg und Schuss auf den Gegner
	func _draw_turns() -> void:
		var enemy := Vector2(640, 125)
		var starts: Array[Vector2] = [Vector2(90, 55), Vector2(90, 125), Vector2(90, 195)]
		var ends: Array[Vector2] = [Vector2(400, 60), Vector2(330, 125), Vector2(420, 200)]
		for i in 3:
			var col: Color = COLORS[i]
			var a: Vector2 = starts[i]
			var b: Vector2 = ends[i]
			draw_line(a, b, Color(col, 0.9), 4.0, true)
			_dashed(b, enemy, GOLD, 2.0)
			_figure(b, col, "")
			_figure(a, Color(col, 0.35), str(i + 1))
			_text(Vector2(a.x - 70, a.y + 38), 140, "Zug %d" % (i + 1), 14, GRAY)
		_figure(enemy, RED, "!")
		_text(Vector2(enemy.x - 70, enemy.y + 38), 140, "Gegner", 14, GRAY)

	# Tafel 2: Zeitleiste – jeder Zug beginnt wieder am selben Startmoment
	func _draw_rewind() -> void:
		var x0 := 150.0
		var lengths: Array[float] = [260.0, 380.0, 480.0]
		draw_line(Vector2(x0, 20), Vector2(x0, 215), Color.WHITE, 2.0)
		_text(Vector2(x0 - 70, 240), 140, "Start", 14, GRAY)
		for i in 3:
			var y := 55.0 + 62.0 * i
			var col: Color = COLORS[i]
			var x1: float = x0 + lengths[i]
			_figure(Vector2(x0 - 50, y), col, str(i + 1))
			draw_rect(Rect2(x0, y - 9, x1 - x0, 18), Color(col, 0.85))
			draw_circle(Vector2(x1, y), 9.0, GOLD)                 # der Schuss beendet den Zug
			_text(Vector2(x1 + 16, y + 5), 120, "Schuss", 14, GOLD, HORIZONTAL_ALIGNMENT_LEFT)
			if i < 2:
				# Rückspul-Pfeil zurück zum Start
				var ya := y + 31.0
				draw_line(Vector2(x1, ya), Vector2(x0 + 14, ya), GRAY, 2.0, true)
				_triangle(Vector2(x0 + 4, ya), Vector2(-1, 0), 9.0, GRAY)
				_triangle(Vector2(x0 + 18, ya), Vector2(-1, 0), 9.0, GRAY)

	# Tafel 3: alle Züge laufen zusammen ab, danach die Wertung
	func _draw_resolve() -> void:
		var x0 := 150.0
		var lengths: Array[float] = [260.0, 380.0, 480.0]
		_triangle(Vector2(x0 - 62, 110), Vector2(1, 0), 26.0, Color.WHITE)
		for i in 3:
			var y := 70.0 + 40.0 * i
			var col: Color = COLORS[i]
			draw_rect(Rect2(x0, y - 9, lengths[i], 18), Color(col, 0.85))
			draw_circle(Vector2(x0 + lengths[i], y), 9.0, GOLD)
		# Abspielmarke
		draw_line(Vector2(x0 + 300, 40), Vector2(x0 + 300, 180), Color.WHITE, 3.0)
		for i in 3:
			_star(Vector2(300.0 + 80.0 * i, 215), 20.0, GOLD)

	func _figure(at: Vector2, col: Color, label: String) -> void:
		draw_circle(at, 20.0, col)
		draw_arc(at, 20.0, 0.0, TAU, 32, Color(1, 1, 1, 0.8), 2.0, true)
		if label != "":
			_text(Vector2(at.x - 20, at.y + 8), 40, label, 22, Color.WHITE)

	func _text(pos: Vector2, width: float, text: String, font_size: int, col: Color,
			align := HORIZONTAL_ALIGNMENT_CENTER) -> void:
		draw_string(get_theme_default_font(), pos, text, align, width, font_size, col)

	func _dashed(a: Vector2, b: Vector2, col: Color, width: float) -> void:
		var n := int(a.distance_to(b) / 14.0)
		for i in n:
			if i % 2 == 0:
				draw_line(a.lerp(b, float(i) / n), a.lerp(b, float(i + 1) / n), col, width, true)

	## Gefülltes Dreieck, Spitze in Richtung dir.
	func _triangle(center: Vector2, dir: Vector2, s: float, col: Color) -> void:
		var side := Vector2(-dir.y, dir.x)
		draw_colored_polygon(PackedVector2Array([
			center + dir * s, center - dir * s * 0.6 + side * s * 0.8,
			center - dir * s * 0.6 - side * s * 0.8]), col)

	func _star(center: Vector2, radius: float, col: Color) -> void:
		var pts := PackedVector2Array()
		for i in 10:
			var r := radius if i % 2 == 0 else radius * 0.45
			pts.append(center + Vector2.UP.rotated(TAU * i / 10.0) * r)
		draw_colored_polygon(pts, col)


func _ready() -> void:
	layer = 8                                  # über dem HUD (3), unter dem Pausemenü (10)
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	# Abdunklung über dem Spielbild, fängt Mausklicks ab
	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.0, 0.0, 0.6)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(dim)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	# --- Menü ---
	_menu_box = VBoxContainer.new()
	_menu_box.add_theme_constant_override("separation", 14)
	root.add_child(_menu_box)
	_menu_box.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_menu_box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_menu_box.grow_vertical = Control.GROW_DIRECTION_BOTH
	var title := _label(_menu_box, 120, Color.WHITE)
	title.text = "SHOWDOWN"
	title.add_theme_constant_override("outline_size", 20)
	var sub := _label(_menu_box, 26, GOLD)
	sub.text = "GO  GO  GO   ·   Taktik in Zeitlupe"
	var gap := Control.new()
	gap.custom_minimum_size.y = 26
	_menu_box.add_child(gap)
	_start = _button(_menu_box, "Spiel starten")
	_start.pressed.connect(_on_start)
	_button(_menu_box, "So wird gespielt").pressed.connect(_open_briefing.bind(false))
	_button(_menu_box, "Beenden").pressed.connect(_on_quit)

	# --- Einweisung ---
	_brief = PanelContainer.new()
	_brief.add_theme_stylebox_override("panel", _box(Color(0.04, 0.05, 0.07, 0.96), Color(1, 1, 1, 0.3), 26))
	root.add_child(_brief)
	_brief.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_brief.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_brief.grow_vertical = Control.GROW_DIRECTION_BOTH
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 16)
	_brief.add_child(col)
	_b_title = _label(col, 40, GOLD)
	_diagram = Diagram.new()
	col.add_child(_diagram)
	_b_text = _label(col, 22, Color.WHITE)
	_b_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_b_text.custom_minimum_size = Vector2(PAGE_W, 96)
	_b_dots = _label(col, 26, Color.WHITE)
	var hint := _label(col, 15, Color(0.7, 0.7, 0.7))
	hint.text = "Weiter: beliebige Taste oder Klick      Überspringen: Esc / Start"
	_brief.visible = false

	_start.grab_focus()


func _on_start() -> void:
	if briefing_seen:
		start_requested.emit()
	else:
		_open_briefing(true)


func _on_quit() -> void:
	get_tree().quit()


func _open_briefing(then_start: bool) -> void:
	_brief_then_start = then_start
	_page = 0
	_menu_box.visible = false
	_brief.visible = true
	_show_page()


func _show_page() -> void:
	var info: Dictionary = PAGES[_page]
	_b_title.text = info.title
	_b_text.text = info.text
	_diagram.set_page(_page)
	var dots := ""
	for i in PAGES.size():
		dots += "●  " if i == _page else "○  "
	_b_dots.text = dots.strip_edges()


func _next_page() -> void:
	_page += 1
	if _page >= PAGES.size():
		_close_briefing()
	else:
		_show_page()


func _close_briefing() -> void:
	briefing_seen = true
	_brief.visible = false
	if _brief_then_start:
		start_requested.emit()
	else:
		_menu_box.visible = true
		_start.grab_focus()


## Einweisung offen: jeder Tastendruck, Controller-Knopf oder Klick blättert weiter,
## Esc bzw. Start überspringt den Rest. (Berührungen kommen als Mausklick an.)
func _input(event: InputEvent) -> void:
	if not _brief.visible:
		return
	var is_key: bool = event is InputEventKey and event.pressed and not event.echo
	var is_pad: bool = event is InputEventJoypadButton and event.pressed
	var is_click: bool = event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT
	if not (is_key or is_pad or is_click):
		return
	get_viewport().set_input_as_handled()
	if (is_key and event.physical_keycode == KEY_ESCAPE) or (is_pad and event.button_index == JOY_BUTTON_START):
		_close_briefing()
	else:
		_next_page()


func _box(bg: Color, border: Color, margin := 10) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(6)
	sb.set_content_margin_all(margin)
	return sb


func _label(parent: Node, size: int, color: Color) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 6)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(l)
	return l


func _button(parent: Node, text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(320, 54)
	b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	b.add_theme_font_size_override("font_size", 22)
	b.add_theme_color_override("font_color", Color.WHITE)
	b.add_theme_color_override("font_hover_color", GOLD)
	b.add_theme_color_override("font_focus_color", GOLD)
	b.add_theme_color_override("font_pressed_color", Color.WHITE)
	b.add_theme_stylebox_override("normal", _box(Color(0.10, 0.12, 0.16, 0.95), Color(1, 1, 1, 0.25), 8))
	b.add_theme_stylebox_override("hover", _box(Color(0.16, 0.19, 0.25, 0.95), Color(1, 1, 1, 0.5), 8))
	b.add_theme_stylebox_override("pressed", _box(Color(0.08, 0.10, 0.14, 0.95), GOLD, 8))
	b.add_theme_stylebox_override("focus", _box(Color(0.10, 0.12, 0.16, 0.95), GOLD, 8))
	parent.add_child(b)
	return b
