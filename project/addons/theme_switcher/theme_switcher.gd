@tool
extends EditorPlugin

const LIGHT_THEME_PATH = "res://resources/light_theme.tres"
const DARK_THEME_PATH = "res://resources/dark_theme.tres"

var menu_popup: PopupMenu

func _enter_tree() -> void:
	menu_popup = PopupMenu.new()
	menu_popup.add_item("Follow System Theme", 0)
	menu_popup.add_item("Force Light Theme", 1)
	menu_popup.add_item("Force Dark Theme", 2)
	menu_popup.id_pressed.connect(_on_menu_item_clicked)
	
	add_tool_submenu_item("Theme Switcher", menu_popup)
	
	# Connect to active tab changes so swapping scenes refreshes the style
	main_screen_changed.connect(_on_screen_or_tab_changed)
	
	DisplayServer.set_system_theme_change_callback(_on_os_theme_changed)
	_on_os_theme_changed()


func _exit_tree() -> void:
	remove_tool_menu_item("Theme Switcher")
	DisplayServer.set_system_theme_change_callback(Callable())
	if menu_popup:
		menu_popup.queue_free()


func _on_menu_item_clicked(id: int) -> void:
	match id:
		0:
			DisplayServer.set_system_theme_change_callback(_on_os_theme_changed)
			_on_os_theme_changed()
		1:
			DisplayServer.set_system_theme_change_callback(Callable())
			_apply_theme_directly(LIGHT_THEME_PATH)
		2:
			DisplayServer.set_system_theme_change_callback(Callable())
			_apply_theme_directly(DARK_THEME_PATH)


func _on_os_theme_changed() -> void:
	if DisplayServer.is_dark_mode_supported():
		var target_theme = DARK_THEME_PATH if DisplayServer.is_dark_mode() else LIGHT_THEME_PATH
		_apply_theme_directly(target_theme)


func _on_screen_or_tab_changed(_screen_name: String) -> void:
	# Trigger refresh when you change your workspace tabs
	_on_os_theme_changed()


func _apply_theme_directly(theme_path: String) -> void:
	# 1. Still save it so it works perfectly when you hit "Play Game"
	ProjectSettings.set_setting("gui/theme/custom", theme_path)
	ProjectSettings.save()
	
	# 2. Force it directly onto the root node of your current scene tab
	var theme_resource = load(theme_path) as Theme
	var editor_interface = get_editor_interface()
	if editor_interface and theme_resource:
		var edited_root = editor_interface.get_edited_scene_root() as Control
		if edited_root:
			# Directly re-skin the active tree workspace on the spot
			edited_root.theme = theme_resource
