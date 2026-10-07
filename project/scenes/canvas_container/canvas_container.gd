class_name CanvasContainer
extends VBoxContainer

const CANVAS_SCENE: PackedScene = preload(
	"res://scenes/canvas/canvas.tscn"
)

const META_PAGE_ID: String = "page_id"

# Nodes we now manage explicitly
@onready var tab_bar: TabBar = %TabBar
@onready var page_container: Control = %PanelContainer # Where pages are added

var current_tab: int = -1:
	set(value):
		current_tab = value
		_update_visible_page()

# ── Lifecycle ─────────────────────────────────────────────────────────────────

func _ready() -> void:
	AppState.active_page.connect_self_changed(_on_active_page_changed)
	AppState.current_project.pages.connect_self_changed(_on_pages_changed)

	# Configure the standalone TabBar settings directly
	tab_bar.tab_close_display_policy = TabBar.CLOSE_BUTTON_SHOW_ACTIVE_ONLY
	tab_bar.close_with_middle_mouse  = true
	
	# Connect to the independent TabBar signals
	tab_bar.tab_changed.connect(_on_tab_changed)
	tab_bar.tab_close_pressed.connect(_on_tab_close_pressed)

	_rebuild_tabs()

# ── Signal Handlers ───────────────────────────────────────────────────────────

func _on_tab_close_pressed(tab_index: int) -> void:
	if tab_index < 0 or tab_index >= page_container.get_child_count():
		return

	var tab_node: Node = page_container.get_child(tab_index)
	if tab_node.is_queued_for_deletion():
		return

	if tab_node.has_meta(META_PAGE_ID):
		var closed_page_id: String = tab_node.get_meta(META_PAGE_ID)

		if AppState.active_page.value != null and AppState.active_page.value.page_id.value == closed_page_id:
			AppState.active_page.value = null
		if AppState.focused_page.value != null and AppState.focused_page.value.page_id.value == closed_page_id:
			AppState.focused_page.value = null

	# Remove from the TabBar ui layout
	tab_bar.remove_tab(tab_index)
	tab_node.queue_free()

func _on_pages_changed(_reactive: ReactiveArray) -> void:
	_rebuild_tabs()

func _on_active_page_changed(active_page: ReactiveVariant) -> void:
	if active_page.value == null:
		return

	var page_id: String = active_page.value.page_id.value if active_page.value.page_id else ""
	if page_id.is_empty():
		return

	var tab_index: int = _find_tab_index_by_page_id(page_id)
	if tab_index != -1:
		tab_bar.current_tab = tab_index
		current_tab = tab_index
	else:
		_create_tab_for_page(active_page.value as ReactivePage)

func _on_tab_changed(tab: int) -> void:
	current_tab = tab
	var page_id: String = _get_current_page_id()
	if page_id.is_empty():
		return
	var page: ReactivePage = AppState.current_project.find_page_id(page_id)
	if page != null:
		AppState.active_page.value = page

# ── Tab Management ────────────────────────────────────────────────────────────

func _rebuild_tabs() -> void:
	var current_ids: Dictionary = {}
	for item: Variant in AppState.current_project.pages.values():
		var page: ReactivePage = item as ReactivePage
		if page != null:
			current_ids[page.page_id.value] = page

	# Match tabs against active data
	for i: int in range(page_container.get_child_count() - 1, -1, -1):
		var tab: Node = page_container.get_child(i)
		if tab.has_meta(META_PAGE_ID):
			var page_id: String = tab.get_meta(META_PAGE_ID)
			if not current_ids.has(page_id):
				tab_bar.remove_tab(i)
				tab.queue_free()

func _create_tab_for_page(page: ReactivePage) -> void:
	var scroll: ScrollContainer        = ScrollContainer.new()
	scroll.name                        = "Scroll_%s" % page.page_id.value
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	scroll.set_meta(META_PAGE_ID, page.page_id.value)

	var canvas: WidgetCanvas            = CANVAS_SCENE.instantiate()
	canvas.name                         = "Canvas_%s" % page.page_id.value
	canvas.custom_minimum_size          = Vector2(600, 600)
	canvas.size_flags_horizontal        = Control.SIZE_SHRINK_BEGIN
	canvas.size_flags_vertical          = Control.SIZE_SHRINK_BEGIN
	canvas.data                         = page.canvas

	scroll.add_child(canvas)
	page_container.add_child(scroll) # Add to our new container node

	# Add the layout tag entry into our visual TabBar header
	tab_bar.add_tab(page.page_name.value)
	var tab_index: int = tab_bar.get_tab_count() - 1

	var reactive_page: ReactivePage = AppState.current_project.find_page_id(page.page_id.value)
	if reactive_page != null:
		reactive_page.canvas.is_dirty.changed.connect(
			func() -> void: _on_canvas_dirty_changed(tab_index, reactive_page.canvas.is_dirty.value)
		)

	canvas.load_page(page)

	tab_bar.current_tab = tab_index
	current_tab = tab_index
	show()

func _update_visible_page() -> void:
	for i: int in range(page_container.get_child_count()):
		var child: Control = page_container.get_child(i) as Control
		if child:
			child.visible = (i == current_tab)

# ── Internal Helpers ──────────────────────────────────────────────────────────

func _get_current_page_id() -> String:
	if tab_bar.get_tab_count() == 0 or current_tab >= page_container.get_child_count():
		return ""
	var container: Node = page_container.get_child(current_tab)
	if container.has_meta(META_PAGE_ID):
		return container.get_meta(META_PAGE_ID)
	return ""

func _find_tab_index_by_page_id(page_id: String) -> int:
	for i: int in range(page_container.get_child_count()):
		var tab: Node = page_container.get_child(i)
		if tab.is_queued_for_deletion():
			continue
		if tab.has_meta(META_PAGE_ID) and tab.get_meta(META_PAGE_ID) == page_id:
			return i
	return -1

# ── Dirty Indicator ───────────────────────────────────────────────────────────

func _on_canvas_dirty_changed(tab_index: int, dirty: bool) -> void:
	if tab_index < 0 or tab_index >= tab_bar.get_tab_count():
		return

	var title: String = tab_bar.get_tab_title(tab_index).trim_suffix(" *")
	tab_bar.set_tab_title(tab_index, title + (" *" if dirty else ""))
