class_name MockOpcUaServer
extends OpcUaServer

# Instantiate the noise generator
var _noise: FastNoiseLite = FastNoiseLite.new()

func _init_client() -> void:
	# Intentionally do not instantiate GodotOpcUa to avoid crashing/linking 
	_client = null 
	name = "MockOpcUaServerConnection_%s" % config.id.value
	
	# Configure the noise profile (Optional)
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_noise.frequency = 0.01 

func _process_iteration() -> void:
	# Use time-based tracking to sample a continuous, smooth noise wave over time
	var current_time: float = Time.get_ticks_msec() * 0.05
	
	for subscription: ReactiveOpcUaSubscription in config.subscriptions.values():
		for tag: ReactiveOpcUaTag in subscription.tags.values():
			# Use a unique identifier (like the tag's hash or name) as a Y-coordinate 
			# so different tags don't return the exact same value stream
			var tag_offset: float = 0.0
			var noise_val: float = _noise.get_noise_2d(current_time, tag_offset) # Range [-1.0, 1.0]

			match tag.tag_type.value:
				ReactiveOpcUaTag.TagType.BOOL:
					# True if noise is positive, false if negative
					tag.value.value = noise_val > 0.0
					
				ReactiveOpcUaTag.TagType.INT32, ReactiveOpcUaTag.TagType.UINT32:
					# Remap [-1.0, 1.0] to [0, 100]
					var normalized: float = (noise_val + 1.0) / 2.0
					tag.value.value = int(normalized * 100.0)
					
				ReactiveOpcUaTag.TagType.FLOAT, ReactiveOpcUaTag.TagType.DOUBLE:
					# Remap [-1.0, 1.0] to [0.0, 20.0]
					var normalized: float = (noise_val + 1.0) / 2.0
					tag.value.value = normalized * 20.0
					
				ReactiveOpcUaTag.TagType.STRING:
					tag.value.value = "Noise: %.2f" % noise_val

func _execute_connect() -> Error:
	# Instantly emulate a successful TCP handshake/session creation
	return OK

func _execute_disconnect() -> void:
	# No physical hardware sockets or C++ cleanups needed
	pass

func _rebuild_subscription_backend(_subscription: OpcUaSubscription) -> void:
	pass

func _teardown_subscription_backend(_subscription: OpcUaSubscription) -> void:
	pass

func _execute_write(_node_id: OpcUaNodeId, _value: Variant) -> bool:
	return true
