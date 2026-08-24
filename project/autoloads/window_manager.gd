# WindowManager.gd
extends Node

## Each window key now maps to a dictionary describing its desktop
## and mobile scene variants. BreakpointManager.is_mobile() determines
## which variant is instantiated at runtime.
const WINDOW_SCENES : Dictionary = {
    "settings": {
        "desktop": preload("res://scenes/dialogs/settings/settings.tscn"),
        "mobile": preload("res://scenes/dialogs/settings/settings.tscn")
    },
    "script_editor": {
        "desktop": preload("res://scenes/dialogs/script_editor/script_editor.tscn"),
        "mobile": preload("res://scenes/dialogs/script_editor/script_editor.tscn")
    },
    "opc_ua_connection_dialog": {
        "desktop": preload("res://scenes/dialogs/opc_ua_connection_dialog/opc_ua_connection_dialog_desktop.tscn"),
        "mobile": preload("res://scenes/dialogs/opc_ua_connection_dialog/opc_ua_connection_dialog_mobile.tscn")
    },
    "browse_nodes": {
        "desktop": preload("res://scenes/dialogs/browse_nodes/browse_nodes.tscn"),
        "mobile": preload("res://scenes/dialogs/browse_nodes/browse_nodes.tscn")
    },
    "extension_manager": {
        "desktop": preload("res://scenes/dialogs/extension_manager/extension_manager.tscn"),
        "mobile": preload("res://scenes/dialogs/extension_manager/extension_manager.tscn")
    },
    "transfer": {
        "desktop": preload("res://scenes/dialogs/project_transfer_dialog/project_transfer_dialog.tscn"),
        "mobile": preload("res://scenes/dialogs/project_transfer_dialog/project_transfer_dialog.tscn")
    }
}

## Resolutions at/below this size are treated as "mobile" and forced full screen.
const FULLSCREEN_BREAKPOINT: Vector2i = Vector2i(600, 600)

## Keep track of active window instances in memory
var active_windows: Dictionary = {}

## Tracks per-call signal connections made via the "callbacks" option,
## keyed by window_key, so they can be cleanly disconnected on reuse/close.
## { window_key: [ { "signal": String, "callable": Callable }, ... ] }
var _dynamic_connections: Dictionary = {}

## Scales the UI relative to the screen DPI so the layout is consistent
## across devices with different pixel densities.
func _ready() -> void:
    _set_scaling()
    get_tree().root.size_changed.connect(_on_root_size_changed)

## Applies DPI-based UI scaling. Runs at startup and whenever the
## display/resolution context changes (rotation, external monitor, etc.).
func _set_scaling() -> void:
    var screen_dpi: int = DisplayServer.screen_get_dpi()
    var scale_factor: float = maxf(screen_dpi / 120.0, 1.0)
    get_tree().root.content_scale_factor = scale_factor

## Re-evaluates scaling and full-screen forcing whenever the viewport
## size changes (orientation change, resize, moved to another display).
func _on_root_size_changed() -> void:
    _set_scaling()
    if _should_force_fullscreen():
        for window_instance: Node in active_windows.values():
            if is_instance_valid(window_instance) and window_instance is Window:
                window_instance.popup_centered_ratio(1.0)

## Resolves the correct PackedScene for a given window key based on the
## current device context, as reported by the BreakpointManager autoload.
## Falls back to whichever variant is available if one is missing.
func _get_window_scene(window_key: String) -> PackedScene:
    if not WINDOW_SCENES.has(window_key):
        return null

    var scene_variants: Dictionary = WINDOW_SCENES[window_key]
    var use_mobile: bool = BreakpointManager.is_mobile()

    if use_mobile and scene_variants.has("mobile"):
        return scene_variants["mobile"]
    elif scene_variants.has("desktop"):
        return scene_variants["desktop"]
    else:
        # Fallback in case only one variant is defined
        return scene_variants.get("mobile", null)

## Opens (or refocuses) a window.
##
## options:
##   "params"    : Dictionary of properties to set on the instance
##                 (e.g. { "file_mode": FileDialog.FILE_MODE_OPEN_FILE })
##   "callbacks" : Dictionary of signal_name -> Callable, connected as
##                 ONE_SHOT so repeated opens don't stack handlers
##   "size"      : Vector2i popup size override (ignored when forced full screen)
##   "force_new" : bool, bypasses the cached instance and creates a new one
func open_window(window_key: String, options: Dictionary = {}) -> Node:
    var params: Dictionary = options.get("params", {})
    var callbacks: Dictionary = options.get("callbacks", {})
    var force_new: bool = options.get("force_new", false)
    var auto_popup: bool = options.get("auto_popup", true)

    var window_instance: Node = null

    if not force_new and active_windows.has(window_key) and is_instance_valid(active_windows[window_key]):
        window_instance = active_windows[window_key]
        _bring_to_front(window_instance)
        _clear_dynamic_connections(window_key)
    else:
        if window_key == "filedialog":
            window_instance = FileDialog.new()
            window_instance.access = FileDialog.ACCESS_FILESYSTEM
            window_instance.file_mode = FileDialog.FILE_MODE_OPEN_FILE
            window_instance.display_mode = FileDialog.DISPLAY_LIST
            if OS.get_name() == "Android":
                window_instance.use_native_dialog = true
        else:
            var scene: PackedScene = _get_window_scene(window_key)
            if scene == null:
                printerr("Window key not found or scene missing: ", window_key)
                return null
            window_instance = scene.instantiate()

        get_tree().root.add_child(window_instance)
        active_windows[window_key] = window_instance

        if window_instance.has_signal("close_requested"):
            window_instance.close_requested.connect(func() -> void: close_window(window_key))
        elif window_instance.has_signal("canceled"):
            window_instance.canceled.connect(func() -> void: close_window(window_key))

    for prop_name: String in params.keys():
        if prop_name in window_instance:
            window_instance.set(prop_name, params[prop_name])

    _dynamic_connections[window_key] = []
    for signal_name: String in callbacks.keys():
        if window_instance.has_signal(signal_name):
            var callable: Callable = callbacks[signal_name]
            window_instance.connect(signal_name, callable, CONNECT_ONE_SHOT)
            _dynamic_connections[window_key].append({"signal": signal_name, "callable": callable})
        else:
            printerr("Signal not found on window '%s': %s" % [window_key, signal_name])

    if auto_popup:
        if window_instance is Window:
            var is_native: bool = ("use_native_dialog" in window_instance) and window_instance.use_native_dialog
            if is_native:
                # Native dialogs are OS-rendered; just trigger the popup,
                # sizing/positioning is handled by the platform itself.
                window_instance.popup_centered(options.get("size", Vector2i(800, 600)))
            elif _should_force_fullscreen():
                _force_window_fullscreen(window_instance)
            else:
                window_instance.popup_centered(options.get("size", Vector2i(800, 600)))
        elif window_instance is Control and _should_force_fullscreen():
            _force_control_fullscreen(window_instance)

    return window_instance

## Determines whether windows should be forced to full screen:
## - Always true on Android/iOS
## - True when the current screen resolution is at/below the breakpoint
func _should_force_fullscreen() -> bool:
    var platform: String = OS.get_name()
    if platform == "Android" or platform == "iOS":
        return true

    var screen_size: Vector2i = DisplayServer.screen_get_size()
    return screen_size.x <= FULLSCREEN_BREAKPOINT.x or screen_size.y <= FULLSCREEN_BREAKPOINT.y

## Forces a Window-based dialog to fill the current viewport.
## Works for both embedded subwindows (default project setting) and
## native subwindows, since it explicitly sets position/size after popup().
func _force_window_fullscreen(window_instance: Window) -> void:
    window_instance.unresizable = true
    window_instance.borderless = true
    window_instance.popup_centered_ratio(1.0)

## Forces a Control-based "window" to fill the current viewport.
func _force_control_fullscreen(control: Control) -> void:
    control.set_anchors_preset(Control.PRESET_FULL_RECT)
    control.position = Vector2.ZERO
    control.size = get_viewport().get_visible_rect().size

## Brings an already-active window instance to the foreground.
## Window nodes use grab_focus() (there is no move_to_front() on Window).
## Control-based "windows" are re-parented to the end of their sibling
## list so they render/draw on top within their parent container.
func _bring_to_front(window_instance: Node) -> void:
    if window_instance is Window:
        window_instance.grab_focus()
    elif window_instance is Control:
        var parent: Node = window_instance.get_parent()
        if parent != null:
            parent.move_child(window_instance, parent.get_child_count() - 1)

func _clear_dynamic_connections(window_key: String) -> void:
    if not _dynamic_connections.has(window_key):
        return
    var win: Node = active_windows.get(window_key)
    if is_instance_valid(win):
        for conn: Dictionary in _dynamic_connections[window_key]:
            if win.is_connected(conn["signal"], conn["callable"]):
                win.disconnect(conn["signal"], conn["callable"])
    _dynamic_connections.erase(window_key)

func close_window(window_key: String) -> void:
    _clear_dynamic_connections(window_key)
    if active_windows.has(window_key):
        var win: Node = active_windows[window_key]
        if is_instance_valid(win):
            win.queue_free()
        active_windows.erase(window_key)

func toggle_window(window_key: String, options: Dictionary = {}) -> void:
    if active_windows.has(window_key) and is_instance_valid(active_windows[window_key]):
        close_window(window_key)
    else:
        open_window(window_key, options)
