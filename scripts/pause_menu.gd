class_name PauseMenu
extends CanvasLayer
## Pausemenü: halbtransparente Abdunklung + zentriertes Panel mit „Fortsetzen“,
## „Mission neu starten“ und „Beenden“. Esc bzw. Start am Controller öffnet/schließt es
## (siehe _input); die Buttons lassen sich mit Steuerkreuz/Stick und A bedienen.
## Layer 10 und PROCESS_MODE_ALWAYS, damit es bei pausiertem Baum weiterläuft.
## Alles per Code aufgebaut (Stil wie hud.gd).

## „Zug beenden“ gewählt: der GameManager beendet den Zug des aktiven Officers
## (Position halten). Bewusst nur hier im Menü, damit es nicht versehentlich passiert.
signal end_turn_requested
## „Hauptmenü“ gewählt: der GameManager lädt die Szene neu und zeigt das Hauptmenü.
signal main_menu_requested

## false: Esc/Start öffnen das Menü nicht (solange das Hauptmenü zu sehen ist).
var enabled := true

var is_open := false

var _dim: ColorRect       # Vollbild-Abdunklung, fängt Mausklicks ab
var _resume: Button       # „Fortsetzen“: bekommt beim Öffnen den Fokus


func _ready() -> void:
	layer = 10
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false

	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	# halbtransparente dunkle Abdunklung über dem ganzen Spiel
	_dim = ColorRect.new()
	_dim.color = Color(0.0, 0.0, 0.0, 0.65)
	_dim.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(_dim)
	_dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	# zentriertes Panel
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _box(Color(0.04, 0.05, 0.07, 0.95), Color(1, 1, 1, 0.3), 24))
	root.add_child(panel)
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 14)
	panel.add_child(col)

	var title := _label(col, 48, Color.WHITE)
	title.text = "PAUSE"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.custom_minimum_size.x = 320

	_resume = _button(col, "Fortsetzen")
	_resume.pressed.connect(close)
	_button(col, "Zug beenden (Position halten)").pressed.connect(end_turn)
	_button(col, "Mission neu starten").pressed.connect(restart)
	_button(col, "Hauptmenü").pressed.connect(to_main_menu)
	_button(col, "Beenden").pressed.connect(quit_game)

	var hint := _label(col, 14, Color(0.7, 0.7, 0.7))
	hint.text = "ESC / START  Fortsetzen"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER


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


func _button(parent: Node, text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(280, 48)
	b.add_theme_font_size_override("font_size", 20)
	b.add_theme_color_override("font_color", Color.WHITE)
	b.add_theme_color_override("font_hover_color", Color(1.0, 0.85, 0.2))
	b.add_theme_color_override("font_focus_color", Color(1.0, 0.85, 0.2))
	b.add_theme_color_override("font_pressed_color", Color.WHITE)
	b.add_theme_stylebox_override("normal", _box(Color(0.10, 0.12, 0.16, 0.95), Color(1, 1, 1, 0.25), 8))
	b.add_theme_stylebox_override("hover", _box(Color(0.16, 0.19, 0.25, 0.95), Color(1, 1, 1, 0.5), 8))
	b.add_theme_stylebox_override("pressed", _box(Color(0.08, 0.10, 0.14, 0.95), Color(1.0, 0.85, 0.2), 8))
	b.add_theme_stylebox_override("focus", _box(Color(0.10, 0.12, 0.16, 0.95), Color(1.0, 0.85, 0.2), 8))
	parent.add_child(b)
	return b


## Menü auf: Spiel pausieren, „Fortsetzen“ fokussieren.
func open() -> void:
	is_open = true
	visible = true
	get_tree().paused = true
	_resume.grab_focus()


## Menü zu: Spiel weiterlaufen lassen.
func close() -> void:
	is_open = false
	visible = false
	get_tree().paused = false


func toggle() -> void:
	if is_open:
		close()
	else:
		open()


## Zug des aktiven Officers ohne Schuss beenden und weiterspielen.
func end_turn() -> void:
	close()
	end_turn_requested.emit()


## Mission neu starten: Szene neu laden (wie Taste N im Spiel).
func restart() -> void:
	get_tree().paused = false
	TimeControl.override_scale = -1.0
	get_tree().reload_current_scene()


func to_main_menu() -> void:
	close()
	main_menu_requested.emit()


func quit_game() -> void:
	get_tree().paused = false
	get_tree().quit()


func _input(event: InputEvent) -> void:
	if not enabled:
		return
	# Esc gehört dem Pausemenü – das Spiel beendet es nicht mehr
	if event is InputEventKey and event.physical_keycode == KEY_ESCAPE \
			and event.pressed and not event.echo:
		toggle()
		get_viewport().set_input_as_handled()
		return
	# Controller: Start öffnet/schließt das Menü, B schließt es
	if event is InputEventJoypadButton and event.pressed:
		if event.button_index == JOY_BUTTON_START or (is_open and event.button_index == JOY_BUTTON_B):
			toggle()
			get_viewport().set_input_as_handled()
			return
	if not is_open:
		return
	# Menü offen: Tastendrücke dürfen nicht ins Spiel durchfallen – außer der
	# UI-Navigation, damit die Buttons per Tastatur bedienbar bleiben.
	# Mausereignisse fängt die Abdunklung (_dim, MOUSE_FILTER_STOP) ab.
	if event is InputEventKey:
		if event.is_action("ui_accept") or event.is_action("ui_up") or event.is_action("ui_down") \
				or event.is_action("ui_left") or event.is_action("ui_right") \
				or event.is_action("ui_focus_next") or event.is_action("ui_focus_prev"):
			return
		get_viewport().set_input_as_handled()
