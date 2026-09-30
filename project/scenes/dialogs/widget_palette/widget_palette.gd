class_name WidgetPalette
extends PanelContainer

@onready var search_bar:   LineEdit  = %SearchBar
@onready var palette_list: ItemList  = %PaletteList
#@onready var cancel_btn:   Button    = %Button

# Keep track of active descriptors matching the current search
var _filtered_descriptors: Array[WidgetExtensionDescriptor] = []

func _ready() -> void:
	_rebuild_palette()
	AppState.loaded_widget_extensions.connect_self_changed(_on_loaded_widget_extensions_changed)
	
	# Connect new search and item list signals
	search_bar.text_changed.connect(_on_search_text_changed)
	palette_list.item_activated.connect(_on_item_activated)
	
	#cancel_btn.pressed.connect(_on_cancel_pressed)

func _on_loaded_widget_extensions_changed(_extensions: ReactiveDictionary) -> void:
	_rebuild_palette()

func _rebuild_palette() -> void:
	palette_list.clear()
	_filtered_descriptors.clear()

	var descriptors: Array = AppState.loaded_widget_extensions.value.values()
	
	# Sort everything alphabetically first
	descriptors.sort_custom(func(a: WidgetExtensionDescriptor, b: WidgetExtensionDescriptor) -> bool:
		return a.display_name < b.display_name
	)

	var filter_text: String = search_bar.text.strip_edges().to_lower()

	for descriptor: WidgetExtensionDescriptor in descriptors:
		if descriptor.host_scene == null:
			continue  # Not yet baked into a spawnable scene

		# Apply LineEdit filter if text is typed
		if not filter_text.is_empty() and not descriptor.display_name.to_lower().contains(filter_text):
			continue

		# Add to UI list
		var idx: int = palette_list.add_item(descriptor.display_name)
		if descriptor.icon != null:
			palette_list.set_item_icon(idx, descriptor.icon)
		
		# Track the mapping between UI index and data descriptor
		_filtered_descriptors.append(descriptor)

func _on_search_text_changed(_new_text: String) -> void:
	_rebuild_palette()

func _on_item_activated(index: int) -> void:
	if index >= 0 and index < _filtered_descriptors.size():
		var descriptor: WidgetExtensionDescriptor = _filtered_descriptors[index]
		IntentBus.add_widget_requested.emit(descriptor.host_scene)

func _on_cancel_pressed() -> void:
	hide()
