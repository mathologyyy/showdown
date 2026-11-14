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

const SIM_HZ := 480
const DT := 1.0 / SIM_HZ

## Zeitlupe im normalen Spiel (0.10 = 10 % Echtzeit). Im Spiel mit Q/E änderbar.
var slowmo_scale := 0.10
## Multiplikator, solange "Vorspulen" (Leertaste) gehalten wird.
var fast_forward_factor := 5.0
var fast_forward := false
## > 0: fester Wert, der die Zeitlupe überschreibt (Auswertung, Abschluss-Replay = 1.0).
var override_scale := -1.0

const SLOWMO_MIN := 0.03
const SLOWMO_MAX := 0.30


func _process(_delta: float) -> void:
	Engine.physics_ticks_per_second = maxi(1, roundi(SIM_HZ * current_scale()))


## Aktueller Zeitfaktor: 1.0 = Echtzeit.
func current_scale() -> float:
	if override_scale > 0.0:
		return override_scale
	return slowmo_scale * (fast_forward_factor if fast_forward else 1.0)


func adjust(step: float) -> void:
	slowmo_scale = clampf(slowmo_scale + step, SLOWMO_MIN, SLOWMO_MAX)
