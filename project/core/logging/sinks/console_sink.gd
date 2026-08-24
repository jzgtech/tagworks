class_name ConsoleSink
extends LogSink

var min_level: int = LogManager.Level.DEBUG

func write(entry: Dictionary) -> void:
    if entry["level"] < min_level:
        return

    var line: String = "[%s] [%s] [%s] %s" % [
        entry["timestamp"], entry["level_name"], entry["category"], entry["message"]
    ]

    match entry["level"]:
        LogManager.Level.ERROR, LogManager.Level.CRITICAL:
            push_error(line)
        LogManager.Level.WARNING:
            push_warning(line)
        _:
            print(line)
