class_name OpcUaServer
extends Node

var config: ReactiveOpcUaServer

var _client: GodotOpcUa
var _poll_accum_sec: float = 0.0
var _subscriptions: Dictionary = {}

var client: GodotOpcUa:
	get: return _client

func _init(cfg: ReactiveOpcUaServer) -> void:
	config = cfg
	name = "OpcUaServerConnection_%s" % config.id.value
	config.connect_self_changed(_on_config_changed)
	_init_client() # <── Abstracted out so subclass can override
	_rebuild_subscriptions_from_config()

# Virtual method overridden by Mock
func _init_client() -> void:
	_client = GodotOpcUa.new()

func _process(delta: float) -> void:
	if not _is_connected():
		return
	_poll_accum_sec += delta
	var interval: float = maxf(config.poll_interval_sec.value, 0.001)
	if _poll_accum_sec < interval:
		return
	_poll_accum_sec = 0.0

	# Overridden by subclass to skip C++ calls
	_process_iteration()

# Virtual method overridden by Mock
func _process_iteration() -> void:
	var err: Error = _client.iterate(1)
	if err != OK:
		_handle_iterate_error(err)

func _exit_tree() -> void:
	disconnect_from_server()

# ── Reactive binding ──────────────────────────────────────────────────────

func _on_config_changed(_origin: Reactive) -> void:
	var was_connected: bool = _is_connected()
	if was_connected:
		disconnect_from_server()
	_rebuild_subscriptions_from_config()
	if was_connected:
		connect_to_server()

# ── Subscription (re)build ───────────────────────────────────────────────

func _rebuild_subscriptions_from_config() -> void:
	for subscription_id: String in _subscriptions.keys().duplicate():
		_teardown_subscription(subscription_id)

	var seen_ids: Dictionary = {}
	for sub_cfg: ReactiveOpcUaSubscription in config.subscriptions.values():
		var subscription_id: String = sub_cfg.id.value
		if seen_ids.has(subscription_id):
			push_warning("OpcUaServerConnection [%s]: duplicate subscription id '%s' — skipping duplicate." % [config.id.value, subscription_id])
			continue
		seen_ids[subscription_id] = true
		_spawn_subscription(sub_cfg)

func _spawn_subscription(sub_cfg: ReactiveOpcUaSubscription) -> void:
	var subscription: OpcUaSubscription = OpcUaSubscription.new(sub_cfg)
	_subscriptions[sub_cfg.id.value] = subscription

	if _is_connected():
		_rebuild_subscription_backend(subscription)

# Virtual method overridden by Mock
func _rebuild_subscription_backend(subscription: OpcUaSubscription) -> void:
	subscription.rebuild(_client)

func _teardown_subscription(subscription_id: String) -> void:
	var subscription: OpcUaSubscription = _subscriptions.get(subscription_id)
	if subscription != null:
		_teardown_subscription_backend(subscription)
	_subscriptions.erase(subscription_id)

# Virtual method overridden by Mock
func _teardown_subscription_backend(subscription: OpcUaSubscription) -> void:
	subscription.teardown(_client)

# ── Connection ────────────────────────────────────────────────────────────

func connect_to_server() -> bool:
	if _is_connected():
		return true

	config.set_connecting()
	
	# Delegate connection routine to make mocking straightforward
	var err: Error = _execute_connect()

	if err != OK:
		var message: String = "Connection attempt failed: %s" % error_string(err)
		push_warning("OpcUaServerConnection [%s]: %s" % [config.id.value, message])
		config.set_connection_failed(message)
		return false

	_rebuild_all_subscriptions()
	_poll_accum_sec = 0.0
	config.set_connected()
	return true

# Virtual method overridden by Mock
func _execute_connect() -> Error:
	if config.username.value.is_empty():
		return _client.connect_to_server(config.endpoint_url.value)
	else:
		return _client.connect_with_credentials(
			config.endpoint_url.value, config.username.value, config.password.value
		)

func disconnect_from_server() -> bool:
	if not _is_connected():
		return false

	_execute_disconnect()
	config.set_disconnected()
	return true

# Virtual method overridden by Mock
func _execute_disconnect() -> void:
	for subscription: OpcUaSubscription in _subscriptions.values():
		subscription.delete(_client)
	_client.disconnect_server()

func teardown() -> void:
	disconnect_from_server()
	for subscription_id: String in _subscriptions.keys().duplicate():
		_teardown_subscription(subscription_id)
	queue_free()

# ── Poll error handling ─────────────────────────────────────────────────

func _handle_iterate_error(err: Error) -> void:
	match err:
		Error.ERR_CONNECTION_ERROR, Error.ERR_DOES_NOT_EXIST:
			var message: String = "Connection lost during polling: %s" % error_string(err)
			push_warning("OpcUaServerConnection [%s]: %s" % [config.id.value, message])
			config.set_connection_failed(message)
		Error.ERR_TIMEOUT:
			push_warning("OpcUaServerConnection [%s]: iterate() timed out." % config.id.value)
		_:
			push_warning("OpcUaServerConnection [%s]: iterate() error: %s" % [config.id.value, error_string(err)])

# ── Write ─────────────────────────────────────────────────────────────────

func write_tag(node_id: OpcUaNodeId, value: Variant) -> bool:
	return _execute_write(node_id, value)

# Virtual method overridden by Mock
func _execute_write(node_id: OpcUaNodeId, value: Variant) -> bool:
	return _client.write_node(node_id, value)

# ── Tag / subscription lookup ────────────────────────────────────────────────

func find_subscription_for_tag(node_id: OpcUaNodeId) -> OpcUaSubscription:
	for subscription: OpcUaSubscription in _subscriptions.values():
		if subscription.has_tag(node_id):
			return subscription
	return null

func get_tag(node_id: OpcUaNodeId) -> ReactiveOpcUaTag:
	var subscription: OpcUaSubscription = find_subscription_for_tag(node_id)
	return subscription.get_tag(node_id) if subscription != null else null

# ── Accessors ─────────────────────────────────────────────────────────────

func is_server_connected() -> bool:
	return _is_connected()

func get_active_subscription_count() -> int:
	return _subscriptions.size()

func get_subscription_ids() -> Array:
	return _subscriptions.keys()

func get_subscription(subscription_id: String) -> OpcUaSubscription:
	return _subscriptions.get(subscription_id, null)

func _rebuild_all_subscriptions() -> void:
	for subscription: OpcUaSubscription in _subscriptions.values():
		_rebuild_subscription_backend(subscription)

# ── Internal helpers ──────────────────────────────────────────────────────

func _is_connected() -> bool:
	return config.connection_status.value == ReactiveOpcUaServer.ConnectionStatus.CONNECTED
