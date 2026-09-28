extends Window

@onready var locale_option: OptionButton = %LanguageOptionButton
@onready var network_transfer_switch: CheckButton = %NetworkTransferCheckButton
@onready var device_name_edit: LineEdit = %DeviceNameLineEdit
@onready var require_pin_switch: CheckButton = %RequirePINCheckButton

@onready var close_button: Button = %CloseButton

var _locale_codes: PackedStringArray = []

func _ready() -> void:
	close_requested.connect(_on_close_pressed)
	close_button.pressed.connect(_on_close_pressed)

	_populate_locales()
	_sync_from_settings()

	locale_option.item_selected.connect(_on_locale_selected)
	network_transfer_switch.toggled.connect(_on_network_transfer_toggled)
	device_name_edit.text_submitted.connect(_on_device_name_submitted)
	device_name_edit.focus_exited.connect(
		func() -> void: _on_device_name_submitted(device_name_edit.text)
	)
	require_pin_switch.toggled.connect(_on_require_pin_toggled)

	# Keep UI in sync if settings change elsewhere (e.g. reset to defaults).
	AppSettings.preferred_locale.connect_self_changed(
		func(_origin: Reactive) -> void: _sync_locale_option()
	)
	AppSettings.network_transfer_enabled.connect_self_changed(
		func(origin: Reactive) -> void:
			network_transfer_switch.button_pressed = origin.value
	)
	AppSettings.device_name.connect_self_changed(
		func(origin: ReactiveString) -> void:
			device_name_edit.text = origin.value
	)
	AppSettings.require_pin_for_transfers.connect_self_changed(
		func(origin: ReactiveBool) -> void:
			require_pin_switch.button_pressed = origin.value
	)


func _populate_locales() -> void:
	locale_option.clear()
	_locale_codes = TranslationServer.get_loaded_locales()
	for i: int in _locale_codes.size():
		var code: String = _locale_codes[i]
		var display_name: String = TranslationServer.get_locale_name(code)
		locale_option.add_item(display_name)
		locale_option.set_item_metadata(i, code)

func _sync_from_settings() -> void:
	_sync_locale_option()
	network_transfer_switch.button_pressed = AppSettings.network_transfer_enabled.value
	device_name_edit.text = AppSettings.device_name.value if AppSettings.has_method("device_name") else ""

func _sync_locale_option() -> void:
	var current: String = AppSettings.preferred_locale.value
	var idx: int = _locale_codes.find(current)
	if idx != -1:
		locale_option.select(idx)

func _on_locale_selected(index: int) -> void:
	var code: String = locale_option.get_item_metadata(index)
	AppSettings.set_locale(code)

func _on_network_transfer_toggled(pressed: bool) -> void:
	AppSettings.set_network_transfer_enabled(pressed)

func _on_device_name_submitted(new_text: String) -> void:
	AppSettings.set_device_name(new_text.strip_edges())

func _on_require_pin_toggled(pressed: bool) -> void:
	AppSettings.set_require_pin_for_transfers(pressed)

func _on_close_pressed() -> void:
	hide()
	queue_free()
