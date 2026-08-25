# main.gd
extends Control

# ── Child references ──────────────────────────────────────────────────────────

@onready var _menu_bar :  MenuBarDesktop   = %MenuBar

@onready var page_container :            VSplitContainer       = %PageContainer
@onready var canvas_container :          PageTabContainer      = %CanvasContainer
@onready var inspector_container :       VSplitContainer       = %InspectorContainer

var active_theme : Theme
@onready var base_theme : Theme = preload("res://resources/base_theme.tres")
@onready var dark_theme : Theme = preload("res://resources/dark_theme.tres")
@onready var light_theme : Theme = preload("res://resources/light_theme.tres")

# ── Constants ─────────────────────────────────────────────────────────────────

## Number of static items in the server menu that precede the dynamic
## server list. Used to avoid removing fixed entries during a rebuild.
const SERVER_MENU_FIXED_ITEM_COUNT: int = 1

## Reserved IDs for the dynamic "Connect All" / "Disconnect All" items.
## Kept out of the range used by fixed static items to avoid collisions.
const CONNECT_ALL_ID: int = 1000
const DISCONNECT_ALL_ID: int = 1001

# ── Lifecycle ─────────────────────────────────────────────────────────────────

func _ready() -> void:
    _setup_window()
    _connect_signals()

## Restores normal window behavior after the borderless splash screen.
func _setup_window() -> void:
    var window: Window = get_window()
    window.borderless = false
    window.unresizable = false
    window.min_size = Vector2i(800, 600)
    window.size = Vector2i(1024, 720)
    window.move_to_center()

func _connect_signals() -> void:
    # ── System ────────────────────────────────────────────────────────────────
    DisplayServer.set_system_theme_change_callback(_on_os_theme_changed)
    _on_os_theme_changed()

    # ── Server registry ────────────────────────────────────────────────────────
    AppState.current_project.opc_ua_servers.connect_self_changed(
        func(_origin: Reactive) -> void:
            _rebuild_server_menu()
    )

    # ── AppState (named handlers so we can call them directly) ────────────────
    AppState.current_project.project_name.connect_self_changed(_on_project_name_changed)

    # UI visibility depends on BOTH runtime_only and is_loaded — a single
    # handler keeps the combined rule consistent regardless of which one
    # changes.
    AppState.runtime_only.connect_self_changed(_update_ui_visibility)
    AppState.current_project.is_loaded.connect_self_changed(_update_ui_visibility)

    # ── Sync current state ─────────────────────────────────────────────────────
    # connect_self_changed only fires on FUTURE changes. If the project was
    # created/opened by the splash screen before this scene existed, we must
    # manually apply the current values now, or the UI stays stale.
    _sync_state()

func _sync_state() -> void:
    _on_project_name_changed(AppState.current_project.project_name)
    _update_ui_visibility()
    _rebuild_server_menu()

func _rebuild_server_menu() -> void:
    MenuActions.rebuild_server_menu(_menu_bar.server_menu)

func _on_project_name_changed(new_name: ReactiveString) -> void:
    get_window().title = new_name.value

## Single source of truth for UI visibility. Reacts to changes in either
## runtime_only or is_loaded, since inspector visibility depends on both.
##
## - menu_bar_container : depends only on runtime_only
## - inspector_container: depends on is_loaded AND NOT runtime_only
## - page_container      : depends only on is_loaded
## - canvas_container     : depends only on is_loaded
func _update_ui_visibility(_origin: Reactive = null) -> void:
    var runtime_only: bool = AppState.runtime_only.value
    var is_loaded: bool = AppState.current_project.is_loaded.value

    _menu_bar.visible = not runtime_only
    inspector_container.visible = is_loaded and not runtime_only
    page_container.visible = is_loaded
    canvas_container.visible = is_loaded

# ── System ────────────────────────────────────────────────────────────────────

func deep_merge_themes(base: Theme, modifier: Theme) -> Theme:
    var result: Theme = base.duplicate(true)

    for type_name: String in modifier.get_type_list():
        for style_name: String in modifier.get_stylebox_list(type_name):
            var mod_sb: StyleBox = modifier.get_stylebox(style_name, type_name)

            if mod_sb is StyleBoxFlat and result.has_stylebox(style_name, type_name):
                var base_sb: StyleBox = result.get_stylebox(style_name, type_name)
                if base_sb is StyleBoxFlat:
                    base_sb.bg_color = mod_sb.bg_color
                    base_sb.border_color = mod_sb.border_color
                    base_sb.shadow_color = mod_sb.shadow_color
            else:
                result.set_stylebox(style_name, type_name, mod_sb)

        for color_name: String in modifier.get_color_list(type_name):
            result.set_color(color_name, type_name, modifier.get_color(color_name, type_name))

    return result

func _on_os_theme_changed() -> void:
    active_theme = deep_merge_themes(base_theme, dark_theme if DisplayServer.is_dark_mode() else light_theme)
    theme = active_theme

# ── Edit Mode ─────────────────────────────────────────────────────────────────

func _on_mode_toggled(is_edit: bool) -> void:
    AppState.edit_mode.value = is_edit
