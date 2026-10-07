extends Control

var data: Object = null
var _value: float = 0.0
var _hovered: bool = false

func on_widget_ready(reactive_widget: ReactiveWidget) -> void:
	data = reactive_widget

	if not data.properties.has_entry("value"):
		data.properties.value["value"] = ReactiveDynamicField.new(
			0.0, data.properties, "value"
		)
	if not data.properties.has_entry("min_value"):
		data.properties.value["min_value"] = ReactiveConstantField.new(0.0, data.properties, "min_value")
	if not data.properties.has_entry("max_value"):
		data.properties.value["max_value"] = ReactiveConstantField.new(10.0, data.properties, "max_value")
	if not data.properties.has_entry("bar_color"):
		data.properties.value["bar_color"] = ReactiveConstantField.new(Color.CORNFLOWER_BLUE, data.properties, "bar_color")
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

	var value_field: ReactiveDynamicField = data.properties.value["value"]
	value_field.set_context_provider(_build_script_context)
	value_field.resolved.connect_self_changed(_on_value_changed)
	_on_value_changed(value_field.resolved)

	for prop: String in ["min_value", "max_value", "bar_color", "warning_threshold", "warning_color", "no_data_color", "show_extremes", "extremes_color"]:
		var field: ReactiveConstantField = data.properties.value[prop]
		field.set_context_provider(_build_script_context)
		field.resolved.connect_self_changed(func(_r: ReactiveVariant) -> void: queue_redraw())

	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)
	resized.connect(queue_redraw)

func build_properties(builder: WidgetPropertyBuilder) -> void:
	builder.add_dynamic_field("value", "Value", data.properties)
	builder.add_constant_float_field("min_value", "Minimum", data.properties)
	builder.add_constant_float_field("max_value", "Maximum", data.properties)
	builder.add_constant_color_field("bar_color", "Bar Color", data.properties)
	builder.add_constant_float_field("warning_threshold", "Warning Threshold", data.properties)
	builder.add_constant_color_field("warning_color", "Warning Color", data.properties)
	builder.add_constant_color_field("no_data_color", "No Data Color", data.properties)
	builder.add_constant_bool_field("show_extremes", "Show Min/Max Labels", data.properties)
	builder.add_constant_color_field("extremes_color", "Min/Max Text Color", data.properties)

func on_edit_mode_changed(enabled: bool) -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE if enabled else Control.MOUSE_FILTER_STOP

func _build_script_context() -> Dictionary:
	return { "id": data.widget_id }

func _on_value_changed(r: ReactiveVariant) -> void:
	_value = r.value if (r.value is float or r.value is int) else NAN
	queue_redraw()

func _on_mouse_entered() -> void:
	_hovered = true
	queue_redraw()

func _on_mouse_exited() -> void:
	_hovered = false
	queue_redraw()

func _draw() -> void:
	var min_value: float = data.properties.value["min_value"].resolved.value
	var max_value: float = data.properties.value["max_value"].resolved.value
	var bar_color: Color = data.properties.value["bar_color"].resolved.value
	var warning_threshold: float = data.properties.value["warning_threshold"].resolved.value
	var warning_color: Color = data.properties.value["warning_color"].resolved.value
	var no_data_color: Color = data.properties.value["no_data_color"].resolved.value
	var show_extremes: bool = data.properties.value["show_extremes"].resolved.value
	var extremes_color: Color = data.properties.value["extremes_color"].resolved.value

	var range_span: float = max(max_value - min_value, 0.0001)

	if is_nan(_value):
		draw_rect(Rect2(Vector2.ZERO, size), no_data_color)
	else:
		var clamped_v: float = clamp(_value, min_value, max_value)
		var normalized: float = (clamped_v - min_value) / range_span
		var bar_top_y: float = size.y * (1.0 - normalized)

		var color: Color = warning_color if _value >= warning_threshold else bar_color
		if _hovered:
			color = color.lightened(0.25)

		draw_rect(Rect2(Vector2(0.0, bar_top_y), Vector2(size.x, size.y - bar_top_y)), color)

	if show_extremes:
		var font: Font = ThemeDB.fallback_font
		var font_size: int = 12

		var max_text: String = "%.2f" % max_value
		draw_string(font, Vector2(size.x * 0.5, float(font_size)), max_text, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size, extremes_color)

		var min_text: String = "%.2f" % min_value
		draw_string(font, Vector2(size.x * 0.5, size.y - 4.0), min_text, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size, extremes_color)
