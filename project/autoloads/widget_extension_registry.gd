extends Node

const SDK_API_VERSION: String  = "1"
const EXTENSIONS_DIR: String   = "user://extensions/"

signal extension_registered(descriptor: WidgetExtensionDescriptor)
signal extension_registration_failed(error: String)

func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(EXTENSIONS_DIR)
	var dir: DirAccess = DirAccess.open(EXTENSIONS_DIR)
	if dir == null:
		LogManager.error("WidgetExtensionRegistry: cannot open '%s' (%s)."
			% [EXTENSIONS_DIR, DirAccess.get_open_error()])
		return

	dir.list_dir_begin()
	var entry: String = dir.get_next()
	while entry != "":
		if not dir.current_is_dir() and entry.get_extension().to_lower() == "zip":
			_register_descriptor(import_extension_zip(EXTENSIONS_DIR.path_join(entry)))
		entry = dir.get_next()
	dir.list_dir_end()

func _register_descriptor(descriptor: WidgetExtensionDescriptor) -> bool:
	if AppState.loaded_widget_extensions.has_entry(descriptor.id):
		return false

	_bake_host_scene(descriptor)

	AppState.loaded_widget_extensions.set_entry(descriptor.id, descriptor)
	extension_registered.emit(descriptor)

	return true

func _bake_host_scene(descriptor: WidgetExtensionDescriptor) -> void:
	var host: PluginWidgetHost = preload("res://widgets/plugin_widget_host.tscn").instantiate()
	host.plugin_id = descriptor.id

	var packed: PackedScene = PackedScene.new()
	if packed.pack(host) == OK:
		descriptor.host_scene = packed
	else:
		LogManager.error("WidgetExtensionRegistry: failed to bake host scene for '%s'." % descriptor.id)

	host.queue_free()

func import_extension_zip(zip_path: String) -> WidgetExtensionDescriptor:
	var reader: ZIPReader = ZIPReader.new()
	if reader.open(zip_path) != OK or not reader.file_exists("manifest.json"):
		LogManager.error("Invalid or unreadable extension package.")
		return null

	var manifest: Variant = JSON.parse_string(
		reader.read_file("manifest.json").get_string_from_utf8()
	)
	if typeof(manifest) != TYPE_DICTIONARY:
		LogManager.error("manifest.json is malformed.")
		reader.close(); return null

	var error: String = _validate_manifest(manifest)
	if error != "":
		LogManager.error(error)
		reader.close(); return null

	var id: String = manifest["id"]
	if AppState.loaded_widget_extensions.has_entry(id):
		LogManager.error("Extension '%s' is already registered." % id)
		reader.close(); return null

	var install_dir: String = EXTENSIONS_DIR.path_join(id)
	if _extract_all(reader, install_dir) != OK:
		LogManager.error("Failed to extract extension files.")
		reader.close(); return null
	reader.close()

	var descriptor: WidgetExtensionDescriptor = _build_descriptor(manifest, install_dir)
	if descriptor == null:
		LogManager.error("Failed to load entry scene for '%s'." % id)
		return null

	_run_plugin_hook(manifest, install_dir)

	return descriptor

## Copies an external .zip into the managed extensions directory, then
## imports and registers it. This ensures the source archive persists
## across restarts so _ready() can rediscover it on next launch.
func install_extension_from_path(source_path: String) -> WidgetExtensionDescriptor:
	var dest_path: String = EXTENSIONS_DIR.path_join(source_path.get_file())

	if ProjectSettings.globalize_path(source_path) != ProjectSettings.globalize_path(dest_path):
		if FileAccess.file_exists(dest_path):
			var msg: String = "A file named '%s' already exists in the extensions folder." \
				% source_path.get_file()
			LogManager.error(msg)
			extension_registration_failed.emit(msg, source_path)
			return null

		var err: Error = DirAccess.copy_absolute(source_path, dest_path)
		if err != OK:
			var msg: String = "Failed to copy extension archive (error %s)." % err
			LogManager.error(msg)
			extension_registration_failed.emit(msg, source_path)
			return null

	var descriptor: WidgetExtensionDescriptor = import_extension_zip(dest_path)
	if descriptor == null:
		return null

	if not _register_descriptor(descriptor):
		var msg: String = "Extension '%s' could not be registered." % descriptor.id
		LogManager.error(msg)
		extension_registration_failed.emit(msg, dest_path)
		return null

	return descriptor

func _validate_manifest(manifest: Dictionary) -> String:
	for key: String in ["id", "name", "version", "api_version", "entry_scene"]:
		if not manifest.has(key) or String(manifest[key]).is_empty():
			return "manifest.json missing required field '%s'." % key
	if String(manifest["api_version"]) != SDK_API_VERSION:
		return "Incompatible api_version '%s' (host supports '%s')." \
			% [manifest["api_version"], SDK_API_VERSION]
	return ""

func _extract_all(reader: ZIPReader, install_dir: String) -> Error:
	DirAccess.make_dir_recursive_absolute(install_dir)
	var real_prefix: String = install_dir  # e.g. "user://extensions/com.vendor.button_widget"

	for path: String in reader.get_files():
		if path.ends_with("/") or path.ends_with(".uid"):
			continue

		var dest: String = install_dir.path_join(path)
		DirAccess.make_dir_recursive_absolute(dest.get_base_dir())

		var file: FileAccess = FileAccess.open(dest, FileAccess.WRITE)
		if file == null:
			return FileAccess.get_open_error()

		if path.ends_with(".tscn") or path.ends_with(".tres") or path.ends_with(".gd"):
			var text: String = reader.read_file(path).get_string_from_utf8()
			text = text.replace("res://__EXT__", real_prefix)
			file.store_string(text)
		else:
			file.store_buffer(reader.read_file(path))

		file.close()
	return OK

func _build_descriptor(manifest: Dictionary, install_dir: String) -> WidgetExtensionDescriptor:
	var scene_path: String = install_dir.path_join(String(manifest["entry_scene"]))
	var content_scene: Resource = ResourceLoader.load(scene_path, "PackedScene")
	if not (content_scene is PackedScene):
		return null

	var probe: Node = (content_scene as PackedScene).instantiate()
	var valid: bool = probe is Control
	probe.queue_free()
	if not valid:
		return null

	var d: WidgetExtensionDescriptor = WidgetExtensionDescriptor.new(manifest)
	return d

func _load_icon(install_dir: String, filename: String) -> Texture2D:
	var path: String = install_dir.path_join(filename)
	if not FileAccess.file_exists(path):
		return null
	var image: Image = Image.new()
	if image.load_svg_from_buffer(FileAccess.get_file_as_bytes(path)) != OK:
		return null
	return ImageTexture.create_from_image(image)

func _run_plugin_hook(manifest: Dictionary, install_dir: String) -> void:
	var plugin_script_name: String = manifest.get("plugin_script", "")
	if plugin_script_name.is_empty():
		return

	var script_path: String = install_dir.path_join(plugin_script_name)
	var script: Script = ResourceLoader.load(script_path) as Script
	if script == null:
		LogManager.error("plugin.gd failed to load or compile at '%s'." % script_path)
		return

	var raw_instance: Object = script.new()
	if raw_instance == null:
		LogManager.error("plugin.gd's script failed to instantiate at '%s'." % script_path)
		return

	var instance: WidgetExtensionPlugin = raw_instance as WidgetExtensionPlugin
	if instance == null:
		LogManager.error(
			"plugin.gd does not extend WidgetExtensionPlugin (got: %s)." \
			% raw_instance.get_script().get_global_name() if raw_instance.get_script() else "unknown script"
		)
		return

	var context: WidgetExtensionContext = WidgetExtensionContext.new(
		self, manifest["id"], install_dir
	)
	instance.on_load(context)
