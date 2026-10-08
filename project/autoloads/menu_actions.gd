extends Node

enum FileAction { NEW, OPEN, TRANSFER, SAVE, SAVE_AS, CLOSE, EXIT }
enum EditAction { SETTINGS, EXTENSIONS, EDIT_MODE }
enum ServerAction { SETTINGS, CONNECT_ALL, DISCONNECT_ALL }

# Data-driven menu structure both variants read from when building their UI.
# Format: [ { label, id, separator_after } ]
const FILE_ITEMS: Array = [
    {"label": "New", "id": FileAction.NEW},
    {"label": "Open...", "id": FileAction.OPEN},
    {"label": "Transfer...", "id": FileAction.TRANSFER},
    {"label": "Save", "id": FileAction.SAVE},
    {"label": "Save As...", "id": FileAction.SAVE_AS},
    {"label": "Close", "id": FileAction.CLOSE},
    {"label": "", "separator": true},
    {"label": "Exit", "id": FileAction.EXIT},
]

const EDIT_ITEMS: Array = [
    {"label": "Settings", "id": EditAction.SETTINGS},
    {"label": "Extension Manager", "id": EditAction.EXTENSIONS},
    {"label": "Edit", "id": EditAction.EDIT_MODE}
]

const SERVER_ITEMS: Array = [
    {"label": "Connection Settings", "id": ServerAction.SETTINGS},
]

## Number of static items in the menu that precede any dynamic items
## Used to avoid removing fixed entries during a rebuild.
const SERVER_MENU_FIXED_ITEM_COUNT: int = 1

## Tracks dynamically created server submenus keyed by server_id.
## Enables clean teardown and rebuild when the server list changes.
var _server_submenus: Dictionary = {}

## Tracks per-server connection_status bindings keyed by server_id, so each
## can be individually disconnected on teardown/rebuild.
## { server_id: { "cfg": ReactiveOpcUaServer, "callable": Callable } }
var _status_bindings: Dictionary = {}

func handle_file_action(id: int) -> void:
    match id:
        FileAction.NEW: IntentBus.new_project_requested.emit()
        FileAction.OPEN: IntentBus.open_project_dialog_requested.emit()
        FileAction.TRANSFER: IntentBus.open_project_transfer_dialog_requested.emit()
        FileAction.SAVE: IntentBus.save_project_requested.emit()
        FileAction.SAVE_AS: IntentBus.save_project_as_dialog_requested.emit()
        FileAction.CLOSE: IntentBus.close_project_requested.emit()
        FileAction.EXIT: get_tree().quit()

func handle_edit_action(id: int) -> void:
    match id:
        EditAction.SETTINGS:
            WindowManager.open_window("settings", {
                "size": Vector2i(900, 720)
            })
        EditAction.EXTENSIONS:
            WindowManager.open_window("extension_manager", {
                "size": Vector2i(900, 720)
            })
        EditAction.EDIT_MODE:
            AppState.edit_mode.value = not AppState.edit_mode.value

func handle_server_action(id: int) -> void:
    match id:
        ServerAction.SETTINGS:
            WindowManager.open_window("opc_ua_connection_dialog", {
                "size": Vector2i(900, 720)
            })
        ServerAction.CONNECT_ALL:
            IntentBus.connect_all_servers.emit()
        ServerAction.DISCONNECT_ALL:
            IntentBus.disconnect_all_servers.emit()

## Updates the edit menu's toggle item text based on the current application edit mode state.
## [param edit_menu] The PopupMenu instance containing the edit action item.
func rebuild_edit_menu(edit_menu: PopupMenu) -> void:
    var item_index: int = edit_menu.get_item_index(EditAction.EDIT_MODE)
    
    # If the item doesn't exist in the menu, get_item_index returns -1
    if item_index == -1:
        LogManager.critical("Edit Mode item not found in the provided PopupMenu.")
        return

    if AppState.edit_mode.value:
        edit_menu.set_item_text(item_index, "Exit Edit Mode")
    else:
        edit_menu.set_item_text(item_index, "Enter Edit Mode")


## Tears down all dynamic server menu entries (and their status bindings)
## and rebuilds them from the current project's server list.
##
## `server_menu` is owned by the calling view (mobile burger submenu or
## desktop MenuBar entry) — this function only mutates its item list,
## it does not care which shell created it.
func rebuild_server_menu(server_menu: PopupMenu) -> void:
    teardown_server_menu()

    while server_menu.item_count > SERVER_MENU_FIXED_ITEM_COUNT:
        server_menu.remove_item(server_menu.item_count - 1)

    if AppState.current_project.opc_ua_servers.value.is_empty():
        return

    server_menu.add_item("Connect All", ServerAction.CONNECT_ALL)
    server_menu.add_item("Disconnect All", ServerAction.DISCONNECT_ALL)
    server_menu.add_separator()

    for cfg: ReactiveOpcUaServer in AppState.current_project.opc_ua_servers.values():
        var server_id: String = cfg.id.value

        var submenu: PopupMenu = PopupMenu.new()
        submenu.name = "sub_%s" % server_id
        submenu.add_item("Connect", 0)
        submenu.add_item("Disconnect", 1)
        submenu.id_pressed.connect(
            func(id: int) -> void:
                match id:
                    0: OpcUaManager.connect_server(server_id)
                    1: OpcUaManager.disconnect_server(server_id)
        )
        server_menu.add_child(submenu)
        _server_submenus[server_id] = submenu

        var menu_item_index: int = server_menu.item_count
        server_menu.add_submenu_node_item(_status_prefix(cfg) + cfg.display_name.value, submenu)

        _bind_status(cfg, server_menu, menu_item_index)

## Disconnects all reactive status bindings and frees dynamically created
## submenus. Must be called before the owning view/PopupMenu is freed
## (e.g. in the view's _exit_tree), or when rebuilding from scratch.
func teardown_server_menu() -> void:
    for binding: Dictionary in _status_bindings.values():
        var cfg: ReactiveOpcUaServer = binding.get("cfg")
        var callback: Callable = binding.get("callable")
        if cfg != null and callback.is_valid():
            cfg.connection_status.reactive_changed.disconnect(callback)
    _status_bindings.clear()

    for submenu: PopupMenu in _server_submenus.values():
        if is_instance_valid(submenu):
            submenu.free()
    _server_submenus.clear()

## Binds directly to a server's reactive connection_status field, updating
## its menu row prefix immediately on any transition — no polling required.
## `is_instance_valid(server_menu)` guards against the owning view having
## been freed without teardown_server_menu() being called first.
func _bind_status(cfg: ReactiveOpcUaServer, server_menu: PopupMenu, menu_item_index: int) -> void:
    var server_id: String = cfg.id.value

    var callback: Callable = func(_origin: Reactive) -> void:
        if is_instance_valid(server_menu) and menu_item_index < server_menu.item_count:
            server_menu.set_item_text(menu_item_index, _status_prefix(cfg) + cfg.display_name.value)

    cfg.connection_status.connect_self_changed(callback)
    _status_bindings[server_id] = {"cfg": cfg, "callable": callback}

func _status_prefix(cfg: ReactiveOpcUaServer) -> String:
    match cfg.connection_status.value:
        ReactiveOpcUaServer.ConnectionStatus.CONNECTED:
            return "● "
        ReactiveOpcUaServer.ConnectionStatus.CONNECTING:
            return "◐ "
        ReactiveOpcUaServer.ConnectionStatus.CONNECTION_FAILED:
            return "✕ "
        _:
            return "○ "

func populate_popup(popup: PopupMenu, items: Array) -> void:
    popup.clear()
    for item: Dictionary in items:
        if item.get("separator", false):
            popup.add_separator()
        else:
            popup.add_item(item["label"], item["id"])
