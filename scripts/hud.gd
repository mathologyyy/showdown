class_name Hud
extends CanvasLayer
## HUD. Macht vor allem klar, in welchem Spielabschnitt man gerade ist:
##  - Leiste oben: Abschnitt (farbig) + Status aller Officer
##  - Titelkarte: große Einblendung mit Untertitel bei jedem Abschnittswechsel
##  - Kinobalken während nicht steuerbarer Abschnitte (Echtzeit-Vorlauf, Auswertung, Replay)
##  - bläulicher Schleier im Standbild (Freeze)
##  - VHS-artiger Rückspul-Effekt mit blinkendem ◀◀-Icon in der Bildmitte (Rewind)
##  - unten links drei Officer-Icons (wen spiele ich gerade?), darüber Munition + Aim-Stabilität
##  - oben links klein die Tastenbelegung, oben rechts Zeit und Tempo
## Alles per Code aufgebaut.

const BAR_HEIGHT := 70.0
const TAKEOVER_BAR_W := 320.0
const TAKEOVER_BAR_H := 8.0
const ICON_MARGIN := 16.0         # Abstand der Officer-Icons zum unteren Bildrand
## Tastenbelegung (oben links): [Tastatur/Maus, Controller, Wirkung]
const KEY_HELP := [
	["TASTATUR", "CONTROLLER", ""],
	["W A S D", "Linker Stick", "Bewegen"],
	["Maus", "Rechter Stick", "Zielen"],
	["Rechte Maustaste", "LT / LB", "Waffe anlegen (halten)"],
	["Linksklick", "RT / RB", "Schießen (nur angelegt)"],
	["Leertaste", "A", "Spezialfähigkeit"],
	["C / Strg", "B", "Ducken"],
	["E", "X", "Tür öffnen"],
	["F / Enter", "Y", "Position halten"],
	["1 / 2 / Mausrad", "Steuerkreuz ↓ / ↑", "Zeitlupe"],
	["Esc", "Start", "Pause"],
]


## Stilisiertes Icon eines Officers (unten links). Die Silhouette verrät die Rolle:
##  "flash"  – normale Figur, hält eine Blendgranate hoch
##  "shield" – stämmige Figur hinter einem großen Schild
##  "roll"   – dünne, große Figur im Laufschritt (der schnelle, agile Officer)
## Zustand: "active" (wird gerade gespielt) hell mit farbigem Rahmen, "dead"
## ausgegraut und durchgestrichen, alles andere abgedunkelt.
class OfficerIcon extends Control:
	const W := 84.0
	const H := 118.0

	var number := 1
	var role := ""
	var caption := ""
	var color := Color.WHITE
	var state := ""

	func _init() -> void:
		custom_minimum_size = Vector2(W, H)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func set_info(p_role: String, p_caption: String, p_color: Color, p_state: String) -> void:
		if p_role == role and p_caption == caption and p_color == color and p_state == state:
			return
		role = p_role
		caption = p_caption
		color = p_color
		state = p_state
		queue_redraw()

	func _draw() -> void:
		var is_active := state == "active"
		var dead := state == "dead"
		# Karte
		var card := StyleBoxFlat.new()
		card.set_corner_radius_all(8)
		card.set_border_width_all(3 if is_active else 2)
		if is_active:
			card.bg_color = Color(color.darkened(0.55), 0.92)
			card.border_color = color.lightened(0.55)
		elif dead:
			card.bg_color = Color(0.22, 0.05, 0.05, 0.8)
			card.border_color = Color(0.5, 0.12, 0.1)
		else:
			card.bg_color = Color(0.06, 0.07, 0.09, 0.8)
			card.border_color = Color(color.darkened(0.3), 0.7)
		draw_style_box(card, Rect2(Vector2.ZERO, Vector2(W, H)))

		# Farben der Figur
		var body := color.lightened(0.15)
		var text_col := Color.WHITE
		if dead:
			body = Color(0.42, 0.42, 0.44)
			text_col = Color(0.8, 0.5, 0.5)
		elif not is_active:
			body = color.darkened(0.4)
			text_col = Color(0.65, 0.65, 0.65)
		var dark := body.darkened(0.5)
		var visor := Color(0.6, 0.85, 1.0) if is_active else Color(0.4, 0.5, 0.58)
		var cx := W * 0.5

		match role:
			"flash":
				_limb(Vector2(cx - 6, 74), Vector2(cx - 7, 96), 8.0, dark)
				_limb(Vector2(cx + 6, 74), Vector2(cx + 7, 96), 8.0, dark)
				_rrect(Rect2(cx - 12, 44, 24, 32), body, 5)
				_limb(Vector2(cx - 15, 48), Vector2(cx - 17, 68), 7.0, body)
				_limb(Vector2(cx + 15, 48), Vector2(cx + 25, 34), 7.0, body)   # Wurfarm oben
				draw_circle(Vector2(cx, 33), 10.0, dark)
				draw_rect(Rect2(cx - 6, 31, 12, 4), visor)
				# Blendgranate in der erhobenen Hand, darüber Blitz-Strahlen
				var can := Color(0.86, 0.88, 0.92) if not dead else Color(0.6, 0.6, 0.6)
				var spark := Color(1.0, 0.85, 0.2) if is_active else Color(0.7, 0.6, 0.2)
				draw_rect(Rect2(cx + 20.5, 19, 9, 13), can)
				draw_rect(Rect2(cx + 20.5, 24, 9, 3), spark)
				draw_rect(Rect2(cx + 22.5, 16, 5, 3), dark)
				var tip := Vector2(cx + 25, 13)
				for ang: float in [-150.0, -115.0, -90.0, -65.0, -30.0]:
					var d := Vector2.RIGHT.rotated(deg_to_rad(ang))
					draw_line(tip + d * 3.0, tip + d * 8.0, spark, 2.0, true)
			"shield":
				_limb(Vector2(cx - 12, 74), Vector2(cx - 12, 96), 9.0, dark)
				_limb(Vector2(cx, 74), Vector2(cx, 96), 9.0, dark)
				_rrect(Rect2(cx - 20, 44, 28, 32), body, 5)
				_limb(Vector2(cx - 22, 49), Vector2(cx - 23, 68), 8.0, body)
				draw_circle(Vector2(cx - 6, 33), 10.0, dark)
				draw_rect(Rect2(cx - 12, 31, 12, 4), visor)
				# großes Schild vor dem Körper, mit Sichtfenster wie im Spiel
				var plate := Color(0.2, 0.25, 0.34) if not dead else Color(0.25, 0.25, 0.27)
				_rrect(Rect2(cx - 6, 38, 34, 58), plate, 5, plate.lightened(0.45), 2)
				draw_rect(Rect2(cx + 2, 47, 18, 5), visor)
			"roll":
				# Tempo-Striche hinter der Figur
				var streak := Color(text_col, 0.55)
				draw_line(Vector2(cx - 33, 42), Vector2(cx - 17, 42), streak, 2.0)
				draw_line(Vector2(cx - 36, 56), Vector2(cx - 21, 56), streak, 2.0)
				draw_line(Vector2(cx - 31, 70), Vector2(cx - 19, 70), streak, 2.0)
				# hinteres Bein und hinterer Arm
				_limb(Vector2(cx - 2, 62), Vector2(cx - 10, 82), 6.0, dark)
				_limb(Vector2(cx - 10, 82), Vector2(cx - 20, 93), 6.0, dark)
				_limb(Vector2(cx + 2, 34), Vector2(cx - 9, 44), 5.0, body)
				_limb(Vector2(cx - 9, 44), Vector2(cx - 14, 53), 5.0, body)
				# schmaler, langer Rumpf, leicht nach vorn geneigt
				_limb(Vector2(cx + 2, 32), Vector2(cx - 2, 62), 10.0, body)
				# vorderes Bein und vorderer Arm
				_limb(Vector2(cx - 2, 62), Vector2(cx + 10, 80), 6.0, dark)
				_limb(Vector2(cx + 10, 80), Vector2(cx + 8, 98), 6.0, dark)
				_limb(Vector2(cx + 2, 34), Vector2(cx + 13, 45), 5.0, body)
				_limb(Vector2(cx + 13, 45), Vector2(cx + 20, 37), 5.0, body)
				draw_circle(Vector2(cx + 4, 19), 7.5, dark)
				draw_rect(Rect2(cx + 2, 17.5, 9, 3), visor)

		if dead:
			var red := Color(0.9, 0.15, 0.1, 0.85)
			draw_line(Vector2(14, 22), Vector2(W - 14, 98), red, 4.0, true)
			draw_line(Vector2(W - 14, 22), Vector2(14, 98), red, 4.0, true)

		var font := get_theme_default_font()
		draw_string(font, Vector2(8, 19), str(number), HORIZONTAL_ALIGNMENT_LEFT, -1.0, 16, text_col)
		draw_string(font, Vector2(0, H - 6), caption, HORIZONTAL_ALIGNMENT_CENTER, W, 12, text_col)

	## Gliedmaße: dicke Linie mit runden Enden.
	func _limb(a: Vector2, b: Vector2, width: float, col: Color) -> void:
		draw_line(a, b, col, width, true)
		draw_circle(a, width * 0.5, col)
		draw_circle(b, width * 0.5, col)

	## Rechteck mit runden Ecken, optional mit Rand.
	func _rrect(rect: Rect2, col: Color, radius: int, border := Color.TRANSPARENT, border_width := 0) -> void:
		var sb := StyleBoxFlat.new()
		sb.bg_color = col
		sb.set_corner_radius_all(radius)
		sb.border_color = border
		sb.set_border_width_all(border_width)
		draw_style_box(sb, rect)

## Zuletzt gezeigte Texte (praktisch für Tests und Debugging).
var card_title := ""
var card_subtitle := ""
var panel_text := ""

var _freeze: ColorRect
var _bar_top: ColorRect
var _bar_bottom: ColorRect
var _phase: Label
var _chips: Array = []            # [{panel: PanelContainer, label: Label}]
var _title: Label
var _big: Label
var _big_alpha := 0.0
var _big_time := 0.0
var _sub: Label
var _ammo: Label
var _special: Label
var _stab: ProgressBar
var _stats: Control
var _clock: Label
var _hint: PanelContainer         # Tastenbelegung, klein oben links
var _icons: Array = []            # OfficerIcon je Officer, unten links
var _panel: PanelContainer
var _panel_label: Label

var _card_time := 0.0             # verbleibende Sekunden; < 0 = bleibt stehen
var _card_alpha := 0.0
var _bars_on := false
var _freeze_on := false

var _rewind_rect: ColorRect       # Effekt-Ebene (erstes Kind von root, unter allem anderen HUD)
var _rewind_mat: ShaderMaterial
var _rewind_icon: Control         # blinkendes ◀◀-Icon + "REW" (letztes Kind von root)
var _rewind_on := false
var _rewind_k := 0.0              # Ein-/Ausblend-Faktor des Effekts (0..1)
var _rewind_time := 0.0           # echte Sekunden seit Start, fürs Blinken
## öffentlich für Tests: true, solange der Rückspul-Effekt angezeigt wird
var rewind_shown := false

var _takeover: VBoxContainer       # Übernahme-Timer (Label + Fortschrittsbalken), oben mittig
var _takeover_label: Label
var _takeover_bar_bg: ColorRect
var _takeover_fill: ColorRect
## öffentlich für Tests: zuletzt gesetzte Restzeit in s (< 0 = Timer ausgeblendet)
var takeover_left := -1.0


func _ready() -> void:
	layer = 3
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	# Effekt-Ebene fürs Zurückspulen: ALLERERSTES Kind von root, dadurch über dem
	# Spielbild, aber unter allen HUD-Elementen (bleiben scharf)
	_rewind_mat = ShaderMaterial.new()
	_rewind_mat.shader = load("res://shaders/rewind.gdshader")
	_rewind_rect = ColorRect.new()
	_rewind_rect.material = _rewind_mat
	_rewind_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rewind_rect.visible = false
	root.add_child(_rewind_rect)
	_rewind_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	_freeze = ColorRect.new()
	_freeze.color = Color(0.25, 0.5, 1.0, 0.0)
	_freeze.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_freeze)
	_freeze.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	_bar_top = _bar(root, Control.PRESET_TOP_WIDE)
	_bar_bottom = _bar(root, Control.PRESET_BOTTOM_WIDE)

	# --- Leiste oben: Abschnitt + Squad-Status ---
	var top := PanelContainer.new()
	top.add_theme_stylebox_override("panel", _box(Color(0.05, 0.06, 0.08, 0.85), Color(1, 1, 1, 0.15)))
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(top)
	top.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	top.grow_horizontal = Control.GROW_DIRECTION_BOTH
	top.offset_top = 10
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	top.add_child(row)
	_phase = _label(row, 22, Color.WHITE)
	_phase.custom_minimum_size.x = 330
	for i in 4:
		var chip := PanelContainer.new()
		row.add_child(chip)
		var l := _label(chip, 16, Color.WHITE)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.custom_minimum_size.x = 150
		_chips.append({"panel": chip, "label": l})

	# --- Übernahme-Timer: Vorlauf-Countdown in echten Sekunden ---
	# Oben mittig zwischen Abschnittsleiste (bis ca. y=58) und Titelkarte (ab y=120),
	# kollidiert weder mit _title/_sub noch mit dem zentrierten _big
	_takeover = VBoxContainer.new()
	_takeover.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_takeover)
	_takeover.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_takeover.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_takeover.offset_top = 62
	_takeover.offset_left = -TAKEOVER_BAR_W * 0.5
	_takeover.offset_right = TAKEOVER_BAR_W * 0.5
	_takeover.offset_bottom = 108
	_takeover.add_theme_constant_override("separation", 4)
	_takeover_label = _label(_takeover, 26, Color.WHITE)
	_takeover_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_takeover_bar_bg = ColorRect.new()
	_takeover_bar_bg.color = Color(0.05, 0.06, 0.08, 0.8)
	_takeover_bar_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_takeover_bar_bg.custom_minimum_size = Vector2(TAKEOVER_BAR_W, TAKEOVER_BAR_H)
	_takeover.add_child(_takeover_bar_bg)
	_takeover_fill = ColorRect.new()
	_takeover_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_takeover_bar_bg.add_child(_takeover_fill)
	_takeover_fill.anchor_right = 0.0
	_takeover_fill.offset_left = 0.0
	_takeover_fill.offset_top = 0.0
	_takeover_fill.offset_bottom = TAKEOVER_BAR_H
	_takeover_fill.offset_right = 0.0
	_takeover.visible = false

	# --- Titelkarte ---
	_title = _label(root, 104, Color.WHITE)
	_title.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_title.offset_top = 120
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.add_theme_constant_override("outline_size", 18)
	_sub = _label(root, 30, Color.WHITE)
	_sub.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_sub.offset_top = 262
	_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_sub.add_theme_constant_override("outline_size", 10)
	_title.modulate.a = 0.0
	_sub.modulate.a = 0.0

	# --- riesige Einblendung in der Bildmitte (Countdown, GO GO GO) ---
	_big = _label(root, 260, Color.WHITE)
	_big.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_big.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_big.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_big.add_theme_constant_override("outline_size", 36)
	_big.modulate.a = 0.0

	# --- unten links: Munition + Aim-Stabilität ---
	_stats = VBoxContainer.new()
	root.add_child(_stats)
	_stats.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	_stats.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_stats.offset_left = 24
	_stats.offset_bottom = -(ICON_MARGIN + OfficerIcon.H + 10.0)
	_ammo = _label(_stats, 22, Color.WHITE)
	_special = _label(_stats, 20, Color(1.0, 0.85, 0.2))
	var cap := _label(_stats, 16, Color(0.8, 0.8, 0.8))
	cap.text = "AIM-STABILITÄT"
	_stab = ProgressBar.new()
	_stab.custom_minimum_size = Vector2(240, 18)
	_stab.max_value = 1.0
	_stab.step = 0.001
	_stab.show_percentage = false
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(0.3, 1.0, 0.5)
	_stab.add_theme_stylebox_override("fill", fill)
	_stats.add_child(_stab)

	# --- oben rechts: Zeit + Tempo ---
	_clock = _label(root, 20, Color.WHITE)
	_clock.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_clock.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_clock.offset_right = -20
	_clock.offset_top = 14
	_clock.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT

	# --- unten links: ein Icon pro Officer, der gespielte ist hervorgehoben ---
	var icon_row := HBoxContainer.new()
	icon_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon_row.add_theme_constant_override("separation", 8)
	root.add_child(icon_row)
	icon_row.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	icon_row.grow_vertical = Control.GROW_DIRECTION_BEGIN
	icon_row.offset_left = 24
	icon_row.offset_bottom = -ICON_MARGIN
	for i in 3:
		var icon := OfficerIcon.new()
		icon.number = i + 1
		icon_row.add_child(icon)
		_icons.append(icon)

	# --- oben links: Tastenbelegung als kleine Tabelle ---
	_hint = PanelContainer.new()
	_hint.add_theme_stylebox_override("panel", _box(Color(0.05, 0.06, 0.08, 0.6), Color(1, 1, 1, 0.12), 8))
	_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_hint)
	_hint.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	_hint.offset_left = 12
	_hint.offset_top = 66                # unter der Abschnittsleiste, damit sich nichts überlappt
	var keys := GridContainer.new()
	keys.columns = 3
	keys.mouse_filter = Control.MOUSE_FILTER_IGNORE
	keys.add_theme_constant_override("h_separation", 12)
	keys.add_theme_constant_override("v_separation", 0)
	_hint.add_child(keys)
	for r in KEY_HELP.size():
		for col in 3:
			var tint := Color(0.82, 0.82, 0.82)
			if r == 0:
				tint = Color(0.55, 0.6, 0.66)         # Kopfzeile
			elif col < 2:
				tint = Color(1.0, 0.85, 0.2)
			var kl := _label(keys, 12, tint)
			kl.add_theme_constant_override("outline_size", 3)
			kl.text = KEY_HELP[r][col]

	# --- Tafel in der Mitte (Fehlschlag, Ergebnis) ---
	_panel = PanelContainer.new()
	_panel.add_theme_stylebox_override("panel", _box(Color(0.04, 0.05, 0.07, 0.92), Color(1, 1, 1, 0.3), 28))
	root.add_child(_panel)
	_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	_panel_label = _label(_panel, 28, Color.WHITE)
	_panel_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_panel.visible = false

	# --- Rückspul-Icon: zwei nach links zeigende Dreiecke (◀◀) + "REW" darunter ---
	# LETZTES Kind von root, damit es über allem HUD liegt
	_rewind_icon = Control.new()
	_rewind_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_rewind_icon)
	var tri_w := 170.0
	var tri_h := 220.0
	var gap := 24.0
	for i in 2:
		var tri := Polygon2D.new()
		tri.color = Color(1, 1, 1, 0.9)
		# Spitze links; beide Dreiecke zusammen um den Ursprung des Controls zentriert
		var cx := (i * 2 - 1) * (tri_w * 0.5 + gap * 0.5)
		tri.polygon = PackedVector2Array([
			Vector2(cx - tri_w * 0.5, 0.0),
			Vector2(cx + tri_w * 0.5, -tri_h * 0.5),
			Vector2(cx + tri_w * 0.5, tri_h * 0.5),
		])
		_rewind_icon.add_child(tri)
	var rew := _label(_rewind_icon, 54, Color.WHITE)
	rew.text = "REW"
	rew.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rew.custom_minimum_size.x = 200
	rew.position = Vector2(-100, 150)   # ca. 150 px unter der Mitte, zentriert
	_rewind_icon.visible = false


func _bar(parent: Control, preset: int) -> ColorRect:
	var r := ColorRect.new()
	r.color = Color(0.07, 0.10, 0.15)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(r)
	r.set_anchors_and_offsets_preset(preset)
	return r


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
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(l)
	return l


## Abschnitts-Anzeige in der Leiste oben.
func set_phase(text: String, color: Color) -> void:
	_phase.text = text
	_phase.add_theme_color_override("font_color", color)


## chips: pro Officer {text: String, color: Color, state: "active"|"done"|"wait"|"dead",
##                      role: String, name: String (Kurzname der Rolle fürs Icon)}
func set_squad(chips: Array) -> void:
	for i in _icons.size():
		var icon: OfficerIcon = _icons[i]
		icon.visible = i < chips.size()
		if icon.visible:
			icon.set_info(chips[i].get("role", ""), chips[i].get("name", ""), chips[i].color, chips[i].state)
	for i in _chips.size():
		var c: Dictionary = _chips[i]
		c.panel.visible = i < chips.size()
		if i >= chips.size():
			continue
		var info: Dictionary = chips[i]
		c.label.text = info.text
		var col: Color = info.color
		match info.state:
			"active":
				c.panel.add_theme_stylebox_override("panel", _box(col, Color.WHITE, 6))
				c.label.add_theme_color_override("font_color", Color.WHITE)
			"done":
				c.panel.add_theme_stylebox_override("panel", _box(Color(0.1, 0.1, 0.12), col, 6))
				c.label.add_theme_color_override("font_color", col.lightened(0.4))
			"dead":
				c.panel.add_theme_stylebox_override("panel", _box(Color(0.3, 0.05, 0.05), Color(0.5, 0.1, 0.1), 6))
				c.label.add_theme_color_override("font_color", Color(0.8, 0.5, 0.5))
			_:
				c.panel.add_theme_stylebox_override("panel", _box(Color(0.1, 0.1, 0.12), Color(0.3, 0.3, 0.3), 6))
				c.label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))


## Große Titelkarte. seconds: Anzeigedauer in echten Sekunden, <= 0 bleibt bis hide_card().
func show_card(title: String, subtitle: String, color: Color, seconds: float) -> void:
	card_title = title
	card_subtitle = subtitle
	_title.text = title
	_sub.text = subtitle
	_title.add_theme_color_override("font_color", color)
	_card_time = seconds if seconds > 0.0 else -1.0
	_card_alpha = 1.0
	_title.pivot_offset = _title.size * 0.5
	_title.scale = Vector2(1.25, 1.25)   # kleiner "Punch" beim Einblenden


## Riesiger Text mitten im Bild, springt groß herein und schrumpft auf Normalgröße.
## seconds: danach blendet er aus.
func show_big(text: String, color: Color, seconds: float) -> void:
	_big.text = text
	_big.add_theme_color_override("font_color", color)
	_big_time = seconds
	_big_alpha = 1.0
	_big.pivot_offset = _big.size * 0.5
	_big.scale = Vector2(1.7, 1.7)
	_big.rotation = -0.06


func hide_card() -> void:
	_card_time = 0.0


## special: Zeile zur Spezialfähigkeit des aktiven Officers.
func set_stats(ammo: int, max_ammo: int, stability: float, shown: bool, special := "") -> void:
	_stats.visible = shown
	_ammo.text = "MUNITION  %d / %d" % [ammo, max_ammo]
	_special.text = special
	_stab.value = stability


func set_clock(text: String) -> void:
	_clock.text = text


func set_letterbox(on: bool) -> void:
	_bars_on = on


func set_freeze(on: bool) -> void:
	_freeze_on = on


## Rückspul-Effekt (VHS-Verzerrung + blinkendes ◀◀-Icon) an/aus.
func set_rewind(on: bool) -> void:
	_rewind_on = on
	rewind_shown = on


## Übernahme-Timer im Vorlauf: seconds_left = echte Sekunden bis zur Kontrolle,
## total = Gesamtdauer des Vorlaufs, color = Füllfarbe des Balkens.
## seconds_left < 0 blendet das Element aus.
func set_takeover_timer(seconds_left: float, total: float, color: Color) -> void:
	takeover_left = seconds_left
	if seconds_left < 0.0:
		_takeover.visible = false
		return
	_takeover.visible = true
	_takeover_label.text = "ÜBERNAHME IN %s s" % ("%.1f" % seconds_left).replace(".", ",")
	var frac := clampf(1.0 - seconds_left / maxf(total, 0.001), 0.0, 1.0)
	_takeover_fill.color = color
	_takeover_fill.offset_right = TAKEOVER_BAR_W * frac


func set_hint_visible(on: bool) -> void:
	_hint.visible = on


## Tafel in der Bildmitte (Fehlschlag, Ergebnis). "" blendet aus.
func set_panel_text(text: String) -> void:
	panel_text = text
	_panel_label.text = text
	_panel.visible = text != ""


## real_dt: echte Sekunden (unabhängig von der Zeitlupe).
func tick(real_dt: float) -> void:
	var w := 1.0 - exp(-10.0 * real_dt)
	var h := lerpf(_bar_top.size.y, BAR_HEIGHT if _bars_on else 0.0, w)
	_bar_top.offset_bottom = h
	_bar_bottom.offset_top = -h
	_freeze.color.a = lerpf(_freeze.color.a, 0.16 if _freeze_on else 0.0, w)

	if _card_time > 0.0:
		_card_time -= real_dt
		if _card_time <= 0.0:
			_card_time = 0.0
	if _card_time == 0.0:
		_card_alpha = maxf(0.0, _card_alpha - real_dt * 3.0)
	_title.modulate.a = _card_alpha
	_sub.modulate.a = _card_alpha
	_title.scale = _title.scale.lerp(Vector2.ONE, w)

	_big_time -= real_dt
	if _big_time <= 0.0:
		_big_alpha = maxf(0.0, _big_alpha - real_dt * 5.0)
	_big.modulate.a = _big_alpha
	var bw := 1.0 - exp(-14.0 * real_dt)
	_big.scale = _big.scale.lerp(Vector2.ONE, bw)
	_big.rotation = lerpf(_big.rotation, 0.0, bw)

	# --- Rückspul-Effekt: VHS-Shader weich ein-/ausblenden, Icon zentriert blinken ---
	_rewind_time += real_dt
	_rewind_k = move_toward(_rewind_k, 1.0 if _rewind_on else 0.0, 8.0 * real_dt)
	_rewind_rect.visible = _rewind_k > 0.01
	_rewind_mat.set_shader_parameter("strength", _rewind_k)
	_rewind_icon.visible = _rewind_on
	if _rewind_on:
		_rewind_icon.position = get_viewport().get_visible_rect().size * 0.5
		_rewind_icon.modulate.a = lerpf(0.35, 1.0, 0.5 + 0.5 * sin(_rewind_time * TAU * 3.0))
