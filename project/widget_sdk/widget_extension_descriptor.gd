# widget_extension_descriptor.gd
class_name WidgetExtensionDescriptor
extends RefCounted

var id: String
var display_name: String
var version: String
var is_container: bool
var author: String
var description: String
var icon: Texture2D
var install_path: String

var backend_script: Script
var content_scene: PackedScene
var inspector_scene: PackedScene # Optional (null if widget has no inspector)

func _init(manifest: Dictionary = {}) -> void:
	if manifest.is_empty():
		return
	parse_manifest_data(manifest)

func parse_manifest_data(manifest: Dictionary) -> void:
	id = String(manifest.get("id", ""))
	display_name = String(manifest.get("name", ""))
	version = String(manifest.get("version", "1.0.0"))
	is_container = bool(manifest.get("is_container", false))
	author = String(manifest.get("author", ""))
	description = String(manifest.get("description", ""))

## Host-driven factory helpers
func create_backend() -> ReactiveWidget:
	if backend_script and backend_script.can_instantiate():
		return backend_script.new() as ReactiveWidget
	return null

func create_content(backend: ReactiveWidget) -> Control:
	if content_scene == null:
		return null
	var node: Control = content_scene.instantiate() as Control
	if node and node.has_method("bind"):
		node.bind(backend)
	return node

func create_inspector(backend: ReactiveWidget) -> Control:
	if inspector_scene == null:
		return null
	var node: Control = inspector_scene.instantiate() as Control
	if node and node.has_method("bind"):
		node.bind(backend)
	return node
