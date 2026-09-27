@tool
extends EditorScript

const SENTINEL: String = "res://__EXT__"
const EXTENSIONS_ROOT: String = "res://extensions"

func _run() -> void:
    DirAccess.make_dir_recursive_absolute("res://dist")

    var extension_ids: Array[String] = _get_extension_ids(EXTENSIONS_ROOT)
    if extension_ids.is_empty():
        push_warning("No extension folders found in %s" % EXTENSIONS_ROOT)
        return

    for extension_id in extension_ids:
        _package_extension(extension_id)

func _get_extension_ids(root: String) -> Array[String]:
    var ids: Array[String] = []
    var dir: DirAccess = DirAccess.open(root)
    if dir == null:
        push_error("Failed to open extensions root: %s" % root)
        return ids

    dir.list_dir_begin()
    var entry: String = dir.get_next()
    while entry != "":
        if entry in [".", "..", ".godot"]:
            entry = dir.get_next()
            continue
        if dir.current_is_dir():
            ids.append(entry)
        entry = dir.get_next()
    dir.list_dir_end()

    return ids

func _package_extension(extension_id: String) -> void:
    var source_dir: String = "%s/%s" % [EXTENSIONS_ROOT, extension_id]
    var output_path: String = "res://dist/%s.zip" % extension_id

    var writer: ZIPPacker = ZIPPacker.new()
    if writer.open(output_path) != OK:
        push_error("Failed to open zip for writing: %s" % output_path)
        return

    _add_dir_recursive(writer, source_dir, "", source_dir)
    writer.close()
    print("Packaged: %s" % output_path)

func _add_dir_recursive(writer: ZIPPacker, abs_dir: String, rel_prefix: String, source_root: String) -> void:
    var dir: DirAccess = DirAccess.open(abs_dir)
    if dir == null:
        push_error("Failed to open directory: %s" % abs_dir)
        return

    dir.list_dir_begin()
    var entry: String = dir.get_next()
    while entry != "":
        if entry in [".", "..", ".godot", ".import"]:
            entry = dir.get_next()
            continue

        if entry.get_extension() == "uid":
            entry = dir.get_next()
            continue

        var abs_path: String = abs_dir.path_join(entry)
        var rel_path: String = rel_prefix.path_join(entry) if rel_prefix != "" else entry

        if dir.current_is_dir():
            _add_dir_recursive(writer, abs_path, rel_path, source_root)
        else:
            _write_entry(writer, abs_path, rel_path, source_root)

        entry = dir.get_next()
    dir.list_dir_end()

func _write_entry(writer: ZIPPacker, abs_path: String, rel_path: String, source_root: String) -> void:
    writer.start_file(rel_path)

    if rel_path.ends_with(".tscn") or rel_path.ends_with(".tres") or rel_path.ends_with(".gd"):
        var text: String = FileAccess.get_file_as_string(abs_path)
        text = text.replace(source_root, SENTINEL)
        text = _strip_uid_attributes(text)
        writer.write_file(text.to_utf8_buffer())
    else:
        writer.write_file(FileAccess.get_file_as_bytes(abs_path))

    writer.close_file()

func _strip_uid_attributes(text: String) -> String:
    var regex: RegEx = RegEx.new()
    regex.compile("\\s*uid=\"uid://[a-z0-9]+\"")
    return regex.sub(text, "", true)
