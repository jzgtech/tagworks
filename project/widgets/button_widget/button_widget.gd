extends ReactiveWidget

func _init() -> void:
	pass
	#if not properties.has_entry("label"):
		#var label_field := ReactiveDynamicField.new("Button", properties, "label")
		#label_field.set_context_provider(_build_script_context)
		#properties.value["label"] = label_field
		
	#if not properties.has_entry("on_click"):
		#properties.value["on_click"] = ReactiveActionBinding.new({}, properties, "on_click")

func _build_script_context() -> Dictionary:
	return { "id": widget_id }
