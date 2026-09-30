extends Node

enum Breakpoint { Mobile, Desktop }

const THRESHOLDS: Dictionary = {
	Breakpoint.Mobile: 0,
	Breakpoint.Desktop: 500,
}

signal breakpoint_changed(old_bp: Breakpoint, new_bp: Breakpoint)
signal orientation_changed(is_portrait: bool)

# Tracks current layout state driven by the window/viewport dimensions
var current_breakpoint: Breakpoint = Breakpoint.Desktop
var is_portrait: bool = false

# Tracks physical hardware device attributes
var is_touch_device: bool = false
var is_mobile_hardware: bool = false


func _ready() -> void:
	# Check if physical touch capabilities are available
	is_touch_device = DisplayServer.is_touchscreen_available()
	
	# Cache the hardware device class once on startup
	is_mobile_hardware = _is_hardware_mobile()
	
	# Connect resize signal to handle dynamic responsive layout scaling
	get_tree().root.size_changed.connect(_on_size_changed)
	_on_size_changed()


func _on_size_changed() -> void:
	# 1. Layout logic: Use viewport size for visual breakpoints/orientation
	var view_size: Vector2 = get_viewport().get_visible_rect().size
	var new_bp: Breakpoint = _calc_breakpoint(view_size.x)
	var new_portrait: bool = view_size.y > view_size.x

	if new_bp != current_breakpoint:
		var old: Breakpoint = current_breakpoint
		current_breakpoint = new_bp
		breakpoint_changed.emit(old, new_bp)

	if new_portrait != is_portrait:
		is_portrait = new_portrait
		orientation_changed.emit(is_portrait)


func _calc_breakpoint(width: float) -> Breakpoint:
	var result: Breakpoint = Breakpoint.Mobile
	# Sort keys safely if your dictionary configuration scales past 2 entries
	for bp: Breakpoint in THRESHOLDS.keys():
		if width >= THRESHOLDS[bp]:
			result = bp
	return result


func _is_hardware_mobile() -> bool:
	# Check the actual platform name first (most reliable)
	var os_name: String = OS.get_name()
	if os_name in ["Android", "iOS"] or OS.has_feature("force_mobile"):
		return true
	if os_name in ["macOS", "Windows", "Linux", "FreeBSD", "NetBSD"]:
		return false
		
	# Fallback/Web: Check the actual display dimensions if platform is ambiguous (like HTML5/Web)
	var screen_size: Vector2i = DisplayServer.screen_get_size()
	var hardware_portrait: bool = screen_size.y > screen_size.x
	
	# If the physical monitor width is very narrow or a small screen locked to portrait
	return screen_size.x < 1024 or (hardware_portrait and screen_size.x < 1280)


# Dynamic states: Tells you if your UI layout context is behaving like a phone screen
func is_mobile() -> bool:
	return current_breakpoint == Breakpoint.Mobile

func is_desktop() -> bool:
	return current_breakpoint == Breakpoint.Desktop


# Hardware states: Tells you if the code is executing on an actual mobile device architecture
func is_running_on_mobile_hardware() -> bool:
	return is_mobile_hardware

func is_running_on_desktop_hardware() -> bool:
	return not is_mobile_hardware
