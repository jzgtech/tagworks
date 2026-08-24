extends Window

@onready var host_list: ItemList = %HostList
@onready var connect_button: Button = %TransferButton
@onready var refresh_button: Button = %RefreshButton
@onready var close_button: Button = %CloseButton
@onready var title_label: Label = %StatusLabel

const SCAN_DURATION: float = 3.0

var _client: DiscoveryClient
var _scan_timer: Timer

func _ready() -> void:
    close_requested.connect(_on_cancel_pressed)
    refresh_button.pressed.connect(_on_refresh_pressed)
    connect_button.pressed.connect(_on_connect_pressed)
    host_list.item_selected.connect(_on_host_selected)

    _client = DiscoveryClient.new()
    add_child(_client)
    _client.host_found.connect(_on_host_found)

    _scan_timer = Timer.new()
    add_child(_scan_timer)
    _scan_timer.one_shot = true
    _scan_timer.timeout.connect(_on_scan_timeout)

    _start_scan()


func _start_scan() -> void:
    host_list.clear()
    host_list.visible = false
    connect_button.disabled = true
    title_label.text = "Searching for devices..."

    _client.reset()
    _scan_timer.start(SCAN_DURATION)


func _on_host_found(host_info: Dictionary) -> void:
    host_list.add_item("%s (%s)" % [host_info.name, host_info.ip])
    host_list.visible = true
    title_label.text = "Devices found"


func _on_scan_timeout() -> void:
    if _client.available_hosts.is_empty():
        title_label.text = "No devices found"
    else:
        title_label.text = "Select a device"


func _on_refresh_pressed() -> void:
    _start_scan()


func _on_host_selected(_index: int) -> void:
    connect_button.disabled = false


func _on_connect_pressed() -> void:
    var index: int = host_list.get_selected_items()[0]
    var host_info: Dictionary = _client.available_hosts[index]
    TransferManager.connect_to_host(host_info)
    hide()


func _on_cancel_pressed() -> void:
    hide()
    queue_free()  # _client is a child, freed automatically
