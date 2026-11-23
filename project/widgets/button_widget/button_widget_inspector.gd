extends VBoxContainer

var data: ReactiveWidget = null

func bind(reactive_widget: ReactiveWidget) -> void:
	data = reactive_widget
	
	var label_field: ReactiveDynamicField = data.properties.value["label"]
	var click_action: ReactiveActionBinding = data.properties.value["on_click"]
	
	# 1. Build your Properties section (e.g., using your InspectorCategory scene)
	#    and bind your text/formula input control to `label_field`
	
	# 2. Build your Events section (e.g., using your InspectorCategory scene)
	#    and bind your action binding editor control to `click_action`

func _exit_tree() -> void:
	# Disconnect any listeners attached to `data.properties` fields here
	# before this inspector node is freed on deselection
	pass
