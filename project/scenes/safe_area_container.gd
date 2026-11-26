extends MarginContainer

const BASE_MARGIN_LEFT: int   = 8
const BASE_MARGIN_TOP: int    = 8
const BASE_MARGIN_RIGHT: int  = 8
const BASE_MARGIN_BOTTOM: int = 8

func _ready() -> void:
	# Recalculate margins if the screen rotates or resizes
	get_tree().root.size_changed.connect(_update_safe_area)
	_update_safe_area()

func _update_safe_area() -> void:
	# Start with your default 8px padding
	var margin_left: int   = BASE_MARGIN_LEFT
	var margin_top: int    = BASE_MARGIN_TOP
	var margin_right: int  = BASE_MARGIN_RIGHT
	var margin_bottom: int = BASE_MARGIN_BOTTOM

	# 1. Check if the game is running on a mobile platform
	if BreakpointManager.is_mobile():
		# 2. Get physical safe area, physical window size, and virtual viewport size
		var safe_area: Rect2i = DisplayServer.get_display_safe_area()
		var window_size: Vector2i = DisplayServer.window_get_size()
		var viewport_size: Vector2 = get_viewport().get_visible_rect().size

		# Ensure valid dimensions to avoid division by zero
		if safe_area.size != Vector2i.ZERO and window_size.x > 0 and window_size.y > 0:
			# 3. Calculate conversion ratio from physical pixels to Godot UI units
			var scale_x: float = viewport_size.x / float(window_size.x)
			var scale_y: float = viewport_size.y / float(window_size.y)

			# 4. Add the scaled safe area padding to your base margins
			margin_left += int(safe_area.position.x * scale_x)
			margin_top += int(safe_area.position.y * scale_y)
			margin_right += int((window_size.x - safe_area.end.x) * scale_x)
			margin_bottom += int((window_size.y - safe_area.end.y) * scale_y)

	# 5. Apply the final padding to this MarginContainer
	add_theme_constant_override("margin_left", margin_left)
	add_theme_constant_override("margin_top", margin_top)
	add_theme_constant_override("margin_right", margin_right)
	add_theme_constant_override("margin_bottom", margin_bottom)
