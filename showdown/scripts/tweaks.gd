extends Node
## Autoload "Tweaks": alle gameplay-relevanten Zahlen kommen aus einer
## editierbaren Datei (res://gameplay_tweaks.cfg, Godot-ConfigFile-Format).
##
## Der Code liest die Werte über num() / whole() / flag(). Fehlt ein Schlüssel,
## wird der übergebene Default zurückgegeben und einmalig eine Warnung ausgegeben.

const PATH := "res://gameplay_tweaks.cfg"

var cfg := ConfigFile.new()
var _warned := {}                     # "Sektion/Schlüssel" -> schon gewarnt


func _ready() -> void:
	reload()


## Lädt die Datei (erneut). Bei Ladefehler: Warnung, danach leere Config –
## dann greifen überall die Defaults aus dem Code.
func reload() -> void:
	var c := ConfigFile.new()
	var err := c.load(PATH)
	if err != OK:
		push_warning("Tweaks: %s nicht ladbar (Fehler %d) – arbeite mit leerer Config weiter." % [PATH, err])
		cfg = ConfigFile.new()
		return
	cfg = c


## Fließkomma-Wert aus der Datei, sonst Default (einmalig gewarnt).
func num(section: String, key: String, default: float) -> float:
	if not _has(section, key):
		return default
	return float(cfg.get_value(section, key, default))


## Ganzzahliger Wert aus der Datei, sonst Default (einmalig gewarnt).
func whole(section: String, key: String, default: int) -> int:
	if not _has(section, key):
		return default
	return int(cfg.get_value(section, key, default))


## Booleanischer Wert aus der Datei, sonst Default (einmalig gewarnt).
func flag(section: String, key: String, default: bool) -> bool:
	if not _has(section, key):
		return default
	return bool(cfg.get_value(section, key, default))


## Existenzprüfung mit einmaliger Warnung pro fehlendem Schlüssel.
func _has(section: String, key: String) -> bool:
	if cfg.has_section_key(section, key):
		return true
	var id := "%s/%s" % [section, key]
	if not _warned.has(id):
		_warned[id] = true
		push_warning("Tweaks: Schlüssel \"%s\" fehlt in %s – Default wird verwendet." % [id, PATH])
	return false
