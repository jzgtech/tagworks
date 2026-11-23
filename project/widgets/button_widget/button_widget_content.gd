extends Button

var data: ReactiveWidget = null
var _label_field: ReactiveDynamicField = null

func bind(reactive_widget: ReactiveWidget) -> void:
	data = reactive_widget
	
	_label_field = data.properties.value["label"]
	_label_field.resolved.connect_self_changed(_on_label_resolved)
	text = str(_label_field.resolved.value)

	if not pressed.is_connected(_on_button_pressed):
		pressed.connect(_on_button_pressed)

func _exit_tree() -> void:
	# Clean up signal listener if the content node is freed
	if _label_field and _label_field.resolved.is_connected_self_changed(_on_label_resolved):
		_label_field.resolved.disconnect_self_changed(_on_label_resolved)

func on_edit_mode_changed(enabled: bool) -> void:
	disabled = enabled

func _on_label_resolved(r: ReactiveVariant) -> void:
	text = str(r.value)

func _on_button_pressed() -> void:
	var action: ReactiveActionBinding = data.properties.value["on_click"]
	action.execute({ "widget_id": data.widget_id })
