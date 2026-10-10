class_name OpcUaTagDetailForm
extends VBoxContainer

signal edited
signal browse_requested

@onready var node_id_edit:              LineEdit      = %NodeIdEdit
@onready var browse_tag_button:         Button        = %BrowseTagButton
@onready var tag_name_edit:             LineEdit      = %TagNameEdit
@onready var data_type_label:           Label         = %DataTypeLabel
@onready var data_type_dropdown:        OptionButton  = %DataTypeDropdown
@onready var is_active_check:           CheckBox      = %IsActiveCheck
@onready var sampling_edit:             SpinBox       = %SamplingEdit
@onready var deadband_edit:             SpinBox       = %DeadbandEdit

@onready var simulated_range_container: HBoxContainer = %SimulatedRangeContainer
@onready var simulated_range_min_edit:  SpinBox       = %SimulatedRangeMinEdit
@onready var simulated_range_max_edit:  SpinBox       = %SimulatedRangeMaxEdit

var _loading: bool = false

func _ready() -> void:
	# node_id is populated exclusively via Browse — read-only by design,
	# consistent with the property-panel tag_edit pattern.
	browse_tag_button.pressed.connect(_on_browse_tag_pressed)
	tag_name_edit.focus_exited.connect(_emit_edited)
	is_active_check.toggled.connect(_emit_edited.unbind(1))
	sampling_edit.value_changed.connect(_emit_edited.unbind(1))
	deadband_edit.value_changed.connect(_emit_edited.unbind(1))

	data_type_dropdown.clear()
	for enum_value: int in ReactiveOpcUaTag.TagType.values():
		var display_text: String
		
		# Check if the text lookup table contains a specific equivalent string
		if ReactiveOpcUaTag.FRIENDLY_NAMES.has(enum_value):
			display_text = ReactiveOpcUaTag.FRIENDLY_NAMES[enum_value]
		else:
			# Fallback: Convert the raw enum number to text if not set in lookup
			display_text = "Type Code: " + str(enum_value)
		
		# Add to dropdown. Passing 'enum_value' as the ID anchors the index perfectly
		data_type_dropdown.add_item(display_text, enum_value)

func _emit_edited() -> void:
	if _loading:
		return
	edited.emit()

func _on_browse_tag_pressed() -> void:
	browse_requested.emit()

# ── Public API ─────────────────────────────────────────────────────────────

func load_config(tag: ReactiveOpcUaTag) -> void:
	_loading = true
	node_id_edit.text                = tag.node_id.value if tag.node_id.value != "" else "(none)"
	tag_name_edit.text               = tag.display_name.value
	if tag.owner_as_subscription().owner_as_server().is_mock.value:
		data_type_label.hide()
		data_type_dropdown.show()
		browse_tag_button.hide()
		simulated_range_container.show()
	is_active_check.button_pressed   = tag.is_active.value
	sampling_edit.value              = tag.sampling_ms.value
	deadband_edit.value              = tag.deadband.value
	_loading = false

func commit_to(tag: ReactiveOpcUaTag) -> void:
	# node_id is committed separately via apply_picked_node_id(), since it's
	# not directly editable in this form.
	tag.node_id.value        = node_id_edit.text
	tag.display_name.value   = tag_name_edit.text.strip_edges()
	tag.tag_type.value       = data_type_dropdown.selected
	tag.is_active.value      = is_active_check.button_pressed
	tag.sampling_ms.value    = sampling_edit.value
	tag.deadband.value       = deadband_edit.value

## Called by the parent dialog's browse callback once a node is picked.
func apply_picked_node_id(node_id: OpcUaNodeId) -> void:
	node_id_edit.text = node_id.to_tag_name()
	data_type_dropdown.select(node_id.numeric_id)
	edited.emit()
