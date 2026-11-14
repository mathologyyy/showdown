class_name RoundSystem
extends RefCounted
## Daten des Rundensystems "Go Go Go".
##
## Begriffe:
##  Durchlauf (pass) – alle lebenden Officer sind je einmal am Zug. Alle Züge eines
##                     Durchlaufs starten vom selben Checkpoint (T0).
##  Zug (turn)       – der Spieler steuert einen Officer, bis ein NEUER Schuss fällt.
##  Track            – Aufzeichnung eines Zugs: Position/Blickrichtung pro Tick + Schüsse.
##  Auswertung       – nach dem letzten Zug laufen alle Tracks gemeinsam ohne Unterbrechung.
##                     Ihr Endzustand wird der Checkpoint des nächsten Durchlaufs, ihre
##                     Welt-Aufzeichnung ein Segment der Timeline fürs Abschluss-Replay.

## Aufzeichnung eines Officer-Zugs.
class Track:
	const STRIDE := 4
	var frames := PackedFloat32Array()   # pro Tick: x, z, yaw, flags (Schild oben, Rolle)
	var shots: Array = []                # [{tick: int, dir: Vector3}]
	var throws: Array = []               # Blendgranaten: [{tick: int, target: Vector3}]
	var doors: Array = []                # geöffnete Türen: [{tick: int, door: int}]

	func length() -> int:
		return frames.size() / STRIDE

	func add_frame(o: Actor) -> void:
		frames.append(o.global_position.x)
		frames.append(o.global_position.z)
		frames.append(o.yaw)
		frames.append(float(o.flags()))


## Welt-Aufzeichnung einer Auswertung (ein Abschnitt des Abschluss-Replays).
class Segment:
	var ticks := 0
	const STRIDE := 5
	var tracks: Array = []               # pro Figur PackedFloat32Array: x, z, yaw, alive, flags
	## Kugel-Abschnitte: [{tick, who (Index der Figur, -1 = Abpraller ohne Mündungsfeuer),
	##                     from, dir, enemy, dist (Flugstrecke), hit_actor}]
	var shots: Array = []
	var grenades: Array = []             # [{tick, from, to}]
	var doors: Array = []                # [{tick, door}]


## Gegnerschüsse gelten als "bekannt", wenn derselbe Gegner in einem früheren Zug
## dieses Durchlaufs ungefähr zur selben Zeit gefeuert hat (Toleranz in Ticks).
const SHOT_MATCH_TICKS := 60

var checkpoint: Dictionary = {}
var pass_index := 0
var order: Array[int] = []               # Officer-Indizes, die in diesem Durchlauf dran sind
var turn := 0
var tracks: Dictionary = {}              # Officer-Index -> Track
var timeline: Array[Segment] = []

var _known_shots: Array = []             # [{enemy: int, tick: int}]
var _consumed: Array[bool] = []


func begin_pass(p_checkpoint: Dictionary, p_order: Array[int]) -> void:
	checkpoint = p_checkpoint
	order = p_order
	pass_index += 1
	turn = 0
	tracks.clear()
	_known_shots.clear()


## Denselben Durchlauf noch einmal von vorn (nach Fehlschlag).
func retry_pass() -> void:
	turn = 0
	tracks.clear()
	_known_shots.clear()


func active_idx() -> int:
	return order[turn]


## Startet den Zug des aktiven Officers und liefert dessen leeren Track.
func begin_turn() -> Track:
	_reset_consumed()
	var t := Track.new()
	tracks[active_idx()] = t
	return t


func begin_resolve() -> void:
	_reset_consumed()


## true, solange noch ein Officer in diesem Durchlauf dran ist.
func advance_turn() -> bool:
	turn += 1
	return turn < order.size()


func longest_track() -> int:
	var n := 0
	for t: Track in tracks.values():
		n = maxi(n, t.length())
	return n


## Hat dieser Gegner in einem früheren Zug schon (ungefähr) jetzt gefeuert?
## Jeder bekannte Schuss wird pro Zug nur einmal "verbraucht".
func match_enemy_shot(enemy_idx: int, tick: int) -> bool:
	for i in _known_shots.size():
		var k: Dictionary = _known_shots[i]
		if not _consumed[i] and k.enemy == enemy_idx and absi(k.tick - tick) <= SHOT_MATCH_TICKS:
			_consumed[i] = true
			return true
	return false


func add_known_shot(enemy_idx: int, tick: int) -> void:
	_known_shots.append({"enemy": enemy_idx, "tick": tick})
	_consumed.append(true)


func total_ticks() -> int:
	var n := 0
	for s in timeline:
		n += s.ticks
	return n


func _reset_consumed() -> void:
	_consumed.resize(_known_shots.size())
	_consumed.fill(false)
