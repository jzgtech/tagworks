class_name WidgetPropertyBuilder
extends RefCounted

## Builds the property/event editor rows for a widget's inspector panel.
##
## Responsibilities:
##  - Routes rows into the "Properties" or "Events" tab depending on which
##    add_* method is called (widget scripts never specify a tab directly).
##  - Renders a per-row source dropdown (Constant / Script / OPC Tag /
##    OPC Tags per-zone) scoped to what the given field type supports.
##  - Provides array-aware editors (add/remove rows) for both constant
##    arrays and per-zone OPC tag arrays.
##
## NOTE: `_build_tag_binding_editor()` assumes AppState.current_project
## exposes `opc_ua_servers` / `subscriptions` / `tags` as dictionary-like
## containers with `.value` (Dictionary) and `.get_entry(id)`. Adjust the
## population logic below if your ReactiveProject API differs.

const LABEL_MIN_WIDTH: int = 100

var _panel: Object  # exposes ._properties and ._events (Control containers)

func _init(panel: Object) -> void:
	_panel = panel

# ══════════════════════════════════════════════════════════════════════════
# PUBLIC API — called from widget scripts' build_properties()
# ══════════════════════════════════════════════════════════════════════════

func add_dynamic_field(prop: String, lbl: String, props: ReactiveDictionary) -> void:
	var field: ReactiveDynamicField = props.value[prop]
	var is_vector: bool = field.is_vector_field()

	var factories: Dictionary = {
		ReactiveDynamicField.SourceType.CONSTANT: (
			_constant_array_editor_factory(field) if is_vector
			else _constant_auto_editor_factory(field)
		),
		ReactiveDynamicField.SourceType.SCRIPT: _script_editor_factory(field),
		ReactiveDynamicField.SourceType.OPC_TAG: _tag_editor_factory(field.tag_binding),
	}
	if is_vector:
		factories[ReactiveDynamicField.SourceType.OPC_TAG_ARRAY] = _tag_array_editor_factory(field)

	_build_field_row(lbl, field, factories, _panel._properties)

func add_constant_color_field(prop: String, lbl: String, props: ReactiveDictionary) -> void:
	_add_simple_constant_field(prop, lbl, props, _constant_color_editor_factory)

func add_constant_float_field(prop: String, lbl: String, props: ReactiveDictionary) -> void:
	_add_simple_constant_field(prop, lbl, props, _constant_float_editor_factory)

func add_constant_string_field(prop: String, lbl: String, props: ReactiveDictionary) -> void:
	_add_simple_constant_field(prop, lbl, props, _constant_string_editor_factory)

func add_constant_bool_field(prop: String, lbl: String, props: ReactiveDictionary) -> void:
	_add_simple_constant_field(prop, lbl, props, _constant_bool_editor_factory)

func add_constant_array_field(prop: String, lbl: String, props: ReactiveDictionary) -> void:
	_add_simple_constant_field(prop, lbl, props, _constant_array_editor_factory)

## Shared by every scalar/array constant field: only the value-editor
## factory differs, the CONSTANT + SCRIPT source wiring is identical.
func _add_simple_constant_field(
	prop: String,
	lbl: String,
	props: ReactiveDictionary,
	constant_factory: Callable
) -> void:
	var field: ReactiveConstantField = props.value[prop]
	var factories: Dictionary = {
		ReactiveConstantField.SourceType.CONSTANT: constant_factory.call(field),
		ReactiveConstantField.SourceType.SCRIPT: _script_editor_factory(field),
	}
	_build_field_row(lbl, field, factories, _panel._properties)

func add_action_field(prop: String, lbl: String, props: ReactiveDictionary) -> void:
	var action: ReactiveActionBinding = props.value[prop]

	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.add_child(_make_label(lbl))

	var editor: Control = _build_action_binding_editor(action)
	editor.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(editor)

	_panel._events.add_child(row)
	_panel._events.add_child(HSeparator.new())

# ══════════════════════════════════════════════════════════════════════════
# GENERIC ROW SCAFFOLDING (label + source dropdown + swappable body)
# ══════════════════════════════════════════════════════════════════════════

func _build_field_row(
	label_text: String,
	field: Object,
	editor_factories: Dictionary,
	container: Control
) -> void:
	var wrapper: HBoxContainer = HBoxContainer.new()
	wrapper.add_theme_constant_override("separation", 8)

	wrapper.add_child(_make_label(label_text))

	var body: MarginContainer = MarginContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var rebuild_body: Callable = func(_origin: Reactive) -> void:
		_rebuild_body(body, field, editor_factories)

	_bind_reactive_listener(wrapper, field.source_type, field.source_type.connect_self_changed, rebuild_body)

	_rebuild_body(body, field, editor_factories)

	wrapper.add_child(body)
	wrapper.add_child(_make_source_dropdown(field))

	container.add_child(wrapper)
	container.add_child(HSeparator.new())


func _make_label(text: String) -> Label:
	var label: Label = Label.new()
	label.text = text
	label.custom_minimum_size.x = LABEL_MIN_WIDTH
	label.size_flags_vertical = Control.SIZE_SHRINK_BEGIN  # top-align in the row
	return label


func _rebuild_body(
	body: Container,
	field: Object,
	editor_factories: Dictionary
) -> void:
	if not is_instance_valid(body):
		return

	for child: Node in body.get_children():
		child.queue_free()

	var factory: Callable = editor_factories.get(field.source_type.value, Callable())
	if factory.is_valid():
		body.add_child(factory.call())


## Connects `listener` via `connect_method` (e.g. a reactive field's
## `connect_self_changed`) and guarantees it is disconnected the moment
## `node` leaves the tree — preventing leaked listeners on long-lived
## reactive objects across repeated panel rebuilds. Disconnection is done
## against `reactive_source.reactive_changed`, which every supported
## connect_* variant is assumed to funnel into.
func _bind_reactive_listener(
	node: Node,
	reactive_source: Object,
	connect_method: Callable,
	listener: Callable
) -> void:
	connect_method.call(listener)
	node.tree_exiting.connect(func() -> void:
		if reactive_source.reactive_changed.is_connected(listener):
			reactive_source.reactive_changed.disconnect(listener)
	)


func _make_source_dropdown(field: Object) -> MenuButton:
	var btn: MenuButton = MenuButton.new()
	btn.text = "⚙"

	var popup: PopupMenu = btn.get_popup()
	popup.clear()

	var is_dynamic: bool = field is ReactiveDynamicField
	var is_vector: bool = field.is_vector_field()

	# Enum values are used directly as popup item IDs — no separate
	# id → SourceType lookup table required.
	popup.add_item("Constant", field.SourceType.CONSTANT)
	popup.add_item("Script", field.SourceType.SCRIPT)

	if is_dynamic:
		popup.add_item("OPC Tag (native array)" if is_vector else "OPC Tag", field.SourceType.OPC_TAG)
		if is_vector:
			popup.add_item("OPC Tags (per zone)", field.SourceType.OPC_TAG_ARRAY)

	var refresh_tooltip: Callable = func() -> void:
		btn.tooltip_text = "Data source: %s" % _source_type_display_name(field)
	refresh_tooltip.call()

	popup.id_pressed.connect(func(id: int) -> void:
		field.source_type.value = id
		refresh_tooltip.call()
	)

	return btn


func _source_type_display_name(field: Object) -> String:
	var is_dynamic: bool = field is ReactiveDynamicField
	match field.source_type.value:
		field.SourceType.CONSTANT: return "Constant"
		field.SourceType.SCRIPT: return "Script"
		field.SourceType.OPC_TAG: return "OPC Tag" if is_dynamic else "Unknown"
		field.SourceType.OPC_TAG_ARRAY: return "OPC Tags (per zone)"
		_: return "Unknown"

# ══════════════════════════════════════════════════════════════════════════
# SCALAR CONSTANT EDITORS
# ══════════════════════════════════════════════════════════════════════════

func _constant_color_editor_factory(field: Object) -> Callable:
	return func() -> Control:
		var picker: ColorPickerButton = ColorPickerButton.new()
		picker.color = field.constant_value.value
		picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		picker.custom_minimum_size.y = 32
		picker.color_changed.connect(func(v: Color) -> void: field.constant_value.value = v)
		return picker

func _constant_float_editor_factory(field: Object) -> Callable:
	return func() -> Control:
		var spin: SpinBox = _make_float_spinbox(float(field.constant_value.value))
		spin.value_changed.connect(func(v: float) -> void: field.constant_value.value = v)
		return spin

func _constant_string_editor_factory(field: Object) -> Callable:
	return func() -> Control:
		var edit: LineEdit = LineEdit.new()
		edit.text = str(field.constant_value.value)
		edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		edit.text_changed.connect(func(v: String) -> void: field.constant_value.value = v)
		return edit

func _constant_bool_editor_factory(field: Object) -> Callable:
	return func() -> Control:
		var check: CheckBox = CheckBox.new()
		check.button_pressed = bool(field.constant_value.value)
		check.toggled.connect(func(v: bool) -> void: field.constant_value.value = v)
		return check

# Fallback used by add_dynamic_field for non-vector fields whose underlying
# type isn't known ahead of time — inspects the current resolved value to
# pick a reasonable editor. Prefer the explicit add_constant_*_field
# variants when the type is known statically.
func _constant_auto_editor_factory(field: Object) -> Callable:
	var v: Variant = field.constant_value.value
	if v is Color:
		return _constant_color_editor_factory(field)
	if v is bool:
		return _constant_bool_editor_factory(field)
	if v is String:
		return _constant_string_editor_factory(field)
	return _constant_float_editor_factory(field)


func _make_float_spinbox(value: float) -> SpinBox:
	var spin: SpinBox = SpinBox.new()
	spin.min_value = -1000000.0
	spin.max_value = 1000000.0
	spin.step = 0.01
	spin.allow_greater = true
	spin.allow_lesser = true
	spin.value = value
	spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return spin

# ══════════════════════════════════════════════════════════════════════════
# ARRAY (CONSTANT) EDITOR — add/remove rows, per-value editing
# ══════════════════════════════════════════════════════════════════════════

func _constant_array_editor_factory(field: Object) -> Callable:
	return func() -> Control:
		var list: VBoxContainer = VBoxContainer.new()
		var rows: VBoxContainer = VBoxContainer.new()
		var arr: Array = Array(field.constant_value.value) if field.constant_value.value != null else []

		var rebuild_ref: Array = [Callable()]
		rebuild_ref[0] = func() -> void:
			for c : Node in rows.get_children():
				c.queue_free()
			for i : int in arr.size():
				rows.add_child(_build_constant_array_row(arr, i, field, rebuild_ref[0]))

		var footer: HBoxContainer = HBoxContainer.new()

		var add_btn: Button = Button.new()
		add_btn.text = "Add Zone"
		add_btn.pressed.connect(func() -> void:
			arr.append(0.0)
			field.constant_value.value = field.rebuild_typed_array(arr)
			rebuild_ref[0].call()
		)

		var fill_btn: Button = Button.new()
		fill_btn.text = "Set All Equal"
		fill_btn.pressed.connect(func() -> void:
			for i : int in arr.size():
				arr[i] = 1.0
			field.constant_value.value = field.rebuild_typed_array(arr)
			rebuild_ref[0].call()
		)

		var clear_btn: Button = Button.new()
		clear_btn.text = "Clear"
		clear_btn.pressed.connect(func() -> void:
			arr.clear()
			field.constant_value.value = field.rebuild_typed_array(arr)
			rebuild_ref[0].call()
		)

		footer.add_child(add_btn)
		footer.add_child(fill_btn)
		footer.add_child(clear_btn)

		rebuild_ref[0].call()
		list.add_child(rows)
		list.add_child(footer)
		return list


func _build_constant_array_row(arr: Array, index: int, field: Object, rebuild: Callable) -> Control:
	var row: HBoxContainer = HBoxContainer.new()

	var idx_label: Label = Label.new()
	idx_label.text = "Zone %d" % index
	idx_label.custom_minimum_size.x = 60
	row.add_child(idx_label)

	var spin: SpinBox = _make_float_spinbox(float(arr[index]))
	spin.value_changed.connect(func(v: float) -> void:
		arr[index] = v
		field.constant_value.value = field.rebuild_typed_array(arr)
	)
	row.add_child(spin)

	var remove_btn: Button = Button.new()
	remove_btn.text = "✕"
	remove_btn.pressed.connect(func() -> void:
		arr.remove_at(index)
		field.constant_value.value = field.rebuild_typed_array(arr)
		rebuild.call()
	)
	row.add_child(remove_btn)

	return row

# ══════════════════════════════════════════════════════════════════════════
# SCRIPT EDITOR — shared by constant + dynamic, scalar + vector fields
# ══════════════════════════════════════════════════════════════════════════

func _script_editor_factory(field: Object) -> Callable:
	return func() -> Control:
		var wrapper: VBoxContainer = VBoxContainer.new()

		var edit: TextEdit = TextEdit.new()
		edit.custom_minimum_size = Vector2(220, 60)
		edit.text = field.script_source.value
		edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY

		var status: Label = Label.new()
		status.modulate = Color.CRIMSON

		edit.text_changed.connect(func() -> void:
			field.script_source.value = edit.text
			status.text = "" if field.resolved.value != null else "Script did not resolve — check syntax"
		)

		wrapper.add_child(edit)
		wrapper.add_child(status)
		return wrapper

# ══════════════════════════════════════════════════════════════════════════
# SINGLE OPC TAG EDITOR — used by scalar OPC_TAG and per-zone tag rows
# ══════════════════════════════════════════════════════════════════════════

func _tag_editor_factory(binding: ReactiveOpcUaTagBinding) -> Callable:
	return func() -> Control:
		return _build_tag_binding_editor(binding)

func _build_tag_binding_editor(binding: ReactiveOpcUaTagBinding) -> Control:
	var row: HFlowContainer = HFlowContainer.new()

	var server_select: OptionButton = OptionButton.new()
	var subscription_select: OptionButton = OptionButton.new()
	var tag_select: OptionButton = OptionButton.new()

	for o : Control in [server_select, subscription_select, tag_select]:
		o.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var project: ReactiveProject = AppState.current_project

	var populate_servers: Callable = func() -> void:
		var ids: Array = project.opc_ua_servers.value.keys() if project != null else []
		_populate_option_button(server_select, ids, "— Select Server —", binding.server_id.value)

	var populate_subscriptions: Callable
	var populate_tags: Callable

	populate_subscriptions = func() -> void:
		var ids: Array = []
		if project != null and not binding.server_id.value.is_empty():
			var server: ReactiveOpcUaServer = project.opc_ua_servers.get_entry(binding.server_id.value)
			if server != null:
				ids = server.subscriptions.value.keys()
		_populate_option_button(subscription_select, ids, "— Select Subscription —", binding.subscription_id.value)

	populate_tags = func() -> void:
		var ids: Array = []
		if project != null and not binding.server_id.value.is_empty() and not binding.subscription_id.value.is_empty():
			var server: ReactiveOpcUaServer = project.opc_ua_servers.get_entry(binding.server_id.value)
			if server != null:
				var subscription: ReactiveOpcUaSubscription = server.subscriptions.get_entry(binding.subscription_id.value)
				if subscription != null:
					ids = subscription.tags.value.keys()
		_populate_option_button(tag_select, ids, "— Select Tag —", binding.tag_id.value)

	server_select.item_selected.connect(func(idx: int) -> void:
		var meta: Variant = server_select.get_item_metadata(idx)
		binding.server_id.value = str(meta) if meta != null else ""
		binding.subscription_id.value = ""
		binding.tag_id.value = ""
		populate_subscriptions.call()
		populate_tags.call()
	)

	subscription_select.item_selected.connect(func(idx: int) -> void:
		var meta: Variant = subscription_select.get_item_metadata(idx)
		binding.subscription_id.value = str(meta) if meta != null else ""
		binding.tag_id.value = ""
		populate_tags.call()
	)

	tag_select.item_selected.connect(func(idx: int) -> void:
		var meta: Variant = tag_select.get_item_metadata(idx)
		binding.tag_id.value = str(meta) if meta != null else ""
	)

	populate_servers.call()
	populate_subscriptions.call()
	populate_tags.call()

	row.add_child(server_select)
	row.add_child(subscription_select)
	row.add_child(tag_select)
	return row


## Fills `option` with a "— Select … —" placeholder followed by one item
## per entry in `ids` (stringified, stored as item metadata), then
## re-selects whichever item's metadata matches `target` (or the
## placeholder if `target` is empty / not found).
func _populate_option_button(
	option: OptionButton,
	ids: Array,
	placeholder: String,
	target: String
) -> void:
	option.clear()
	option.add_item(placeholder, -1)
	for i : int in ids.size():
		option.add_item(str(ids[i]), i)
		option.set_item_metadata(i + 1, ids[i])
	_select_option_by_metadata(option, target)


func _select_option_by_metadata(option: OptionButton, target: String) -> void:
	if target.is_empty():
		option.select(0)
		return
	for i : int in option.item_count:
		if str(option.get_item_metadata(i)) == target:
			option.select(i)
			return
	option.select(0)

# ══════════════════════════════════════════════════════════════════════════
# PER-ZONE OPC TAG ARRAY EDITOR — "connect tags to array properties"
# ══════════════════════════════════════════════════════════════════════════

func _tag_array_editor_factory(field: ReactiveDynamicField) -> Callable:
	return func() -> Control:
		var list: VBoxContainer = VBoxContainer.new()
		var rows: VBoxContainer = VBoxContainer.new()
		var binding: ReactiveOpcUaTagArrayBinding = field.tag_array_binding

		# `rebuild` must call itself (each row's remove button calls back
		# into it). A plain `var rebuild: Callable; rebuild = func() ...`
		# would capture `rebuild` by value at closure-creation time —
		# before the assignment finishes — leaving every nested call
		# holding a stale, invalid Callable that crashes on invoke.
		# Wrapping it in a single-element Array sidesteps this, since
		# Arrays are captured by reference and reflect later mutation.
		var rebuild_ref: Array = [Callable()]
		rebuild_ref[0] = func() -> void:
			if not is_instance_valid(rows):
				return
			for c : Node in rows.get_children():
				c.queue_free()
			for i : int in binding.tag_bindings.value.size():
				rows.add_child(_build_tag_array_row(binding, i, rebuild_ref[0]))

		var on_tag_bindings_changed: Callable = func(_origin: ReactiveArray) -> void: rebuild_ref[0].call()
		_bind_reactive_listener(
			list, binding.tag_bindings, binding.tag_bindings.connect_any_changed_self, on_tag_bindings_changed
		)

		var add_btn: Button = Button.new()
		add_btn.text = "Add Zone Tag"
		add_btn.pressed.connect(func() -> void:
			binding.add_tag("", "", "")
		)

		rebuild_ref[0].call()
		list.add_child(rows)
		list.add_child(add_btn)
		return list

func _build_tag_array_row(binding: ReactiveOpcUaTagArrayBinding, index: int, rebuild: Callable) -> Control:
	var row: HBoxContainer = HBoxContainer.new()

	var idx_label: Label = Label.new()
	idx_label.text = "Zone %d" % index
	idx_label.custom_minimum_size.x = 60
	row.add_child(idx_label)

	var picker: Control = _build_tag_binding_editor(binding.tag_bindings.value[index])
	picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(picker)

	var remove_btn: Button = Button.new()
	remove_btn.text = "✕"
	remove_btn.pressed.connect(func() -> void:
		binding.remove_tag(index)
		rebuild.call()
	)
	row.add_child(remove_btn)

	return row

# ══════════════════════════════════════════════════════════════════════════
# ACTION BINDING EDITOR (Events tab)
# ══════════════════════════════════════════════════════════════════════════

## NOTE: This assumes ReactiveActionBinding exposes an `action_type`
## (ReactiveInt) and a `script_source` (ReactiveString) similar in spirit to
## ReactiveDynamicField. Adjust field names below to match your actual
## ReactiveActionBinding implementation.
func _build_action_binding_editor(action: ReactiveActionBinding) -> Control:
	var wrapper: VBoxContainer = VBoxContainer.new()

	var edit: TextEdit = TextEdit.new()
	edit.custom_minimum_size = Vector2(220, 50)
	edit.text = action.script_source.value if "script_source" in action else ""
	edit.placeholder_text = "e.g. Widgets.get(\"detail_panel\").set_visible(true)"

	edit.text_changed.connect(func() -> void:
		if "script_source" in action:
			action.script_source.value = edit.text
	)

	wrapper.add_child(edit)
	return wrapper
