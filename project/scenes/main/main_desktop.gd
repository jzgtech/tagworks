# main.gd
extends Control

# ── Child references ──────────────────────────────────────────────────────────

@onready var _menu_bar    : MenuBarDesktop = %MenuBar
@onready var _root_layout : VBoxContainer  = %RootLayout
@onready var _mac_os_spacer: Control = %MacOSSpacer

@onready var pages_panel   : PagePanel    = %PagesPanel
@onready var tab_container : TabContainer = %TabContainer

var active_theme : Theme
@onready var dark_theme : Theme = preload("res://resources/dark_theme.tres")
@onready var light_theme : Theme = preload("res://resources/light_theme.tres")

var _dragging: bool = false
var _drag_offset: Vector2i

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
    
    # Force this window to 'resize' to ensure the scaling is recalculated.
    get_tree().root.size_changed.emit()

func _gui_input(event: InputEvent) -> void:
    if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
        if event.pressed:
            _dragging = true
            _drag_offset = DisplayServer.mouse_get_position() - get_window().position
        else:
            _dragging = false

func _process(_delta: float) -> void:
    if _dragging:
        get_window().position = DisplayServer.mouse_get_position() - _drag_offset

    var current_mode: Window.Mode = get_window().mode
    if current_mode == Window.MODE_FULLSCREEN or current_mode == Window.MODE_EXCLUSIVE_FULLSCREEN:
        _mac_os_spacer.visible = false
    else:
        _mac_os_spacer.visible = true if BreakpointManager.is_running_on_macos_hardware() else false

## Restores normal window behavior after the borderless splash screen.
func _setup_window() -> void:
    var window: Window = get_window()
    window.unresizable = false
    window.transparent = false
    window.min_size = Vector2i(800, 600)
    window.size = Vector2i(1024, 720)
    window.maximize_disabled = false
    window.minimize_disabled = false
    window.extend_to_title = true
    window.borderless = false
    window.move_to_center()

    var global_menu_supported: bool = DisplayServer.has_feature(DisplayServer.FEATURE_GLOBAL_MENU)
    var wants_global_menu: bool = _menu_bar.menu_bar.is_prefer_global_menu()

    if global_menu_supported and wants_global_menu:
        _root_layout.add_theme_constant_override("separation", 0)

func _connect_signals() -> void:
    # ── System ────────────────────────────────────────────────────────────────
    DisplayServer.set_system_theme_change_callback(_on_os_theme_changed)
    _on_os_theme_changed()

    # ── Menu Bar ────────────────────────────────────────────────────────
    AppState.current_project.opc_ua_servers.connect_self_changed(
        func(_origin: Reactive) -> void:
            _rebuild_server_menu()
    )
    
    AppState.edit_mode.connect_self_changed(
        func(_origin: Reactive) -> void:
            _rebuild_edit_menu()
    )

    # ── AppState (named handlers so we can call them directly) ────────────────

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
    _update_ui_visibility()
    _rebuild_edit_menu()
    _rebuild_server_menu()

func _rebuild_edit_menu() -> void:
    MenuActions.rebuild_edit_menu(_menu_bar.edit_menu)

func _rebuild_server_menu() -> void:
    MenuActions.rebuild_server_menu(_menu_bar.server_menu)

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
    pages_panel.visible = is_loaded
    tab_container.visible = is_loaded and not runtime_only

# ── System ────────────────────────────────────────────────────────────────────
func _on_os_theme_changed() -> void:
    theme = dark_theme if DisplayServer.is_dark_mode() else light_theme

# ── Edit Mode ─────────────────────────────────────────────────────────────────

func _on_mode_toggled(is_edit: bool) -> void:
    AppState.edit_mode.value = is_edit
