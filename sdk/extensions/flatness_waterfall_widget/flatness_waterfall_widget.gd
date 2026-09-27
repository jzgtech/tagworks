extends Control

var data: Object = null

# ── Sampling ─────────────────────────────────────────────────────────────
var _sample_timer: Timer
var _current_values: Array = []
var _widths: Array = []
var _zone_count: int = 0
var _max_rows: int = 1

# ── Double-buffered history image (avoids per-tick allocation) ──────────
var _buffer_image_a: Image
var _buffer_image_b: Image
var _active_is_a: bool = true
var _buffer_image: Image           # points at whichever buffer is "current"
var _buffer_texture: ImageTexture

# ── Cached resolved render properties (avoid per-tick dictionary lookups) ─
var _cached_min_value: float = -10.0
var _cached_max_value: float = 10.0
var _cached_max_color: Color = Color.LIME_GREEN
var _cached_zero_color: Color = Color.GRAY
var _cached_min_color: Color = Color.CRIMSON
var _cached_no_data_color: Color = Color(0.5, 0.5, 0.5, 0.35)
var _cached_curve_exponent: float = 1.0

# ── Cached zone offsets (avoid recompute on every draw/mouse-move) ──────
var _cached_offsets: PackedFloat32Array = PackedFloat32Array()
var _offsets_dirty: bool = true

# ── Debounced rebuilds for transient zone-count changes ──────────────────
var _rebuild_debounce_timer: Timer
var _pending_zone_count: int = -1

var _edit_mode: bool = false
var _hovered_zone: int = -1
var _hovered_row: int = -1

func on_widget_ready(reactive_widget: ReactiveWidget) -> void:
    data = reactive_widget
    _ensure_default_properties()

    var values_field: ReactiveDynamicField = data.properties.value["values"]
    values_field.set_context_provider(_build_script_context)
    values_field.resolved.connect_self_changed(_on_values_changed)
    _on_values_changed(values_field.resolved)

    var widths_field: ReactiveConstantField = data.properties.value["widths"]
    widths_field.set_context_provider(_build_script_context)
    widths_field.resolved.connect_self_changed(_on_widths_changed)
    _on_widths_changed(widths_field.resolved)

    for prop in ["min_value", "max_value", "max_color", "zero_color",
                 "min_color", "no_data_color", "color_curve_exponent"]:
        var field: ReactiveConstantField = data.properties.value[prop]
        field.set_context_provider(_build_script_context)
        field.resolved.connect_self_changed(func(_r: ReactiveVariant) -> void:
            _update_cached_render_properties()
            queue_redraw()
        )

    for prop in ["history_duration_seconds", "sample_interval_seconds"]:
        var field: ReactiveConstantField = data.properties.value[prop]
        field.set_context_provider(_build_script_context)
        field.resolved.connect_self_changed(func(_r: ReactiveVariant) -> void: _rebuild_buffer())

    mouse_filter = Control.MOUSE_FILTER_STOP
    mouse_entered.connect(_on_mouse_entered)
    mouse_exited.connect(_on_mouse_exited)

    # Nearest filtering so 1px-wide source columns don't bleed into
    # neighboring zones when stretched across variable-width rects.
    texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

    _update_cached_render_properties()
    _rebuild_buffer()
    _setup_sample_timer()

func _setup_sample_timer() -> void:
    _sample_timer = Timer.new()
    _sample_timer.one_shot = false
    _sample_timer.process_mode = Node.PROCESS_MODE_ALWAYS
    _sample_timer.wait_time = max(_get_float("sample_interval_seconds", 0.5), 0.05)
    # autostart defers the actual start() call to the Timer's own
    # tree-entry lifecycle, avoiding the "not inside scene tree" race
    # that occurs when on_widget_ready() runs mid-ancestor-_ready().
    _sample_timer.autostart = true
    _sample_timer.timeout.connect(_on_sample_tick)
    add_child(_sample_timer)

func _ensure_default_properties() -> void:
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
    if not data.properties.has_entry("max_color"):
        data.properties.value["max_color"] = ReactiveConstantField.new(Color.LIME_GREEN, data.properties, "max_color")
    if not data.properties.has_entry("zero_color"):
        data.properties.value["zero_color"] = ReactiveConstantField.new(Color.GRAY, data.properties, "zero_color")
    if not data.properties.has_entry("min_color"):
        data.properties.value["min_color"] = ReactiveConstantField.new(Color.CRIMSON, data.properties, "min_color")
    if not data.properties.has_entry("no_data_color"):
        data.properties.value["no_data_color"] = ReactiveConstantField.new(Color(0.5, 0.5, 0.5, 0.35), data.properties, "no_data_color")
    if not data.properties.has_entry("color_curve_exponent"):
        data.properties.value["color_curve_exponent"] = ReactiveConstantField.new(1.0, data.properties, "color_curve_exponent")
    if not data.properties.has_entry("history_duration_seconds"):
        data.properties.value["history_duration_seconds"] = ReactiveConstantField.new(10.0, data.properties, "history_duration_seconds")
    if not data.properties.has_entry("sample_interval_seconds"):
        data.properties.value["sample_interval_seconds"] = ReactiveConstantField.new(0.5, data.properties, "sample_interval_seconds")

func build_properties(builder: WidgetPropertyBuilder) -> void:
    builder.add_dynamic_field("values", "Values", data.properties)
    builder.add_constant_array_field("widths", "Widths", data.properties)
    builder.add_constant_float_field("min_value", "Minimum", data.properties)
    builder.add_constant_float_field("max_value", "Maximum", data.properties)
    builder.add_constant_color_field("max_color", "Maximum Color", data.properties)
    builder.add_constant_color_field("zero_color", "Zero Color", data.properties)
    builder.add_constant_color_field("min_color", "Minimum Color", data.properties)
    builder.add_constant_color_field("no_data_color", "No Data Color", data.properties)
    builder.add_constant_float_field("color_curve_exponent", "Color Curve Exponent", data.properties)
    builder.add_constant_float_field("history_duration_seconds", "History Duration (s)", data.properties)
    builder.add_constant_float_field("sample_interval_seconds", "Sample Interval (s)", data.properties)

func on_edit_mode_changed(enabled: bool) -> void:
    _edit_mode = enabled
    mouse_filter = Control.MOUSE_FILTER_IGNORE if enabled else Control.MOUSE_FILTER_STOP
    if _sample_timer:
        if enabled:
            _sample_timer.paused = true
        else:
            _sample_timer.paused = false
    queue_redraw()

func _build_script_context() -> Dictionary:
    return { "id": data.widget_id }

# ── Helpers (mirrors bar widget conventions) ────────────────────────────
static func _coerce_to_array(v: Variant) -> Array:
    if v == null:
        return []
    if v is Array:
        return v
    return Array(v)

static func _is_numeric(v: Variant) -> bool:
    return v is float or v is int

static func _safe_float(v: Variant, fallback: float = 0.0) -> float:
    return float(v) if _is_numeric(v) else fallback

func _get_float(prop: String, fallback: float) -> float:
    if data == null or not data.properties.has_entry(prop):
        return fallback
    return float(data.properties.value[prop].resolved.value)

# ── Cached render property refresh ───────────────────────────────────────
func _update_cached_render_properties() -> void:
    if data == null:
        return

    var min_v := _get_float("min_value", -10.0)
    var max_v := _get_float("max_value", 10.0)
    # Guard against inverted/degenerate ranges.
    if min_v >= max_v:
        max_v = min_v + 0.0001
    _cached_min_value = min_v
    _cached_max_value = max_v

    _cached_max_color = data.properties.value["max_color"].resolved.value
    _cached_zero_color = data.properties.value["zero_color"].resolved.value
    _cached_min_color = data.properties.value["min_color"].resolved.value
    _cached_no_data_color = data.properties.value["no_data_color"].resolved.value

    # Guard exponent against non-positive values, which would make pow()
    # produce NaN/Inf for t == 0.
    _cached_curve_exponent = max(_get_float("color_curve_exponent", 1.0), 0.01)

# ── Reactive callbacks ───────────────────────────────────────────────────
func _on_values_changed(r: ReactiveVariant) -> void:
    _current_values = _coerce_to_array(r.value)
    _maybe_rebuild_for_zone_count()

func _on_widths_changed(r: ReactiveVariant) -> void:
    _widths = _coerce_to_array(r.value)
    _offsets_dirty = true
    _maybe_rebuild_for_zone_count()

func _resolve_zone_count() -> int:
    if not _widths.is_empty():
        return _widths.size()
    return _current_values.size()

func _maybe_rebuild_for_zone_count() -> void:
    var new_count := _resolve_zone_count()
    if new_count == _zone_count:
        return
    if new_count == 0:
        # Likely a transient state (e.g. "values" briefly empty while a
        # data source reconnects). Ignore momentary blips instead of
        # discarding accumulated history immediately.
        return
    _schedule_rebuild_debounced(new_count)

func _schedule_rebuild_debounced(new_count: int) -> void:
    _pending_zone_count = new_count
    if _rebuild_debounce_timer == null:
        _rebuild_debounce_timer = Timer.new()
        _rebuild_debounce_timer.one_shot = true
        _rebuild_debounce_timer.process_mode = Node.PROCESS_MODE_ALWAYS
        _rebuild_debounce_timer.timeout.connect(_on_rebuild_debounce_timeout)
        add_child(_rebuild_debounce_timer)
    _rebuild_debounce_timer.start(0.15)

func _on_rebuild_debounce_timeout() -> void:
    if _pending_zone_count > 0 and _pending_zone_count != _zone_count:
        _rebuild_buffer()

# ── Buffer management ────────────────────────────────────────────────────
func _rebuild_buffer() -> void:
    _zone_count = max(_resolve_zone_count(), 1)

    var duration := _get_float("history_duration_seconds", 10.0)
    var interval := _get_float("sample_interval_seconds", 0.5)
    _max_rows = max(int(ceil(duration / max(interval, 0.01))), 1)

    _buffer_image_a = Image.create_empty(_zone_count, _max_rows, false, Image.FORMAT_RGBA8)
    _buffer_image_a.fill(Color(0, 0, 0, 0))
    _buffer_image_b = Image.create_empty(_zone_count, _max_rows, false, Image.FORMAT_RGBA8)
    _buffer_image_b.fill(Color(0, 0, 0, 0))
    _active_is_a = true
    _buffer_image = _buffer_image_a
    _buffer_texture = ImageTexture.create_from_image(_buffer_image)

    _offsets_dirty = true

    if _sample_timer:
        _sample_timer.wait_time = max(interval, 0.05)
        # Only re-trigger manually if the timer is fully live but idle
        # (e.g. interval changed after initial autostart already ran).
        if _sample_timer.is_inside_tree() and _sample_timer.is_stopped():
            _sample_timer.start()

    queue_redraw()

func _on_sample_tick() -> void:
    if _buffer_image == null:
        return

    var min_v := _cached_min_value
    var max_v := _cached_max_value
    var safe_max := max_v if not is_zero_approx(max_v) else 0.0001
    var safe_min := min_v if not is_zero_approx(min_v) else -0.0001

    # Double-buffered scroll: write the shifted+updated frame into the
    # inactive image, then swap. This avoids allocating a new Image
    # every tick while still only doing one native blit_rect per tick.
    var src_image := _buffer_image_a if _active_is_a else _buffer_image_b
    var dst_image := _buffer_image_b if _active_is_a else _buffer_image_a

    if _max_rows > 1:
        dst_image.blit_rect(src_image, Rect2i(0, 0, _zone_count, _max_rows - 1), Vector2i(0, 1))

    for x in _zone_count:
        var raw: Variant = _current_values[x] if x < _current_values.size() else null

        var color: Color
        if not _is_numeric(raw):
            color = _cached_no_data_color
        else:
            var value: float = clamp(float(raw), min_v, max_v)
            # Interpolate from zero towards the max or min colour based on
            # the (optionally curved) normalized magnitude of the deviation.
            if value >= 0.0:
                var t: float = clamp(value / safe_max, 0.0, 1.0)
                t = pow(t, _cached_curve_exponent)
                color = _cached_zero_color.lerp(_cached_max_color, t)
            else:
                var t: float = clamp(value / safe_min, 0.0, 1.0)
                t = pow(t, _cached_curve_exponent)
                color = _cached_zero_color.lerp(_cached_min_color, t)

        dst_image.set_pixel(x, 0, color)

    _buffer_image = dst_image
    _active_is_a = not _active_is_a
    _buffer_texture.update(_buffer_image)
    queue_redraw()

# ── Zone/row offset math (mirrors bar widget's _compute_zone_offsets) ────
func _compute_zone_offsets() -> PackedFloat32Array:
    if not _offsets_dirty:
        return _cached_offsets

    var offsets := PackedFloat32Array()
    offsets.resize(_zone_count + 1)
    var w := size.x

    if _widths.size() == _zone_count and _zone_count > 0:
        var total_width := 0.0
        for width in _widths:
            total_width += max(_safe_float(width), 0.0)

        if is_zero_approx(total_width):
            _fill_equal_offsets(offsets, w)
        else:
            var acc := 0.0
            offsets[0] = 0.0
            for i in _zone_count:
                acc += max(_safe_float(_widths[i]), 0.0)
                offsets[i + 1] = (acc / total_width) * w
    else:
        _fill_equal_offsets(offsets, w)

    _cached_offsets = offsets
    _offsets_dirty = false
    return offsets

func _fill_equal_offsets(offsets: PackedFloat32Array, w: float) -> void:
    if _zone_count == 0:
        return
    var bar_width := w / float(_zone_count)
    for i in _zone_count + 1:
        offsets[i] = i * bar_width

func _notification(what: int) -> void:
    if what == NOTIFICATION_RESIZED:
        _offsets_dirty = true

# ── Rendering ─────────────────────────────────────────────────────────────
func _draw() -> void:
    if _buffer_texture == null or _zone_count == 0:
        return

    var offsets := _compute_zone_offsets()
    var h := size.y

    for i in _zone_count:
        var x_start := offsets[i]
        var x_end := offsets[i + 1]
        var zone_width: float = max(x_end - x_start - 1.0, 1.0)

        var src_rect := Rect2(i, 0, 1, _max_rows)
        var dest_rect := Rect2(x_start, 0, zone_width, h)
        draw_texture_rect_region(_buffer_texture, dest_rect, src_rect)

        if i == _hovered_zone:
            draw_rect(dest_rect, Color(1, 1, 1, 0.15))

    if _hovered_row >= 0:
        var row_h := h / float(_max_rows)
        draw_rect(Rect2(0, _hovered_row * row_h, size.x, row_h), Color(1, 1, 1, 0.10))

# ── Interaction (hover highlight only — no tooltip) ─────────────────────
func _gui_input(event: InputEvent) -> void:
    if _edit_mode or _zone_count == 0:
        return

    if event is InputEventMouseMotion:
        var zone := _zone_index_at(event.position.x)
        var row := _row_index_at(event.position.y)
        if zone != _hovered_zone or row != _hovered_row:
            _hovered_zone = zone
            _hovered_row = row
            queue_redraw()

func _on_mouse_entered() -> void:
    pass

func _on_mouse_exited() -> void:
    if _hovered_zone != -1 or _hovered_row != -1:
        _hovered_zone = -1
        _hovered_row = -1
        queue_redraw()

func _zone_index_at(x: float) -> int:
    var offsets := _compute_zone_offsets()
    for i in _zone_count:
        var is_last := i == _zone_count - 1
        if x >= offsets[i] and (x < offsets[i + 1] or (is_last and x <= offsets[i + 1])):
            return i
    return -1

func _row_index_at(y: float) -> int:
    if size.y <= 0.0 or _max_rows <= 0:
        return -1
    var row := int((y / size.y) * _max_rows)
    return clamp(row, 0, _max_rows - 1)
