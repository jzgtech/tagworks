extends Node

enum Breakpoint { Mobile, Desktop }

const THRESHOLDS: Dictionary = {
    Breakpoint.Mobile: 0,
    Breakpoint.Desktop: 500,
}

signal breakpoint_changed(old_bp: Breakpoint, new_bp: Breakpoint)
signal orientation_changed(is_portrait: bool)

var current_breakpoint: Breakpoint = Breakpoint.Desktop
var is_portrait: bool = false
var is_touch_device: bool = false

func _ready() -> void:
    is_touch_device = DisplayServer.is_touchscreen_available()
    get_tree().root.size_changed.connect(_on_size_changed)
    _on_size_changed()

func _on_size_changed() -> void:
    var size: Vector2 = get_viewport().get_visible_rect().size
    var new_bp: Breakpoint = _calc_breakpoint(size.x)
    var new_portrait: bool = size.y > size.x

    if new_bp != current_breakpoint:
        var old: Breakpoint = current_breakpoint
        current_breakpoint = new_bp
        breakpoint_changed.emit(old, new_bp)

    if new_portrait != is_portrait:
        is_portrait = new_portrait
        orientation_changed.emit(is_portrait)

func _calc_breakpoint(width: float) -> Breakpoint:
    var result: Breakpoint = Breakpoint.Mobile
    for bp: Breakpoint in THRESHOLDS.keys():
        if width >= THRESHOLDS[bp]:
            result = bp
    return result

func is_mobile() -> bool:
    return current_breakpoint <= Breakpoint.Mobile

func is_desktop() -> bool:
    return current_breakpoint >= Breakpoint.Desktop
