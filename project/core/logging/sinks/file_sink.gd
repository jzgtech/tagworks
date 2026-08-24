class_name FileSink
extends LogSink

var min_level: int = LogManager.Level.INFO
var log_path: String = "user://logs/game.log"
var _file: FileAccess

func _init() -> void:
    DirAccess.make_dir_recursive_absolute(log_path.get_base_dir())
    _file = FileAccess.open(log_path, FileAccess.WRITE_READ)
    if _file:
        _file.seek_end()

func write(entry: Dictionary) -> void:
    if entry["level"] < min_level or _file == null:
        return
    var line: String = "[%s] [%s] [%s] %s" % [
        entry["timestamp"], entry["level_name"], entry["category"], entry["message"]
    ]
    _file.store_line(line)
    _file.flush()
