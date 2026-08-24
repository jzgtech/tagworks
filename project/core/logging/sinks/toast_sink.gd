class_name ToastSink
extends LogSink

var min_level: int = LogManager.Level.WARNING

const LEVEL_TO_TOAST_TYPE: Dictionary= {
    LogManager.Level.INFO: "info",
    LogManager.Level.WARNING: "warning",
    LogManager.Level.ERROR: "error",
    LogManager.Level.CRITICAL: "error",
}

func write(entry: Dictionary) -> void:
    # Per-call override: Logger.info(msg, cat, {"silent": true}) skips the toast
    if entry["meta"].get("silent", false):
        return

    var force_toast: bool = entry["meta"].get("force_toast", false)
    if entry["level"] < min_level and not force_toast:
        return
    if entry["level"] == LogManager.Level.DEBUG and not force_toast:
        return

    var toast_type: String = LEVEL_TO_TOAST_TYPE.get(entry["level"], "info")
    ToastManager.show_toast(entry["message"], toast_type)
