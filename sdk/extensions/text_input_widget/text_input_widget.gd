extends LineEdit

var data: Object = null

func on_widget_ready(reactive_widget: ReactiveWidget) -> void:
    data = reactive_widget
    if not data.properties.has_entry("value"):
        data.properties.value["value"] = ReactiveDynamicField.new("", data.properties, "value")
    if not data.properties.has_entry("placeholder"):
        data.properties.value["placeholder"] = ReactiveDynamicField.new("Enter text", data.properties, "placeholder")
    if not data.properties.has_entry("on_change"):
        data.properties.value["on_change"] = ReactiveActionBinding.new({}, data.properties, "on_change")
    if not data.properties.has_entry("on_submit"):
        data.properties.value["on_submit"] = ReactiveActionBinding.new({}, data.properties, "on_submit")

    var value_field: ReactiveDynamicField = data.properties.value["value"]
    value_field.set_context_provider(_build_script_context)
    value_field.resolved.connect_self_changed(_on_value_resolved)
    text = str(value_field.resolved.value)

    var placeholder_field: ReactiveDynamicField = data.properties.value["placeholder"]
    placeholder_field.set_context_provider(_build_script_context)
    placeholder_field.resolved.connect_self_changed(_on_placeholder_resolved)
    placeholder_text = str(placeholder_field.resolved.value)

    if not text_changed.is_connected(_on_text_changed):
        text_changed.connect(_on_text_changed)
    if not text_submitted.is_connected(_on_text_submitted):
        text_submitted.connect(_on_text_submitted)

func build_properties(builder: WidgetPropertyBuilder) -> void:
    builder.add_dynamic_field("value", "Value", data.properties)
    builder.add_dynamic_field("placeholder", "Placeholder", data.properties)
    builder.add_action_field("on_change", "On Change", data.properties)
    builder.add_action_field("on_submit", "On Submit", data.properties)

func on_edit_mode_changed(enabled: bool) -> void:
    editable = not enabled

func _build_script_context() -> Dictionary:
    return { "id": data.widget_id }   # no .value — WidgetDataHandle.widget_id already unwraps it

func _on_value_resolved(r: ReactiveVariant) -> void:
    text = str(r.value)

func _on_placeholder_resolved(r: ReactiveVariant) -> void:
    placeholder_text = str(r.value)

func _on_text_changed(new_text: String) -> void:
    var action: ReactiveActionBinding = data.properties.value["on_change"]
    action.execute({ "widget_id": data.widget_id, "value": new_text })

func _on_text_submitted(new_text: String) -> void:
    var action: ReactiveActionBinding = data.properties.value["on_submit"]
    action.execute({ "widget_id": data.widget_id, "value": new_text })
