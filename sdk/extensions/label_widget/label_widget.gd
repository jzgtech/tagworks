extends Label

var data: Object = null

func on_widget_ready(reactive_widget: ReactiveWidget) -> void:
    data = reactive_widget
    if not data.properties.has_entry("label"):
        data.properties.value["label"] = ReactiveDynamicField.new("Label", data.properties, "label")

    var label_field: ReactiveDynamicField = data.properties.value["label"]
    label_field.set_context_provider(_build_script_context)
    label_field.resolved.connect_self_changed(_on_label_resolved)
    text = str(label_field.resolved.value)

func build_properties(builder: WidgetPropertyBuilder) -> void:
    builder.add_dynamic_field("label", "Label", data.properties)

func on_edit_mode_changed(enabled: bool) -> void:
    # Labels have no "disabled" state; toggle mouse interaction instead
    mouse_filter = Control.MOUSE_FILTER_IGNORE if enabled else Control.MOUSE_FILTER_STOP

func _build_script_context() -> Dictionary:
    return { "id": data.widget_id }

func _on_label_resolved(r: ReactiveVariant) -> void:
    text = str(r.value)
