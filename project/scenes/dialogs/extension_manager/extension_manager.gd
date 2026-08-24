extends Window

@onready var _install_button : Button        = %InstallButton
@onready var _list_container : VBoxContainer = %ExtensionList
@onready var _error_label    : Label         = %StatusLabel

const ExtensionCard: PackedScene = preload("res://scenes/dialogs/extension_manager/extension_card.tscn")

func _ready() -> void:
    AppState.loaded_widget_extensions.connect_self_changed(_on_registry_changed)
    _install_button.pressed.connect(_on_install_button_pressed)
    _refresh_list()

func _on_install_button_pressed() -> void:
    WindowManager.open_window("filedialog", {
        "params": {
            "title"       : "Open Extension",
            "file_mode"   : FileDialog.FILE_MODE_OPEN_FILE,
            "access"      : FileDialog.ACCESS_FILESYSTEM,
            "current_dir" : "extensions",
            "filters"     : ".zip"
        },
        "callbacks": {
            "file_selected": _on_open_dialog_selected
        }
    })

func _on_open_dialog_selected(path : String) -> void:
    WidgetExtensionRegistry.install_extension_from_path(path)

func _on_registration_failed(reason : String, source_path : String) -> void:
    _error_label.text = "%s\n\nSource: %s" % [reason, source_path]

func _on_registry_changed(_origin : ReactiveDictionary) -> void:
    _refresh_list()

func _refresh_list() -> void:
    for child : Node in _list_container.get_children():
        child.queue_free()

    for id : String in AppState.loaded_widget_extensions.keys():
        var descriptor: WidgetExtensionDescriptor = AppState.loaded_widget_extensions.get_entry(id)
        var card: Control = ExtensionCard.instantiate()
        _list_container.add_child(card)
        card.setup(descriptor)
