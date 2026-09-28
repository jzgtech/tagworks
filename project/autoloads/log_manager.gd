extends Node

enum Level { DEBUG, INFO, WARNING, ERROR, CRITICAL }

const LEVEL_NAMES: Dictionary = {
	Level.DEBUG: "DEBUG",
	Level.INFO: "INFO",
	Level.WARNING: "WARNING",
	Level.ERROR: "ERROR",
	Level.CRITICAL: "CRITICAL",
}

## Emitted for every log call — useful for a future in-game console or remote telemetry sink
signal log_emitted(entry: Dictionary)

var _sinks: Array[LogSink] = []

func _ready() -> void:
	register_sink(ConsoleSink.new())
	register_sink(FileSink.new())
	register_sink(ToastSink.new())

func register_sink(sink: LogSink) -> void:
	_sinks.append(sink)

func unregister_sink(sink: LogSink) -> void:
	_sinks.erase(sink)

## Core dispatch ------------------------------------------------------------

func _log(level: Level, message: String, category: String = "General", meta: Dictionary = {}) -> void:
	var entry: Dictionary = {
		"level": level,
		"level_name": LEVEL_NAMES[level],
		"message": message,
		"category": category,
		"timestamp": Time.get_datetime_string_from_system(),
		"meta": meta,
	}
	log_emitted.emit(entry)
	for sink: LogSink in _sinks:
		sink.write(entry)

## Public API -----------------------------------------------------------

func debug(message: String, category: String = "General", meta: Dictionary = {}) -> void:
	_log(Level.DEBUG, message, category, meta)

func info(message: String, category: String = "General", meta: Dictionary = {}) -> void:
	_log(Level.INFO, message, category, meta)

func warning(message: String, category: String = "General", meta: Dictionary = {}) -> void:
	_log(Level.WARNING, message, category, meta)

func error(message: String, category: String = "General", meta: Dictionary = {}) -> void:
	_log(Level.ERROR, message, category, meta)

func critical(message: String, category: String = "General", meta: Dictionary = {}) -> void:
	_log(Level.CRITICAL, message, category, meta)
