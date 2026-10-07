extends Button

var data: Object = null

func on_widget_ready(reactive_widget: ReactiveWidget) -> void:
    data = reactive_widget
    if not data.properties.has_entry("label"):
        data.properties.value["label"] = ReactiveDynamicField.new("Button", data.properties, "label")
    if not data.properties.has_entry("on_click"):
        data.properties.value["on_click"] = ReactiveActionBinding.new({}, data.properties, "on_click")

    var label_field: ReactiveDynamicField = data.properties.value["label"]
    label_field.set_context_provider(_build_script_context)
    label_field.resolved.connect_self_changed(_on_label_resolved)
    text = str(label_field.resolved.value)

    if not pressed.is_connected(_on_button_pressed):
        pressed.connect(_on_button_pressed)

func build_properties(builder: WidgetPropertyBuilder) -> void:
    builder.add_dynamic_field("label", "Label", data.properties)
    builder.add_action_field("on_click", "On Click", data.properties)

func on_edit_mode_changed(enabled: bool) -> void:
    disabled = enabled

func _build_script_context() -> Dictionary:
    return { "id": data.widget_id }   # no .value — WidgetDataHandle.widget_id already unwraps it

func _on_label_resolved(r: ReactiveVariant) -> void:
    text = str(r.value)

func _on_button_pressed() -> void:
    var action: ReactiveActionBinding = data.properties.value["on_click"]
    action.execute({ "widget_id": data.widget_id })
