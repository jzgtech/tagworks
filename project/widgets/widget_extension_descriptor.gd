# widget_extension_descriptor.gd
class_name WidgetExtensionDescriptor
extends RefCounted

var id: String
var display_name: String
var version: String
var is_container: bool
var icon: Texture2D
var content_scene: PackedScene
var install_path: String
var host_scene: PackedScene

## Holds the configuration schemas for properties parsed from the manifest
var properties: Array[Dictionary] = []
## Holds the event hooks exposed by this widget parsed from the manifest
var events: Array[Dictionary] = []

func _init(manifest: Dictionary = {}) -> void:
	if manifest.is_empty():
		return
	parse_manifest_data(manifest)

## Helper method to populate this descriptor from your raw parsed manifest Dictionary
func parse_manifest_data(manifest: Dictionary) -> void:
	id = manifest.get("id", "")
	display_name = manifest.get("name", "")
	version = manifest.get("version", "1.0.0")
	is_container = manifest.get("is_container", false)
	
	# Clear out existing arrays in case of re-initialization
	properties.clear()
	events.clear()
	
	# Safely extract and store properties schema arrays
	if manifest.has("properties") and manifest["properties"] is Array:
		for prop: Variant in manifest["properties"]:
			if prop is Dictionary:
				properties.append(prop)
				
	# Safely extract and store events schema arrays
	if manifest.has("events") and manifest["events"] is Array:
		for event: Variant in manifest["events"]:
			if event is Dictionary:
				events.append(event)
