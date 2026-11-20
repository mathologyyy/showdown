class_name Pad
extends RefCounted
## Hilfen für Controller in Menüs.
##
## Godot benennt Controller-Tasten nach ihrer LAGE wie beim Xbox-Pad: JOY_BUTTON_A = unten,
## JOY_BUTTON_B = rechts. Bei Nintendo-Controllern liegt das „A“ aber rechts, und dort ist
## es üblich, mit der rechten Taste zu bestätigen und mit der unteren zurückzugehen.
## Die Menüs fragen deshalb hier nach, welche Taste bestätigt und welche zurückgeht.

const NINTENDO_WORDS := ["nintendo", "switch", "pro controller", "joy-con", "joycon"]


## Ist der Controller ein Nintendo-Gerät (Switch Pro, Joy-Con)?
static func is_nintendo(device: int) -> bool:
	var n := Input.get_joy_name(device).to_lower()
	for word: String in NINTENDO_WORDS:
		if n.contains(word):
			return true
	return false


## Taste zum Bestätigen in Menüs: Nintendo rechts („A“), sonst unten („A“ bei Xbox, Kreuz).
static func confirm_button(device: int) -> int:
	return JOY_BUTTON_B if is_nintendo(device) else JOY_BUTTON_A


## Taste zum Zurückgehen in Menüs: jeweils die andere der beiden.
static func back_button(device: int) -> int:
	return JOY_BUTTON_A if is_nintendo(device) else JOY_BUTTON_B


## Menü-Eingabe vom Controller selbst behandeln (in _input aufrufen). Bestätigen drückt den
## fokussierten Button, Steuerkreuz und linker Stick wechseln den Fokus. Hat noch kein Button
## den Fokus, bekommt ihn `first`. Liefert true, wenn das Ereignis verbraucht wurde; dann
## hat es der Aufrufer per set_input_as_handled zu markieren (sonst löst Godots eingebautes
## ui_accept auf der unteren Taste bei Nintendo-Controllern zusätzlich aus).
## stick_state: Array mit einem bool, merkt sich, ob der Stick schon ausgelenkt war.
static func handle_menu(event: InputEvent, viewport: Viewport, first: Control, stick_state: Array) -> bool:
	var focus := viewport.gui_get_focus_owner()
	if event is InputEventJoypadButton:
		var jb := event as InputEventJoypadButton
		if jb.button_index != JOY_BUTTON_A and jb.button_index != JOY_BUTTON_B \
				and jb.button_index != JOY_BUTTON_DPAD_UP and jb.button_index != JOY_BUTTON_DPAD_DOWN:
			return false
		if not jb.pressed:
			return true
		if focus == null:
			first.grab_focus()
			return true
		match jb.button_index:
			JOY_BUTTON_DPAD_UP:
				_move_focus(focus, -1)
			JOY_BUTTON_DPAD_DOWN:
				_move_focus(focus, 1)
			_:
				if jb.button_index == confirm_button(jb.device) and focus is BaseButton:
					(focus as BaseButton).pressed.emit()
		return true
	if event is InputEventJoypadMotion and (event as InputEventJoypadMotion).axis == JOY_AXIS_LEFT_Y:
		var v := (event as InputEventJoypadMotion).axis_value
		var held: bool = stick_state[0]
		if absf(v) < 0.3:
			stick_state[0] = false
		elif absf(v) > 0.6 and not held:
			stick_state[0] = true
			if focus == null:
				first.grab_focus()
			else:
				_move_focus(focus, 1 if v > 0.0 else -1)
		return true
	return false


static func _move_focus(focus: Control, step: int) -> void:
	var next := focus.find_next_valid_focus() if step > 0 else focus.find_prev_valid_focus()
	if next:
		next.grab_focus()
