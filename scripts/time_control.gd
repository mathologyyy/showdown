extends Node
## Zentrale Zeitsteuerung (Autoload "TimeControl").
##
## Die Simulation rechnet in festen Ticks von 1/480 Spielsekunde (DT), immer genau
## ein Tick pro _physics_process. Die Zeitlupe entsteht dadurch, dass hier die
## Physik-Tickrate der Engine verstellt wird: bei 10 % laufen nur 48 Ticks pro
## echter Sekunde, im Abschluss-Replay (Faktor 1.0) alle 480.
## Vorteil gegenüber Engine.time_scale (das nur das Delta skaliert): Jeder Tick ist
## exakt gleich lang, Aufzeichnungen und Gegner-KI bleiben deterministisch, egal
## wie schnell die Welt gerade läuft. Die Physik-Interpolation (project.godot)
## glättet die Darstellung zwischen den wenigen Ticks.
## Zeitlupe nur, solange der aktive Officer die Waffe angelegt hat (GameManager
## setzt dafür pro Frame "aiming"). Per slowdown_only_while_aiming in
## gameplay_tweaks.cfg lässt sich das alte Verhalten wiederherstellen (false = immer Zeitlupe).

const SIM_HZ := 480
const DT := 1.0 / SIM_HZ

## Tempo im Slowdown (0.10 = 10 % Echtzeit). Mit 1/2 oder Mausrad änderbar.
var slowmo_scale := 0.10
## Tempo des normalen Gameplays (1.0 = Echtzeit), nur aktiv wenn slowdown_only_while_aiming.
var normal_speed := 1.0
## true: Slowdown nur bei angelegter Waffe, sonst normal_speed. false: immer Slowdown.
var slowdown_only_while_aiming := true
## echte Sekunden für den weichen Übergang zwischen normalem Tempo und Slowdown.
var slowdown_blend_time := 0.15
## Tempo aller "Echtzeit"-Abschnitte (Vorlauf, Abschluss-Replay): 1.0 = echte Echtzeit,
## 2.0 = doppelt so schnell. Der GameManager setzt damit override_scale.
var realtime_speed := 1.0
## Wird vom GameManager pro Frame gesetzt: der gesteuerte Officer hat die Waffe angelegt.
var aiming := false
## > 0: fester Wert, der die Zeitlupe überschreibt (Auswertung, Abschluss-Replay = 1.0).
var override_scale := -1.0
## 0 = normales Tempo, 1 = Slowdown (weicher Übergang in _process).
var _blend := 1.0

const SLOWMO_MIN := 0.03
const SLOWMO_MAX := 1.0


func _process(delta: float) -> void:
	# Zielwert für den Blend: 1.0 = Slowdown, 0.0 = normales Tempo.
	# delta ist hier echte Zeit – genau das ist für den weichen Übergang gewollt.
	var ziel := 1.0
	if slowdown_only_while_aiming:
		ziel = 1.0 if aiming else 0.0
	_blend = move_toward(_blend, ziel, delta / maxf(slowdown_blend_time, 0.001))
	Engine.physics_ticks_per_second = maxi(1, roundi(SIM_HZ * current_scale()))


## Aktueller Zeitfaktor: 1.0 = Echtzeit.
func current_scale() -> float:
	if override_scale > 0.0:
		return override_scale
	return play_scale()


## Tempo des steuerbaren Spiels ohne Override: im Aiming-Modus weich zwischen
## normal_speed und slowmo_scale geblendet, sonst immer slowmo_scale.
func play_scale() -> float:
	if not slowdown_only_while_aiming:
		return slowmo_scale
	return lerpf(normal_speed, slowmo_scale, _blend)


## Tempo, das direkt nach einer Übernahme ohne angelegte Waffe gilt.
func rest_scale() -> float:
	if slowdown_only_while_aiming:
		return normal_speed
	return slowmo_scale


func adjust(step: float) -> void:
	slowmo_scale = clampf(slowmo_scale + step, SLOWMO_MIN, SLOWMO_MAX)


## Übernimmt die Zeitwerte aus den Tweaks (Sektion "tempo"): slowmo_scale geklemmt
## auf SLOWMO_MIN..SLOWMO_MAX, normal_speed geklemmt auf 0.05..2.0.
func apply_tweaks() -> void:
	slowmo_scale = clampf(Tweaks.num("tempo", "slowdown_speed", 0.10), SLOWMO_MIN, SLOWMO_MAX)
	normal_speed = clampf(Tweaks.num("tempo", "normal_speed", 1.0), 0.05, 2.0)
	slowdown_only_while_aiming = Tweaks.flag("tempo", "slowdown_only_while_aiming", true)
	slowdown_blend_time = Tweaks.num("tempo", "slowdown_blend_time", 0.15)
	realtime_speed = clampf(Tweaks.num("tempo", "realtime_speed", 1.0), 0.25, 4.0)
	if not slowdown_only_while_aiming or aiming:
		_blend = 1.0
	else:
		_blend = 0.0
