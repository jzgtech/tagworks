# sdk/preview_harness.gd
extends Control

@export var content_scene: PackedScene

func _ready() -> void:
    if content_scene == null:
        return
    var content: Control = content_scene.instantiate()
    content.set_anchors_preset(Control.PRESET_FULL_RECT)
    %ContentSlot.add_child(content)

    if content.has_method("on_widget_ready"):
        content.call("on_widget_ready", null)  # pass a mock ReactiveWidget if needed
