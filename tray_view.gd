@tool
class_name SudorisTray
extends Control
## The three piece slots under the board. Colours and sprites come from the skin.

signal piece_picked(piece_id: int, global_position: Vector2)
signal rotate_requested(piece_id: int)

## Colours, sprites and font. Use the same skin as the BoardView.
@export var skin: SudorisSkin
## Shows sample pieces in the editor.
@export var editor_preview := true

var pieces: Array = []
var active_slots: Array[int] = [-1, -1, -1]
var dragging_piece := -1
var _default_skin := SudorisSkin.new()

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP

func _process(_delta: float) -> void:
	if Engine.is_editor_hint():
		if editor_preview and pieces.is_empty():
			_build_preview()
		queue_redraw()

func current_skin() -> SudorisSkin:
	return skin if skin else _default_skin

func configure(new_pieces: Array, new_slots: Array[int], new_dragging_piece := -1) -> void:
	pieces = new_pieces
	active_slots = new_slots
	dragging_piece = new_dragging_piece
	queue_redraw()

func _gui_input(event: InputEvent) -> void:
	if Engine.is_editor_hint() or not (event is InputEventMouseButton or event is InputEventScreenTouch):
		return
	var pressed := false
	var position := Vector2.ZERO
	if event is InputEventMouseButton:
		pressed = event.pressed
		position = event.position
	elif event is InputEventScreenTouch:
		pressed = event.pressed
		position = event.position
	if not pressed:
		return
	var slot_width := size.x / 3.0
	var slot := clampi(int(position.x / slot_width), 0, 2)
	var piece_id := active_slots[slot]
	if piece_id == -1:
		return
	var card := _card_rect(slot, slot_width)
	var rotate_area := _rotate_rect(card)
	if rotate_area.has_point(position):
		rotate_requested.emit(piece_id)
	else:
		piece_picked.emit(piece_id, get_global_transform_with_canvas() * position)

func _draw() -> void:
	var look := current_skin()
	var panel := look.rounded_box(look.tray_panel_color, 22, look.tray_border_color, 1)
	panel.shadow_color = Color(0.05, 0.08, 0.02, 0.35)
	panel.shadow_size = 7
	panel.shadow_offset = Vector2(0, 4)
	draw_style_box(panel, Rect2(Vector2.ZERO, size))
	var slot_width := size.x / 3.0
	for slot in 3:
		var center_x := slot_width * (slot + 0.5)
		var id := active_slots[slot]
		var card := _card_rect(slot, slot_width)
		var rotate_rect := _rotate_rect(card)
		var border := look.slot_border_active_color if id != -1 else look.slot_border_empty_color
		draw_style_box(look.rounded_box(look.slot_color, 14, border, 1), card)
		draw_style_box(look.rounded_box(look.rotate_button_color, 10, look.rotate_button_border_color, 1), rotate_rect)
		_draw_rotate_icon(look, rotate_rect.get_center())
		if id == -1 or id >= pieces.size():
			continue
		var cells: Array[Vector2i] = pieces[id].rotated_cells()
		# The held piece leaves only a faint outline behind in its slot.
		var held := id == dragging_piece
		var max_x := 0
		var max_y := 0
		for cell in cells:
			max_x = max(max_x, cell.x)
			max_y = max(max_y, cell.y)
		var unit := look.tray_block_size
		var piece_area_bottom := rotate_rect.position.y - 4.0
		var piece_center_y := card.position.y + (piece_area_bottom - card.position.y) * 0.5
		var start := Vector2(center_x - (max_x + 1) * unit * 0.5, piece_center_y - (max_y + 1) * unit * 0.5)
		for cell in cells:
			var cell_rect := Rect2(start + Vector2(cell) * unit, Vector2.ONE * unit)
			if held:
				draw_rect(cell_rect.grow(-1.5), Color(pieces[id].color, 0.35), false, 1.5)
				continue
			look.draw_block(self, cell_rect.grow(-0.8), pieces[id].color)

func _draw_rotate_icon(look: SudorisSkin, center: Vector2) -> void:
	if look.rotate_icon:
		var half := Vector2.ONE * 14.0
		draw_texture_rect(look.rotate_icon, Rect2(center - half, half * 2.0), false, look.rotate_icon_color)
		return
	draw_arc(center, 12, -2.4, 1.6, 24, look.rotate_icon_color, 2.8, true)
	draw_line(center + Vector2(-8, -8), center + Vector2(-14, -2), look.rotate_icon_color, 2.8)
	draw_line(center + Vector2(-8, -8), center + Vector2(0, -6), look.rotate_icon_color, 2.8)

func _card_rect(slot: int, slot_width: float) -> Rect2:
	return Rect2(slot * slot_width + 10, 8, slot_width - 20, size.y - 16)

func _rotate_rect(card: Rect2) -> Rect2:
	return Rect2(Vector2(card.position.x + 6, card.end.y - 47), Vector2(card.size.x - 12, 41))

# --- Editor preview -------------------------------------------------------------

class PreviewPiece:
	var color: Color
	var cells: Array[Vector2i]
	func _init(new_color: Color, new_cells: Array[Vector2i]) -> void:
		color = new_color
		cells = new_cells
	func rotated_cells() -> Array[Vector2i]:
		return cells

func _build_preview() -> void:
	pieces = [
		PreviewPiece.new(Color("#ef5d50"), [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1)] as Array[Vector2i]),
		PreviewPiece.new(Color("#e46aa8"), [Vector2i(0, 0), Vector2i(0, 1), Vector2i(1, 1), Vector2i(1, 2)] as Array[Vector2i]),
		PreviewPiece.new(Color("#4ec982"), [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(1, 1)] as Array[Vector2i]),
	]
	active_slots = [0, 1, 2]
