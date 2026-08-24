class_name DiscoveryClient
extends Node

signal host_found(host_info: Dictionary)

const UDP_PORT: int = 8910

var available_hosts: Array[Dictionary] = []
var _udp: PacketPeerUDP = PacketPeerUDP.new()


func _ready() -> void:
    _udp.set_broadcast_enabled(true)
    _udp.bind(0)
    set_process(true)
    broadcast_request()


func broadcast_request() -> void:
    _udp.set_dest_address("255.255.255.255", UDP_PORT)
    _udp.put_packet("DISCOVER_REQUEST".to_utf8_buffer())


func reset() -> void:
    available_hosts.clear()
    broadcast_request()


func _process(_delta: float) -> void:
    while _udp.get_available_packet_count() > 0:
        var packet: String = _udp.get_packet().get_string_from_utf8()
        var sender_ip: String = _udp.get_packet_ip()
        if packet.begins_with("DISCOVER_RESPONSE"):
            var parts: PackedStringArray = packet.split("|")
            var host_info: Dictionary = {
                "name": parts[1],
                "ip": sender_ip,
                "port": int(parts[2]),
            }
            if not available_hosts.any(func(h: Dictionary) -> bool: return h.ip == host_info.ip):
                available_hosts.append(host_info)
                host_found.emit(host_info)


func _exit_tree() -> void:
    _udp.close()
