# transfer_manager.gd — Autoload singleton
extends Node

const LOG_CATEGORY: String = "Transfer"

# --- Client-side signals ---
signal pin_required
signal auth_failed(attempts_left: int)
signal project_metadata_received(project_name: String, size: int)
signal transfer_progress(bytes_received: int, bytes_total: int)
signal transfer_completed(file_path: String)

# --- Host-side signals ---
signal incoming_connection_request(peer_ip: String, pin_required: bool, pin: String)
signal transfer_sent

# --- Shared ---
signal transfer_failed(reason: String)

const MAX_PIN_ATTEMPTS: int = 3
const PIN_TIMEOUT: float = 30.0

enum Mode { NONE, CLIENT, HOST }
enum ClientState { AWAITING_HELLO, AWAITING_PIN_ENTRY, AWAITING_AUTH_RESULT, AWAITING_METADATA, RECEIVING_FILE, DONE }
enum HostState { AWAITING_AUTH, SENDING_FILE, DONE }

var _mode: Mode = Mode.NONE
var _client_state: ClientState
var _host_state: HostState

var _peer: StreamPeerTCP
var _read_buffer: PackedByteArray = PackedByteArray()

var _expected_pin: String = ""
var _pin_attempts: int = 0
var _pin_timer: Timer
var _host_requires_pin: bool = false

var _incoming_project_name: String = ""
var _expected_size: int = 0
var _received_bytes: int = 0
var _file_buffer: PackedByteArray = PackedByteArray()


func _ready() -> void:
    _pin_timer = Timer.new()
    add_child(_pin_timer)
    _pin_timer.one_shot = true
    _pin_timer.timeout.connect(_on_pin_timeout)
    LogManager.debug("TransferManager ready", LOG_CATEGORY)


func _process(_delta: float) -> void:
    if _peer == null:
        return

    _peer.poll()
    match _peer.get_status():
        StreamPeerTCP.STATUS_CONNECTED:
            _read_incoming()
        StreamPeerTCP.STATUS_ERROR, StreamPeerTCP.STATUS_NONE:
            LogManager.warning("Peer connection lost or errored", LOG_CATEGORY, {"mode": _mode})
            transfer_failed.emit("Connection lost")
            _cleanup()


# =========================================================
# CLIENT SIDE
# =========================================================

func connect_to_host(host_info: Dictionary) -> void:
    _cleanup()
    _mode = Mode.CLIENT
    _client_state = ClientState.AWAITING_HELLO

    LogManager.info("Connecting to host", LOG_CATEGORY, {"ip": host_info.get("ip", ""), "port": host_info.get("port", 0)})

    _peer = StreamPeerTCP.new()
    var err: int = _peer.connect_to_host(host_info.ip, host_info.port)
    if err != OK:
        LogManager.error("Failed to initiate connection to host", LOG_CATEGORY, {"error_code": err, "host_info": host_info})
        transfer_failed.emit("Could not reach host")
        _cleanup()
        return

    set_process(true)


func submit_pin(pin: String) -> void:
    if _mode != Mode.CLIENT:
        LogManager.warning("submit_pin called while not in CLIENT mode", LOG_CATEGORY, {"mode": _mode})
        return
    _client_state = ClientState.AWAITING_AUTH_RESULT
    LogManager.debug("Submitting PIN to host", LOG_CATEGORY)
    _send_control_message({"type": "AUTH", "pin": pin})


func _handle_client_control_message(msg: Dictionary) -> void:
    LogManager.debug("Client received control message", LOG_CATEGORY, {"type": msg.get("type", "?")})
    match msg.get("type", ""):
        "HELLO":
            _host_requires_pin = msg.get("pin_required", false)
            LogManager.info("Received HELLO from host", LOG_CATEGORY, {"pin_required": _host_requires_pin})
            if _host_requires_pin:
                _client_state = ClientState.AWAITING_PIN_ENTRY
                pin_required.emit()
            else:
                _client_state = ClientState.AWAITING_METADATA
        "AUTH_OK":
            LogManager.info("Authentication succeeded", LOG_CATEGORY)
            _client_state = ClientState.AWAITING_METADATA
        "AUTH_FAIL":
            var attempts_left: int = msg.get("attempts_left", 0)
            LogManager.warning("Authentication failed", LOG_CATEGORY, {"attempts_left": attempts_left})
            if attempts_left <= 0:
                LogManager.error("PIN attempts exhausted, aborting transfer", LOG_CATEGORY)
                transfer_failed.emit("Too many incorrect PIN attempts")
                _cleanup()
            else:
                _client_state = ClientState.AWAITING_PIN_ENTRY
                auth_failed.emit(attempts_left)
                pin_required.emit()
        "METADATA":
            _incoming_project_name = msg.get("project_name", "project")
            _expected_size = msg.get("size", 0)
            _received_bytes = 0
            _file_buffer = PackedByteArray()
            _client_state = ClientState.RECEIVING_FILE
            LogManager.info("Received project metadata", LOG_CATEGORY, {
                "project_name": _incoming_project_name,
                "size": _expected_size
            })
            project_metadata_received.emit(_incoming_project_name, _expected_size)
            transfer_progress.emit(0, _expected_size)
        "ERROR":
            var error_message: String = msg.get("message", "Unknown error")
            LogManager.error("Host reported error", LOG_CATEGORY, {"message": error_message})
            transfer_failed.emit(error_message)
            _cleanup()


func _consume_file_bytes() -> bool:
    if _read_buffer.is_empty():
        return false
    var remaining: int = _expected_size - _received_bytes
    var take: int = min(remaining, _read_buffer.size())
    var chunk: PackedByteArray = _read_buffer.slice(0, take)
    _file_buffer.append_array(chunk)
    _read_buffer = _read_buffer.slice(take, _read_buffer.size())
    _received_bytes += take
    transfer_progress.emit(_received_bytes, _expected_size)

    if _received_bytes >= _expected_size:
        LogManager.debug("File fully received, finalizing", LOG_CATEGORY, {"bytes": _received_bytes})
        _finalize_received_file()

    return take > 0


func _finalize_received_file() -> void:
    var target_dir: String = "user://received_projects"
    DirAccess.make_dir_recursive_absolute(target_dir)
    var target_path: String = target_dir.path_join(_incoming_project_name + ".json")

    var file: FileAccess = FileAccess.open(target_path, FileAccess.WRITE)
    if file == null:
        LogManager.critical("Could not write received project to disk", LOG_CATEGORY, {"target_path": target_path})
        transfer_failed.emit("Could not write received project to disk")
        _cleanup()
        return
    file.store_buffer(_file_buffer)
    file.close()

    _client_state = ClientState.DONE
    LogManager.info("Project transfer completed", LOG_CATEGORY, {"target_path": target_path})
    transfer_completed.emit(target_path)
    _cleanup()


# =========================================================
# HOST SIDE
# =========================================================

func handle_incoming_connection(peer: StreamPeerTCP) -> void:
    _cleanup()
    _mode = Mode.HOST
    _peer = peer
    _pin_attempts = 0

    var requires_pin: bool = AppSettings.require_pin_for_transfers.value
    _host_requires_pin = requires_pin

    LogManager.info("Incoming connection accepted", LOG_CATEGORY, {
        "peer_ip": peer.get_connected_host(),
        "pin_required": requires_pin
    })

    set_process(true)

    if requires_pin:
        _expected_pin = _generate_pin()
        _host_state = HostState.AWAITING_AUTH
        _send_control_message({"type": "HELLO", "pin_required": true})
        _pin_timer.start(PIN_TIMEOUT)
        LogManager.debug("Generated PIN for incoming transfer", LOG_CATEGORY, {"pin": _expected_pin})
        incoming_connection_request.emit(peer.get_connected_host(), true, _expected_pin)
    else:
        _expected_pin = ""
        _send_control_message({"type": "HELLO", "pin_required": false})
        incoming_connection_request.emit(peer.get_connected_host(), false, "")
        _host_state = HostState.SENDING_FILE
        LogManager.info("PIN not required, sending project immediately", LOG_CATEGORY)
        _send_project_file()


func _handle_host_control_message(msg: Dictionary) -> void:
    if msg.get("type", "") != "AUTH":
        LogManager.warning("Unexpected control message while awaiting auth", LOG_CATEGORY, {"type": msg.get("type", "?")})
        return

    var submitted_pin: String = msg.get("pin", "")
    _pin_attempts += 1

    LogManager.debug("Received AUTH attempt", LOG_CATEGORY, {"attempt": _pin_attempts})

    if submitted_pin == _expected_pin:
        LogManager.info("Client authenticated successfully", LOG_CATEGORY)
        _pin_timer.stop()
        _send_control_message({"type": "AUTH_OK"})
        _host_state = HostState.SENDING_FILE
        _send_project_file()
    else:
        var attempts_left: int = MAX_PIN_ATTEMPTS - _pin_attempts
        LogManager.warning("Incorrect PIN submitted", LOG_CATEGORY, {"attempts_left": attempts_left})
        _send_control_message({"type": "AUTH_FAIL", "attempts_left": attempts_left})
        if attempts_left <= 0:
            LogManager.error("Client exhausted PIN attempts, aborting", LOG_CATEGORY)
            transfer_failed.emit("Too many incorrect PIN attempts from client")
            _cleanup()


func _send_project_file() -> void:
    var path: String = AppState.current_project.file_path.value
    LogManager.debug("Reading project file for transfer", LOG_CATEGORY, {"path": path})

    var file: FileAccess = FileAccess.open(path, FileAccess.READ)
    if file == null:
        LogManager.error("Could not open project file for reading", LOG_CATEGORY, {"path": path})
        _send_control_message({"type": "ERROR", "message": "Could not read project file"})
        transfer_failed.emit("Could not read project file")
        _cleanup()
        return

    var bytes: PackedByteArray = file.get_buffer(file.get_length())
    file.close()

    var project_name: String = path.get_file().get_basename()
    LogManager.info("Sending project to client", LOG_CATEGORY, {
        "project_name": project_name,
        "size": bytes.size()
    })

    _send_control_message({"type": "METADATA", "project_name": project_name, "size": bytes.size()})
    _peer.put_data(bytes)

    _host_state = HostState.DONE
    LogManager.info("Project sent successfully", LOG_CATEGORY, {"project_name": project_name})
    transfer_sent.emit()
    _cleanup()


func _on_pin_timeout() -> void:
    if _mode == Mode.HOST and _host_state == HostState.AWAITING_AUTH:
        LogManager.warning("Client failed to authenticate within timeout", LOG_CATEGORY, {"timeout": PIN_TIMEOUT})
        transfer_failed.emit("Client did not authenticate in time")
        _cleanup()


# =========================================================
# SHARED: framing + buffer handling
# =========================================================

func _send_control_message(data: Dictionary) -> void:
    var json: String = JSON.stringify(data)
    var payload: PackedByteArray = json.to_utf8_buffer()
    var header: PackedByteArray = PackedByteArray()
    header.resize(4)
    header.encode_u32(0, payload.size())
    _peer.put_data(header)
    _peer.put_data(payload)
    LogManager.debug("Sent control message", LOG_CATEGORY, {"type": data.get("type", "?")})


func _read_incoming() -> void:
    var available: int = _peer.get_available_bytes()
    if available > 0:
        _read_buffer.append_array(_peer.get_data(available)[1])

    var made_progress: bool = true
    while made_progress:
        made_progress = false
        match _mode:
            Mode.CLIENT:
                match _client_state:
                    ClientState.AWAITING_HELLO, ClientState.AWAITING_AUTH_RESULT, ClientState.AWAITING_METADATA:
                        var msg: Variant = _try_extract_control_message()
                        if msg != null:
                            _handle_client_control_message(msg)
                            made_progress = true
                    ClientState.RECEIVING_FILE:
                        made_progress = _consume_file_bytes()
            Mode.HOST:
                match _host_state:
                    HostState.AWAITING_AUTH:
                        var msg: Variant = _try_extract_control_message()
                        if msg != null:
                            _handle_host_control_message(msg)
                            made_progress = true


func _try_extract_control_message() -> Variant:
    if _read_buffer.size() < 4:
        return null
    var length: int = _read_buffer.decode_u32(0)
    if _read_buffer.size() < 4 + length:
        return null
    var payload: PackedByteArray = _read_buffer.slice(4, 4 + length)
    _read_buffer = _read_buffer.slice(4 + length, _read_buffer.size())
    return JSON.parse_string(payload.get_string_from_utf8())


func _generate_pin() -> String:
    randomize()
    return "%04d" % (randi() % 10000)


func _cleanup() -> void:
    LogManager.debug("Cleaning up transfer state", LOG_CATEGORY, {"mode": _mode})
    set_process(false)
    if _peer:
        _peer.disconnect_from_host()
    _peer = null
    _read_buffer = PackedByteArray()
    _file_buffer = PackedByteArray()
    _mode = Mode.NONE
    _pin_timer.stop()
