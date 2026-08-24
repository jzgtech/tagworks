class_name MenuBarMobile
extends HBoxContainer

@onready var _edit_mode_toggle: Button = %EditModeButton
@onready var _menu_button: MenuButton = %MenuButton

var _file_menu: PopupMenu
var _edit_menu: PopupMenu
var _server_menu: PopupMenu
var server_menu: PopupMenu:
    get: return _server_menu

func _ready() -> void:
    var root_menu: PopupMenu = _menu_button.get_popup()

    _file_menu = _build_submenu(root_menu, "FileMenu")
    MenuActions.populate_popup(_file_menu, MenuActions.FILE_ITEMS)
    _file_menu.id_pressed.connect(MenuActions.handle_file_action)

    _edit_menu = _build_submenu(root_menu, "EditMenu")
    MenuActions.populate_popup(_edit_menu, MenuActions.EDIT_ITEMS)
    _edit_menu.id_pressed.connect(MenuActions.handle_edit_action)

    _server_menu = _build_submenu(root_menu, "ServerMenu")
    MenuActions.populate_popup(_server_menu, MenuActions.SERVER_ITEMS)
    _server_menu.id_pressed.connect(MenuActions.handle_server_action)

    root_menu.add_submenu_item("File", "FileMenu")
    root_menu.add_submenu_item("Edit", "EditMenu")
    root_menu.add_submenu_item("Server", "ServerMenu")

    _menu_button.about_to_popup.connect(_position_root_menu)

    _edit_mode_toggle.toggled.connect(
        func(edit_mode: bool) -> void:
            AppState.edit_mode.value = edit_mode
    )

    AppState.edit_mode.connect_self_changed(
        func(edit_mode: ReactiveBool) -> void:
            _edit_mode_toggle.set_pressed_no_signal(edit_mode.value)
    )


func _build_submenu(parent: PopupMenu, node_name: String) -> PopupMenu:
    var submenu: PopupMenu = PopupMenu.new()
    submenu.name = node_name
    parent.add_child(submenu)
    return submenu

func _position_root_menu() -> void:
    var popup: PopupMenu = _menu_button.get_popup()
    popup.reset_size()
    var popup_size: Vector2 = popup.size
    var btn_rect: Rect2 = _menu_button.get_global_rect()

    var target_pos: Vector2 = Vector2(
        btn_rect.position.x + btn_rect.size.x - popup_size.x,
        btn_rect.position.y + btn_rect.size.y
    )

    var viewport_rect: Rect2 = get_viewport().get_visible_rect()
    target_pos.x = clamp(target_pos.x, viewport_rect.position.x + 8.0,
        viewport_rect.position.x + viewport_rect.size.x - popup_size.x - 8.0)
    target_pos.y = clamp(target_pos.y, viewport_rect.position.y + 8.0,
        viewport_rect.position.y + viewport_rect.size.y - popup_size.y - 8.0)

    popup.position = target_pos
