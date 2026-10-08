extends Node

const SETTINGS_PATH: String = "user://settings.cfg"

var preferred_locale: ReactiveString = ReactiveString.new("")
var network_transfer_enabled: ReactiveBool = ReactiveBool.new(false)
var device_name: ReactiveString = ReactiveString.new("")
var require_pin_for_transfers: ReactiveBool = ReactiveBool.new(true)

func _ready() -> void:
    _load()
    if not preferred_locale.value.is_empty():
        TranslationServer.set_locale(preferred_locale.value)
    else:
        _apply_os_default_locale()

    preferred_locale.connect_self_changed(
        func(_origin: Reactive) -> void: _save()
    )
    network_transfer_enabled.connect_self_changed(
        func(_origin: Reactive) -> void:
            _save()
            _apply_network_transfer_state()
    )
    device_name.connect_self_changed(
        func(_origin: Reactive) -> void: _save()
    )
    require_pin_for_transfers.connect_self_changed(
        func(_origin: Reactive) -> void: _save()
    )

    if device_name.value.is_empty():
        device_name.value = OS.get_environment("COMPUTERNAME") if OS.has_environment("COMPUTERNAME") else OS.get_name()

    _apply_network_transfer_state()

func _apply_os_default_locale() -> void:
    var os_locale: String = OS.get_locale_language()
    if TranslationServer.get_loaded_locales().has(os_locale):
        TranslationServer.set_locale(os_locale)
        preferred_locale.value = os_locale

func set_locale(locale: String) -> void:
    TranslationServer.set_locale(locale)
    preferred_locale.value = locale

func set_network_transfer_enabled(enabled: bool) -> void:
    network_transfer_enabled.value = enabled

func set_device_name(new_name: String) -> void:
    device_name.value = new_name

func set_require_pin_for_transfers(enabled: bool) -> void:
    require_pin_for_transfers.value = enabled

func _apply_network_transfer_state() -> void:
    if network_transfer_enabled.value:
        DiscoveryHost.start()
    else:
        DiscoveryHost.stop()

func _load() -> void:
    var config: ConfigFile = ConfigFile.new()
    if config.load(SETTINGS_PATH) == OK:
        preferred_locale.value = config.get_value("app", "locale", "")
        network_transfer_enabled.value = config.get_value("app", "network_transfer_enabled", false)
        device_name.value = config.get_value("app", "device_name", "")
        require_pin_for_transfers.value = config.get_value("app", "require_pin_for_transfers", true)

func _save() -> void:
    var config: ConfigFile = ConfigFile.new()
    config.set_value("app", "locale", preferred_locale.value)
    config.set_value("app", "network_transfer_enabled", network_transfer_enabled.value)
    config.set_value("app", "device_name", device_name.value)
    config.set_value("app", "require_pin_for_transfers", require_pin_for_transfers.value)
    config.save(SETTINGS_PATH)
