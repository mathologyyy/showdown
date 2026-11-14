class_name Hud
extends CanvasLayer
## HUD. Macht vor allem klar, in welchem Spielabschnitt man gerade ist:
##  - Leiste oben: Abschnitt (farbig) + Status aller Officer
##  - Titelkarte: große Einblendung mit Untertitel bei jedem Abschnittswechsel
##  - Kinobalken während nicht steuerbarer Abschnitte (Echtzeit-Vorlauf, Auswertung, Replay)
##  - bläulicher Schleier im Standbild (Freeze)
##  - VHS-artiger Rückspul-Effekt mit blinkendem ◀◀-Icon in der Bildmitte (Rewind)
##  - unten links Munition + Aim-Stabilität, oben rechts Zeit und Tempo
## Alles per Code aufgebaut.

const BAR_HEIGHT := 70.0
const TAKEOVER_BAR_W := 320.0
const TAKEOVER_BAR_H := 8.0

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
var _hint: Label
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
	_stats.offset_bottom = -52
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

	_hint = _label(root, 16, Color(0.75, 0.75, 0.75))
	_hint.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_hint.offset_top = -34
	_hint.offset_bottom = -10
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.text = "WASD bewegen · Maus zielen · Rechte Maustaste halten = Waffe anlegen · Linksklick schießen (nur beim Anlegen) · Leertaste = Spezialfähigkeit · C ducken · E Tür öffnen · F Position halten · 1/2 oder Mausrad Zeitlupe · ESC Pause"

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


## chips: pro Officer {text: String, color: Color, state: "active"|"done"|"wait"|"dead"}
func set_squad(chips: Array) -> void:
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
