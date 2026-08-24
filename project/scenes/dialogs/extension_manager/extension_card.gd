extends HBoxContainer

@onready var _name_label : Label = %NameLabel
@onready var _desc_label : Label = %DescriptionLabel

func setup(widget : WidgetExtensionDescriptor) -> void:
    _name_label.text = widget.display_name
    _desc_label.text = widget.install_path
