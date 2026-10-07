extends Control

var data: ReactiveWidget = null

var _values: Array = []
var _widths: Array = []
var _edit_mode: bool = false
var _hovered_index: int = -1

func on_widget_ready(reactive_widget: ReactiveWidget) -> void:
	data = reactive_widget

	if not data.properties.has_entry("values"):
		data.properties.value["values"] = ReactiveDynamicField.new(
			PackedFloat32Array(), data.properties, "values"
		)
	if not data.properties.has_entry("widths"):
		data.properties.value["widths"] = ReactiveConstantField.new(
			PackedFloat32Array(), data.properties, "widths"
		)
	if not data.properties.has_entry("min_value"):
		data.properties.value["min_value"] = ReactiveConstantField.new(-10.0, data.properties, "min_value")
	if not data.properties.has_entry("max_value"):
		data.properties.value["max_value"] = ReactiveConstantField.new(10.0, data.properties, "max_value")
	if not data.properties.has_entry("positive_color"):
		data.properties.value["positive_color"] = ReactiveConstantField.new(Color.LIME_GREEN, data.properties, "positive_color")
	if not data.properties.has_entry("negative_color"):
		data.properties.value["negative_color"] = ReactiveConstantField.new(Color.CRIMSON, data.properties, "negative_color")
	if not data.properties.has_entry("zero_line_color"):
		data.properties.value["zero_line_color"] = ReactiveConstantField.new(Color.GRAY, data.properties, "zero_line_color")
	if not data.properties.has_entry("warning_threshold"):
		data.properties.value["warning_threshold"] = ReactiveConstantField.new(7.0, data.properties, "warning_threshold")
	if not data.properties.has_entry("warning_color"):
		data.properties.value["warning_color"] = ReactiveConstantField.new(Color.ORANGE, data.properties, "warning_color")
	if not data.properties.has_entry("no_data_color"):
		data.properties.value["no_data_color"] = ReactiveConstantField.new(Color(0.5, 0.5, 0.5, 0.35), data.properties, "no_data_color")
	if not data.properties.has_entry("show_extremes"):
		data.properties.value["show_extremes"] = ReactiveConstantField.new(true, data.properties, "show_extremes")
	if not data.properties.has_entry("extremes_color"):
		data.properties.value["extremes_color"] = ReactiveConstantField.new(Color.WHITE, data.properties, "extremes_color")

	var values_field: ReactiveDynamicField = data.properties.value["values"]
	values_field.set_context_provider(_build_script_context)
	values_field.resolved.connect_self_changed(_on_values_changed)
	_on_values_changed(values_field.resolved)

	var widths_field: ReactiveConstantField = data.properties.value["widths"]
	widths_field.set_context_provider(_build_script_context)
	widths_field.resolved.connect_self_changed(_on_widths_changed)
	_on_widths_changed(widths_field.resolved)

	for prop: String in ["min_value", "max_value", "positive_color", "negative_color", "zero_line_color", "warning_threshold", "warning_color", "no_data_color", "show_extremes", "extremes_color"]:
		var field: ReactiveConstantField = data.properties.value[prop]
		field.set_context_provider(_build_script_context)
		field.resolved.connect_self_changed(func(_r: ReactiveVariant) -> void: queue_redraw())

	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)

func build_properties(builder: WidgetPropertyBuilder) -> void:
	builder.add_dynamic_field("values", "Values", data.properties)
	builder.add_constant_array_field("widths", "Widths", data.properties)
	builder.add_constant_float_field("min_value", "Minimum", data.properties)
	builder.add_constant_float_field("max_value", "Maximum", data.properties)
	builder.add_constant_color_field("positive_color", "Positive Color", data.properties)
	builder.add_constant_color_field("negative_color", "Negative Color", data.properties)
	builder.add_constant_color_field("zero_line_color", "Zero Line Color", data.properties)
	builder.add_constant_float_field("warning_threshold", "Warning Threshold", data.properties)
	builder.add_constant_color_field("warning_color", "Warning Color", data.properties)
	builder.add_constant_color_field("no_data_color", "No Data Color", data.properties)
	builder.add_constant_bool_field("show_extremes", "Show Min/Max Overlay", data.properties)
	builder.add_constant_color_field("extremes_color", "Min/Max Text Color", data.properties)

func on_edit_mode_changed(enabled: bool) -> void:
	_edit_mode = enabled
	mouse_filter = Control.MOUSE_FILTER_IGNORE if enabled else Control.MOUSE_FILTER_STOP
	queue_redraw()

func _build_script_context() -> Dictionary:
	return { "id": data.widget_id }

# ── Generic Array coercion (Array or any Packed*Array → plain Array) ───────
static func _coerce_to_array(v: Variant) -> Array:
	if v == null:
		return []
	if v is Array:
		return v
	return Array(v)

# ── Null/non-numeric-safe helpers ───────────────────────────────────────────
static func _is_numeric(v: Variant) -> bool:
	return v is float or v is int

static func _safe_float(v: Variant, fallback: float = 0.0) -> float:
	return float(v) if _is_numeric(v) else fallback

func _on_values_changed(r: ReactiveVariant) -> void:
	# Elements are kept as raw Variants (including null for unresolved
	# per-zone OPC tags) — no coercion here. _draw()/_update_tooltip()
	# decide how to render a missing value; they don't get silently
	# collapsed to 0.0, which would be indistinguishable from a genuine
	# "perfectly flat" reading.
	_values = _coerce_to_array(r.value)
	queue_redraw()

func _on_widths_changed(r: ReactiveVariant) -> void:
	_widths = _coerce_to_array(r.value)
	queue_redraw()

func _gui_input(event: InputEvent) -> void:
	if _edit_mode or _values.is_empty():
		return

	if event is InputEventMouseMotion:
		var mouse_motion: InputEventMouseMotion = event
		var idx: int = _zone_index_at(mouse_motion.position)
		if idx != _hovered_index:
			_hovered_index = idx
			_update_tooltip(idx)
			queue_redraw()

func _on_mouse_entered() -> void:
	pass

func _on_mouse_exited() -> void:
	if _hovered_index != -1:
		_hovered_index = -1
		tooltip_text = ""
		queue_redraw()

func _compute_zone_offsets() -> PackedFloat32Array:
	var zone_count: int = _values.size()
	var offsets: PackedFloat32Array = PackedFloat32Array()
	offsets.resize(zone_count + 1)

	var w: float = size.x

	if _widths.size() == zone_count and zone_count > 0:
		var total_width: float = 0.0
		for width: Variant in _widths:
			# A missing/null width contributes 0 to the total rather than
			# crashing — its zone will simply collapse to 0px width below,
			# which is preferable to guessing a value.
			total_width += max(_safe_float(width), 0.0)

		if is_zero_approx(total_width):
			_fill_equal_offsets(offsets, zone_count, w)
		else:
			var acc: float = 0.0
			offsets[0] = 0.0
			for i: int in zone_count:
				acc += max(_safe_float(_widths[i]), 0.0)
				offsets[i + 1] = (acc / total_width) * w
	else:
		_fill_equal_offsets(offsets, zone_count, w)

	return offsets

func _fill_equal_offsets(offsets: PackedFloat32Array, zone_count: int, w: float) -> void:
	if zone_count == 0:
		return
	var bar_width: float = w / float(zone_count)
	for i: int in zone_count + 1:
		offsets[i] = i * bar_width

func _zone_index_at(pos: Vector2) -> int:
	if _values.is_empty() or size.x <= 0.0:
		return -1

	var offsets: PackedFloat32Array = _compute_zone_offsets()
	for i: int in _values.size():
		if pos.x >= offsets[i] and pos.x < offsets[i + 1]:
			return i
	return -1

func _update_tooltip(idx: int) -> void:
	if idx < 0:
		tooltip_text = ""
		return

	var raw: Variant = _values[idx]
	if _is_numeric(raw):
		tooltip_text = "Zone %d: %.2f I-Units" % [idx, float(raw)]
	else:
		tooltip_text = "Zone %d: No Data" % idx

func _draw() -> void:
	if _values.is_empty():
		return

	var min_value: float = float(data.properties.value["min_value"].resolved.value)
	var max_value: float = float(data.properties.value["max_value"].resolved.value)
	var pos_color: Color = data.properties.value["positive_color"].resolved.value
	var neg_color: Color = data.properties.value["negative_color"].resolved.value
	var zero_color: Color = data.properties.value["zero_line_color"].resolved.value
	var warn_color: Color = data.properties.value["warning_color"].resolved.value
	var warn_threshold: float = float(data.properties.value["warning_threshold"].resolved.value)
	var no_data_color: Color = data.properties.value["no_data_color"].resolved.value

	var safe_max: float = max_value if not is_zero_approx(max_value) else 0.0001
	var safe_min: float = min_value if not is_zero_approx(min_value) else -0.0001

	var w: float = size.x
	var h: float = size.y
	var center_y: float = h * 0.5

	draw_line(Vector2(0, center_y), Vector2(w, center_y), zero_color, 1.0)

	var zone_count: int = _values.size()
	if zone_count == 0:
		return

	var offsets: PackedFloat32Array = _compute_zone_offsets()

	for i: int in zone_count:
		var raw_value: Variant = _values[i]
		var x_start: float = offsets[i]
		var x_end: float = offsets[i + 1]
		var zone_width: float = max(x_end - x_start - 1.0, 1.0)

		if not _is_numeric(raw_value):
			_draw_no_data_zone(x_start, zone_width, h, no_data_color)
			if i == _hovered_index:
				draw_rect(Rect2(x_start, 0, zone_width, h), Color(1, 1, 1, 0.15))
			continue

		var value: float = clamp(float(raw_value), min_value, max_value)

		var normalized: float = 0.0
		if value >= 0.0:
			normalized = value / safe_max
		else:
			normalized = value / abs(safe_min)

		var bar_height: float = normalized * (h * 0.5)
		var color: Color = pos_color if value >= 0.0 else neg_color
		if abs(float(raw_value)) >= warn_threshold:
			color = warn_color

		var rect: Rect2
		if value >= 0.0:
			rect = Rect2(x_start, center_y - bar_height, zone_width, bar_height)
		else:
			rect = Rect2(x_start, center_y, zone_width, abs(bar_height))

		draw_rect(rect, color)

		if i == _hovered_index:
			draw_rect(rect, Color(1, 1, 1, 0.25))

	if bool(data.properties.value["show_extremes"].resolved.value):
		_draw_extremes_overlay()

# Renders a zone with no resolvable value as a muted, hatched placeholder
# spanning the full chart height, rather than silently drawing it as a
# zero-value bar (which would be indistinguishable from a genuine flat
# reading of 0.0).
func _draw_no_data_zone(x_start: float, zone_width: float, h: float, no_data_color: Color) -> void:
	draw_rect(Rect2(x_start, 0, zone_width, h), no_data_color)

	var step: float = 8.0
	var i: float = 0.0
	while i < zone_width + h:
		var x1: float = x_start + i
		var y1: float = 0.0
		var x2: float = x_start + i - h
		var y2: float = h
		draw_line(
			Vector2(clamp(x1, x_start, x_start + zone_width), y1),
			Vector2(clamp(x2, x_start, x_start + zone_width), y2),
			no_data_color.lightened(0.2),
			1.0
		)
		i += step

# Draws the *static* scale boundaries (min_value / max_value) as a fixed
# overlay — these are the configured display range, not the actual
# min/max of the current dataset. They exist purely to give the viewer a
# reference for how the bars are being scaled.
#
# Anchored to top-right (max) and bottom-right (min), independent of
# `size` beyond positioning, so this never participates in layout —
# sibling widgets sharing the same width remain perfectly aligned.
func _draw_extremes_overlay() -> void:
	var min_value: float = float(data.properties.value["min_value"].resolved.value)
	var max_value: float = float(data.properties.value["max_value"].resolved.value)

	var font: Font = ThemeDB.fallback_font
	var font_size: int = ThemeDB.fallback_font_size
	var text_color: Color = data.properties.value["extremes_color"].resolved.value
	var padding: float = 4.0

	var max_text: String = "%.2f" % max_value
	var min_text: String = "%.2f" % min_value

	var available_width: float = size.x - padding * 2.0

	# Top-right: maximum possible display value
	var max_pos: Vector2 = Vector2(padding, padding + font.get_ascent(font_size))
	draw_string_outline(font, max_pos, max_text, HORIZONTAL_ALIGNMENT_RIGHT, available_width, font_size, 2, Color.BLACK)
	draw_string(font, max_pos, max_text, HORIZONTAL_ALIGNMENT_RIGHT, available_width, font_size, text_color)

	# Bottom-right: minimum possible display value
	var min_baseline_y: float = size.y - padding - font.get_descent(font_size)
	var min_pos: Vector2 = Vector2(padding, min_baseline_y)
	draw_string_outline(font, min_pos, min_text, HORIZONTAL_ALIGNMENT_RIGHT, available_width, font_size, 2, Color.BLACK)
	draw_string(font, min_pos, min_text, HORIZONTAL_ALIGNMENT_RIGHT, available_width, font_size, text_color)
