class_name MenuBarDesktop
extends HBoxContainer

@onready var menu_bar: MenuBar = %MenuBar
@onready var _file_menu: PopupMenu = %FilePopup
@onready var _edit_menu: PopupMenu = %EditPopup
@onready var _server_menu: PopupMenu = %ServerPopup

var edit_menu: PopupMenu:
	get: return _edit_menu

var server_menu: PopupMenu:
	get: return _server_menu

func _ready() -> void:
	MenuActions.populate_popup(_file_menu, MenuActions.FILE_ITEMS)
	MenuActions.populate_popup(_edit_menu, MenuActions.EDIT_ITEMS)
	MenuActions.populate_popup(_server_menu, MenuActions.SERVER_ITEMS)

	_file_menu.id_pressed.connect(MenuActions.handle_file_action)
	_edit_menu.id_pressed.connect(MenuActions.handle_edit_action)
	_server_menu.id_pressed.connect(MenuActions.handle_server_action)
