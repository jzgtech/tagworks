extends Node

const SAVE_DIR     :String = "user://projects/"
const FILE_VERSION :int    = 2

const PROJECT_FILE_FILTER: PackedStringArray = ["*.json ; Project Files"]

var project: ReactiveProject = null

## Reactive status owned exclusively by ProjectManager — the single
## source of truth for the outcome of the last load/save attempt.
## Success is observed separately via AppState.current_project.is_loaded.
var last_error: ReactiveString = ReactiveString.new("")

# ── Lifecycle ─────────────────────────────────────────────────────────────────

func _ready() -> void:
	IntentBus.new_project_requested.connect(_on_new_project_requested)
	IntentBus.save_project_requested.connect(_on_save_project_requested)
	IntentBus.save_project_as_requested.connect(_on_save_project_as_requested)
	IntentBus.open_project_requested.connect(_on_open_project_requested)
	IntentBus.open_project_transfer_dialog_requested.connect(_on_open_project_transfer_dialog_requested)
	IntentBus.close_project_requested.connect(_on_close_project_requested)
	IntentBus.open_project_dialog_requested.connect(_on_open_project_dialog_requested)
	IntentBus.save_project_as_dialog_requested.connect(_on_save_project_as_dialog_requested)

# ── Helpers ───────────────────────────────────────────────────────────────────

func has_active_project() -> bool:
	return not AppState.current_project.value.file_path.value.is_empty()

func get_current_project_path() -> String:
	return AppState.current_project.value.file_path.value

# ── IntentBus Handlers ────────────────────────────────────────────────────────

func _on_new_project_requested() -> void:
	last_error.value = ""
	AppState.new_project()


func _on_save_project_requested() -> void:
	if AppState.current_project.file_path.value.is_empty():
		_on_save_project_as_dialog_requested()
		return
	_save(AppState.current_project.file_path.value)


func _on_save_project_as_requested(path: String) -> void:
	_save(path)


func _on_open_project_requested(path: String) -> void:
	last_error.value = ""

	if not FileAccess.file_exists(path):
		_fail("Project file not found: %s" % path)
		return

	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		_fail("Failed to open file for reading: %s" % path)
		return

	var payload: Variant = JSON.parse_string(file.get_as_text())
	file.close()

	if not payload is Dictionary:
		_fail("Invalid project file format.")
		return

	AppState.load_project(payload)

	if AppState.current_project.is_loaded.value:
		AppState.current_project.file_path.value = path
		RecentProjects.add(path, AppState.current_project.project_name.value)
	else:
		_fail("Project failed to initialize after loading.")


func _on_close_project_requested() -> void:
	AppState.close_project()


func _fail(reason: String) -> void:
	push_warning("ProjectManager: %s" % reason)
	last_error.value = reason

# ── File Dialogs ──────────────────────────────────────────────────────────────

func _on_open_project_dialog_requested() -> void:
	_ensure_save_dir()

	WindowManager.open_window("filedialog", {
		"params": {
			"title":       "Open Project",
			"file_mode":   FileDialog.FILE_MODE_OPEN_FILE,
			"access":      FileDialog.ACCESS_FILESYSTEM,
			"current_dir": SAVE_DIR,
			"filters":     PROJECT_FILE_FILTER
		},
		"callbacks": {
			"file_selected": _on_open_dialog_selected
		}
	})

func _on_open_project_transfer_dialog_requested() -> void:
	WindowManager.open_window("transfer")


func _on_save_project_as_dialog_requested() -> void:
	_ensure_save_dir()

	var params: Dictionary = {
		"title":     "Save Project As",
		"file_mode": FileDialog.FILE_MODE_SAVE_FILE,
		"access":    FileDialog.ACCESS_FILESYSTEM,
		"filters":   PROJECT_FILE_FILTER
	}

	var current_path: String = AppState.current_project.file_path.value
	if not current_path.is_empty():
		params["current_path"] = current_path
	else:
		params["current_dir"] = SAVE_DIR

	WindowManager.open_window("filedialog", {
		"params": params,
		"callbacks": {
			"file_selected": _on_save_dialog_selected
		}
	})


func _on_open_dialog_selected(path: String) -> void:
	_on_open_project_requested(path)


func _on_save_dialog_selected(path: String) -> void:
	_save(path)

# ── Save ──────────────────────────────────────────────────────────────────────

func _save(path: String) -> void:
	_ensure_save_dir()

	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		_fail("Failed to open file for writing: %s" % path)
		return

	file.store_string(JSON.stringify(AppState.current_project.serialize(), "\t"))
	file.close()

	AppState.current_project.file_path.value = path
	RecentProjects.add(AppState.current_project.file_path.value, AppState.current_project.project_name.value)

# ── Project Listing ───────────────────────────────────────────────────────────

func get_saved_projects() -> Array[String]:
	_ensure_save_dir()
	var result: Array[String] = []
	var dir: DirAccess = DirAccess.open(SAVE_DIR)
	if dir == null:
		return result
	dir.list_dir_begin()
	var file_name: String = dir.get_next()
	while file_name != "":
		if not dir.current_is_dir() and file_name.ends_with(".json"):
			result.append(file_name.trim_suffix(".json"))
		file_name = dir.get_next()
	return result


func _ensure_save_dir() -> void:
	if not DirAccess.dir_exists_absolute(SAVE_DIR):
		DirAccess.make_dir_recursive_absolute(SAVE_DIR)
