class_name LogSink
extends RefCounted

## Override in subclasses. `entry` contains:
## level, level_name, message, category, timestamp, meta
func write(entry: Dictionary) -> void:
    push_error("LogSink.write() not implemented in %s" % get_script().resource_path)
