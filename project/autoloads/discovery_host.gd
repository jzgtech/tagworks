extends Node

const UDP_PORT: int = 8910
const TCP_PORT: int = 8911

var _udp: PacketPeerUDP = PacketPeerUDP.new()
var _tcp_server: TCPServer = TCPServer.new()
var _active_connections: Array[StreamPeerTCP] = []

func _ready() -> void:
	AppSettings.network_transfer_enabled.connect_self_changed(
		func(_origin: Reactive) -> void: _apply_state()
	)
	_apply_state()


func _apply_state() -> void:
	if AppSettings.network_transfer_enabled.value:
		start()
	else:
		stop()


func start() -> void:
	if _udp.is_bound():
		return # already running
	_udp.bind(UDP_PORT)
	_tcp_server.listen(TCP_PORT)
	set_process(true)


func stop() -> void:
	set_process(false)
	_udp.close()
	_tcp_server.stop()
	for peer: StreamPeerTCP in _active_connections:
		peer.disconnect_from_host()
	_active_connections.clear()


func _process(_delta: float) -> void:
	_poll_discovery_requests()
	_poll_incoming_connections()


func _poll_discovery_requests() -> void:
	while _udp.get_available_packet_count() > 0:
		var packet: String = _udp.get_packet().get_string_from_utf8()
		var sender_ip: String = _udp.get_packet_ip()
		var sender_port: int = _udp.get_packet_port()
		if packet == "DISCOVER_REQUEST":
			var response: String = "DISCOVER_RESPONSE|%s|%d" % [
				AppSettings.device_name.value, TCP_PORT
			]
			_udp.set_dest_address(sender_ip, sender_port)
			_udp.put_packet(response.to_utf8_buffer())


func _poll_incoming_connections() -> void:
	if _tcp_server.is_connection_available():
		var peer: StreamPeerTCP = _tcp_server.take_connection()
		_active_connections.append(peer)
		# Hand off to TransferManager for PIN confirmation / project listing
		TransferManager.handle_incoming_connection(peer)
