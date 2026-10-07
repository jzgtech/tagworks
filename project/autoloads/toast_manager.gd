extends CanvasLayer

const TOAST_SCENE: Resource = preload("res://ui/toast/toast.tscn")

@export var max_visible: int = 4
@export var toast_spacing: float = 8.0
@export var default_duration: float = 3.0
@export var screen_margin: float = 16.0
@export var position_preset: String = "bottom_right" # top_left, top_right, bottom_left, bottom_right, top_center, bottom_center

var _container: VBoxContainer
var _active_toasts: Array[Toast] = []
var _queue: Array[Dictionary] = []

# Maps our string-based presets to Godot's built-in Control.LayoutPreset enum
const PRESET_MAP: Dictionary = {
	"top_left": Control.PRESET_TOP_LEFT,
	"top_right": Control.PRESET_TOP_RIGHT,
	"bottom_left": Control.PRESET_BOTTOM_LEFT,
	"bottom_right": Control.PRESET_BOTTOM_RIGHT,
	"top_center": Control.PRESET_CENTER_TOP,
	"bottom_center": Control.PRESET_CENTER_BOTTOM,
}

func _ready() -> void:
	layer = 100
	follow_viewport_enabled = false # Ensures it stays fixed to the WINDOW, not a camera/viewport transform
	_build_container()
	get_tree().root.size_changed.connect(_apply_position_preset)

func _build_container() -> void:
	_container = VBoxContainer.new()
	_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_container.add_theme_constant_override("separation", int(toast_spacing))
	add_child(_container)
	_apply_position_preset()

func _apply_position_preset() -> void:
	var preset: int = PRESET_MAP.get(position_preset, Control.PRESET_BOTTOM_RIGHT)

	# This is the exact same call the editor uses when you click a Layout preset.
	# PRESET_MODE_KEEP_SIZE keeps the container's current size instead of stretching it.
	_container.set_anchors_and_offsets_preset(
		preset,
		Control.PRESET_MODE_KEEP_SIZE,
		int(screen_margin)
	)

	# Grow direction still needs to be set manually. Anchors/offsets place the container,
	# but grow direction controls which way it expands when the VBoxContainer's size
	# changes at runtime (e.g., a toast is added/removed). Without this, a bottom-right
	# stack would grow further off-screen instead of upward/leftward toward the center.
	match position_preset:
		"top_left":
			_container.grow_horizontal = Control.GROW_DIRECTION_END
			_container.grow_vertical = Control.GROW_DIRECTION_END
		"top_right":
			_container.grow_horizontal = Control.GROW_DIRECTION_BEGIN
			_container.grow_vertical = Control.GROW_DIRECTION_END
		"bottom_left":
			_container.grow_horizontal = Control.GROW_DIRECTION_END
			_container.grow_vertical = Control.GROW_DIRECTION_BEGIN
		"bottom_right":
			_container.grow_horizontal = Control.GROW_DIRECTION_BEGIN
			_container.grow_vertical = Control.GROW_DIRECTION_BEGIN
		"top_center":
			_container.grow_horizontal = Control.GROW_DIRECTION_BOTH
			_container.grow_vertical = Control.GROW_DIRECTION_END
		"bottom_center":
			_container.grow_horizontal = Control.GROW_DIRECTION_BOTH
			_container.grow_vertical = Control.GROW_DIRECTION_BEGIN

## Public API -----------------------------------------------------------

func show_toast(message: String, type: String = "info", duration: float = -1.0) -> void:
	var dur: float = default_duration if duration < 0.0 else duration
	if _active_toasts.size() >= max_visible:
		_queue.append({"message": message, "type": type, "duration": dur})
		return
	_spawn_toast(message, type, dur)

func success(message: String, duration: float = -1.0) -> void:
	show_toast(message, "success", duration)

func error(message: String, duration: float = -1.0) -> void:
	show_toast(message, "error", duration)

func warning(message: String, duration: float = -1.0) -> void:
	show_toast(message, "warning", duration)

func info(message: String, duration: float = -1.0) -> void:
	show_toast(message, "info", duration)

func clear_all() -> void:
	_queue.clear()
	for t: Toast in _active_toasts.duplicate():
		t.play_out()

## Internal ---------------------------------------------------------------

func _spawn_toast(message: String, type: String, duration: float) -> void:
	if _container != null and is_instance_valid(_container):
		var toast: Toast = TOAST_SCENE.instantiate()
		_container.add_child(toast)
		# For bottom-anchored presets, newest toast should appear at the bottom of the stack visually
		if position_preset in ["bottom_left", "bottom_right", "bottom_center"]:
			_container.move_child(toast, _container.get_child_count() - 1)
		toast.setup(message, type, duration)
		toast.dismissed.connect(_on_toast_dismissed)
		_active_toasts.append(toast)
		toast.play_in()

func _on_toast_dismissed(toast: Toast) -> void:
	_active_toasts.erase(toast)
	toast.queue_free()
	if not _queue.is_empty():
		var next: Dictionary = _queue.pop_front()
		_spawn_toast(next["message"], next["type"], next["duration"])
