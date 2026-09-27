class_name MockOpcUaServer
extends OpcUaServer

# Maps node_id (or its String format) -> Variant value
var _mock_store: Dictionary = {}

func _init_client() -> void:
	# Intentionally do not instantiate GodotOpcUa to avoid crashing/linking 
	_client = null 
	name = "MockOpcUaServerConnection_%s" % config.id.value

func _process_iteration() -> void:
	# Here you can optionally simulate value fluctuations or counter increments over time
	pass

func _execute_connect() -> Error:
	# Instantly emulate a successful TCP handshake/session creation
	return OK

func _execute_disconnect() -> void:
	# No physical hardware sockets or C++ cleanups needed
	pass

func _rebuild_subscription_backend(subscription: OpcUaSubscription) -> void:
	# Push initial cached mock values down to the UI tags right on subscription startup
	for node_id in subscription.get_tag_node_ids():
		if _mock_store.has(node_id):
			var tag = subscription.get_tag(node_id)
			if tag:
				tag.value.set_value(_mock_store[node_id])

func _teardown_subscription_backend(subscription: OpcUaSubscription) -> void:
	pass

func _execute_write(node_id: OpcUaNodeId, value: Variant) -> bool:
	# 1. Update our mock data storage
	_mock_store[node_id] = value
	
	# 2. Instantly update the reactive UI graph so the application believes the PLC took it
	var tag: ReactiveOpcUaTag = get_tag(node_id)
	if tag:
		tag.value.set_value(value)
		
	return true
