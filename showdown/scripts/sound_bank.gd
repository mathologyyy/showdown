class_name SoundBank
extends Node
## Alle Sounds des Spiels. Schüsse, Blendgranate und Tür sind CC0-Aufnahmen von
## opengameart.org (assets/sounds/), die kurzen Signale (Countdown, Slowdown,
## Abpraller, Einschlag, Freeze) werden beim Start im Code erzeugt.

const RATE := 22050
## Dateien: Pfad, Startversatz in Sekunden (Stille am Anfang überspringen), Lautstärke in dB
const FILES := {
	"shot_team": ["res://assets/sounds/shot_team.wav", 0.13, -6.0],
	"shot_enemy": ["res://assets/sounds/shot_enemy.wav", 0.22, -4.0],
	"flash": ["res://assets/sounds/flash_bang.wav", 0.0, 0.0],
	"door": ["res://assets/sounds/door_open.wav", 0.57, -2.0],
}
const VOICES := 10

var _streams := {}              # Name -> {stream, offset, db}
var _players: Array[AudioStreamPlayer] = []
var _next := 0


func _ready() -> void:
	for n in FILES:
		var f: Array = FILES[n]
		if ResourceLoader.exists(f[0]):
			_streams[n] = {"stream": load(f[0]), "offset": f[1], "db": f[2]}
	_add("beep", _tone(0.09, 880.0, 880.0, 0.0), -8.0)
	_add("go", _tone(0.32, 1320.0, 1320.0, 0.0), -6.0)
	_add("slowdown", _tone(1.5, 240.0, 42.0, 0.0), -3.0)
	_add("ricochet", _tone(0.28, 2900.0, 1300.0, 0.15), -9.0)
	_add("impact", _tone(0.07, 160.0, 70.0, 0.9), -12.0)
	_add("freeze", _tone(0.35, 110.0, 55.0, 0.1), -4.0)
	_add("rewind", _tone(0.9, 300.0, 1500.0, 0.25), -8.0)
	_add("alarm", _tone(0.18, 520.0, 390.0, 0.0), -9.0)
	for i in VOICES:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_players.append(p)


## pitch: Tonhöhe/Tempo (in Zeitlupe tiefer). Mehrere Sounds überlagern sich.
func play(sound: String, pitch := 1.0, db_offset := 0.0) -> void:
	if not _streams.has(sound):
		return
	var s: Dictionary = _streams[sound]
	var p := _players[_next]
	_next = (_next + 1) % VOICES
	p.stream = s.stream
	p.pitch_scale = clampf(pitch, 0.3, 2.0)
	p.volume_db = s.db + db_offset
	p.play(s.offset)


func _add(sound: String, stream: AudioStream, db: float) -> void:
	_streams[sound] = {"stream": stream, "offset": 0.0, "db": db}


## Erzeugt einen kurzen Ton: Sinus, der von f0 nach f1 gleitet, mit Rauschanteil
## (noise 0..1) und abklingender Hüllkurve.
func _tone(seconds: float, f0: float, f1: float, noise: float) -> AudioStreamWAV:
	var n := int(seconds * RATE)
	var data := PackedByteArray()
	data.resize(n * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(f0 + f1 * 7.0 + seconds)
	var phase := 0.0
	for i in n:
		var t := float(i) / float(n)
		phase += TAU * lerpf(f0, f1, t) / RATE
		var env := minf(1.0, t * 60.0) * pow(1.0 - t, 1.6)
		var v := lerpf(sin(phase), rng.randf_range(-1.0, 1.0), noise) * env
		data.encode_s16(i * 2, int(clampf(v, -1.0, 1.0) * 30000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = data
	return w
