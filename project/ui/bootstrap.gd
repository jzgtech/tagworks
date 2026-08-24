extends Node

const START_SCREEN_DESKTOP: String = "res://scenes/start_screen/start_screen_desktop.tscn"
const START_SCREEN_MOBILE : String = "res://scenes/start_screen/start_screen_mobile.tscn"

func _ready() -> void:
    # Ensure BreakpointManager has evaluated the current window size before we route based on it.
    await get_tree().process_frame

    if BreakpointManager.is_mobile():
        get_tree().change_scene_to_file(START_SCREEN_MOBILE)
    else:
        get_tree().change_scene_to_file(START_SCREEN_DESKTOP)

func _get_launch_project_path() -> String:
    var args: PackedStringArray = OS.get_cmdline_user_args()
    for arg: String in args:
        if arg.begins_with("--project="):
            return arg.get_slice("=", 1)
    return ""
