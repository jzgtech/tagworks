extends PanelContainer
class_name Toast

signal dismissed(toast: Toast)

@onready var icon_label   : Label       = %IconLabel
@onready var message_label: Label       = %MessageLabel
@onready var close_button : Button      = %CloseButton
@onready var progress_bar : ProgressBar = %ProgressBar

var duration: float = 3.0
var _tween: Tween
var _time_left: float
var _paused: bool = false

const TYPE_COLORS: Dictionary = {
    "success": Color("4caf50"),
    "error": Color("f44336"),
    "warning": Color("ff9800"),
    "info": Color("2196f3"),
}

const TYPE_ICONS: Dictionary = {
    "success": "✅",
    "error": "⛔",
    "warning": "⚠️",
    "info": "ℹ️",
}

func _ready() -> void:
    close_button.pressed.connect(_on_close_pressed)
    mouse_entered.connect(_on_mouse_entered)
    mouse_exited.connect(_on_mouse_exited)
    modulate.a = 0.0
    scale = Vector2(0.9, 0.9)

func setup(message: String, type: String = "info", duration_sec: float = 3.0) -> void:
    message_label.text = message
    duration = duration_sec
    _time_left = duration

    var color: Color = TYPE_COLORS.get(type, TYPE_COLORS["info"])
    var stylebox: StyleBoxFlat = get_theme_stylebox("panel").duplicate()
    stylebox.border_color = color
    stylebox.bg_color = color.darkened(0.7)
    add_theme_stylebox_override("panel", stylebox)

    if TYPE_ICONS.has(type):
        icon_label.text = TYPE_ICONS[type]
    progress_bar.modulate = color

func play_in() -> void:
    _tween = create_tween()
    _tween.set_parallel(true)
    _tween.tween_property(self, "modulate:a", 1.0, 0.25).set_trans(Tween.TRANS_SINE)
    _tween.tween_property(self, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func play_out() -> void:
    _tween = create_tween()
    _tween.set_parallel(true)
    _tween.tween_property(self, "modulate:a", 0.0, 0.2)
    _tween.tween_property(self, "scale", Vector2(0.9, 0.9), 0.2)
    _tween.chain().tween_callback(func() -> void: dismissed.emit(self))

func _process(delta: float) -> void:
    if _paused or duration <= 0.0:
        return
    _time_left -= delta
    progress_bar.value = (_time_left / duration) * 100.0
    if _time_left <= 0.0:
        play_out()
        set_process(false)

func _on_close_pressed() -> void:
    set_process(false)
    play_out()

func _on_mouse_entered() -> void:
    _paused = true

func _on_mouse_exited() -> void:
    _paused = false
