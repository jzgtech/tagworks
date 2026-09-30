extends Tree

const BUTTON_ID_ADD: int = 5
const BUTTON_ID_DELETE: int = 10

var hovered_item: TreeItem = null
var placeholder: PlaceholderTexture2D = PlaceholderTexture2D.new()

func _ready() -> void:
	placeholder.size = Vector2(16, 16)
	set_process_input(true)
	button_clicked.connect(_on_button_clicked)
	mouse_exited.connect(_on_mouse_exited)

func _gui_input(event: InputEvent) -> void:
	if AppState.runtime_only.value:
		return
	if event is InputEventMouseMotion:
		var mouse_pos: Vector2 = get_local_mouse_position()
		var current_item: TreeItem = get_item_at_position(mouse_pos)
		
		# Only trigger if the item actually changes
		if current_item != hovered_item:
			if hovered_item:
				_on_item_exited(hovered_item)
			
			hovered_item = current_item
			
			if hovered_item:
				_on_item_entered(hovered_item)

func _on_item_entered(item: TreeItem) -> void:
	if item and is_instance_valid(item):
		# Fix 1: Clear buttons first to ensure duplicates are never made
		_clear_item_buttons(item)
		
		item.add_button(0, placeholder, BUTTON_ID_ADD, false, "Add Child Page")
		item.add_button(0, placeholder, BUTTON_ID_DELETE, false, "Delete Page")

func _on_item_exited(item: TreeItem) -> void:
	if item and is_instance_valid(item):
		_clear_item_buttons(item)
	# Fix 2: Don't clear hovered_item here, handle it in the event loop

# Fix 3: Extracted logic to completely ensure buttons are gone
func _clear_item_buttons(item: TreeItem) -> void:
	if item and is_instance_valid(item):
		# Wipes every button in column 0 safely and instantly
		item.clear_buttons() 

func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_EXIT:
		_clear_all_hover_states()

func _on_mouse_exited() -> void:
	_clear_all_hover_states()

# Fix 4: Centralized fallback cleanup function
func _clear_all_hover_states() -> void:
	if hovered_item and is_instance_valid(hovered_item):
		_clear_item_buttons(hovered_item)
	hovered_item = null

func _on_button_clicked(item: TreeItem, _column: int, id: int, mouse_button_idx: int) -> void:
	var page: ReactivePage = item.get_metadata(0) as ReactivePage
	if mouse_button_idx == MOUSE_BUTTON_LEFT:
		if id == BUTTON_ID_ADD:
			var project: ReactiveProject = AppState.current_project

			# Resolve a unique name
			var resolved: String = "New Page"
			var offset: int = 1
			while project.find_page_name(resolved) != null:
				resolved = "New Page" + " " + str(offset)
				offset  += 1

			if page != null and not page.page_id.value.is_empty():
				var new_page: ReactivePage = ReactivePage.create(resolved, page.children)
				page.add_child_page(new_page)
			else:
				var new_page: ReactivePage = ReactivePage.create(resolved, AppState.current_project.pages)
				project.add_page(new_page)
		elif id == BUTTON_ID_DELETE:
			AppState.current_project.remove_page(page.page_id.value)
