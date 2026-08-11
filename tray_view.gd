@tool
class_name SudorisTray
extends Control

signal piece_picked(piece_id: int, global_position: Vector2)
signal rotate_requested(piece_id: int)

var pieces: Array = []
var active_slots: Array[int] = [-1, -1, -1]

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP

func configure(new_pieces: Array, new_slots: Array[int]) -> void:
	pieces = new_pieces
	active_slots = new_slots
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
	draw_style_box(_panel_style(), Rect2(Vector2.ZERO, size))
	var slot_width := size.x / 3.0
	for slot in 3:
		var center_x := slot_width * (slot + 0.5)
		var id := active_slots[slot]
		var card := _card_rect(slot, slot_width)
		var rotate_rect := _rotate_rect(card)
		var rotate_center := rotate_rect.get_center()
		draw_style_box(_slot_style(id != -1), card)
		draw_arc(rotate_center, 7, -2.4, 1.6, 16, Color("#9eb765"), 1.8, true)
		draw_line(rotate_center + Vector2(-5, -5), rotate_center + Vector2(-9, -1), Color("#9eb765"), 1.8)
		draw_line(rotate_center + Vector2(-5, -5), rotate_center + Vector2(0, -4), Color("#9eb765"), 1.8)
		if id == -1 or id >= pieces.size():
			draw_string(ThemeDB.fallback_font, Vector2(center_x - 18, 72), "USED", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("#617044"))
			continue
		var cells: Array[Vector2i] = pieces[id].rotated_cells()
		var max_x := 0
		var max_y := 0
		for cell in cells:
			max_x = max(max_x, cell.x)
			max_y = max(max_y, cell.y)
		var unit := 17.0
		var piece_center_y := card.position.y + card.size.y * 0.56
		var start := Vector2(center_x - (max_x + 1) * unit * 0.5, piece_center_y - (max_y + 1) * unit * 0.5)
		for cell in cells:
			var cell_rect := Rect2(start + Vector2(cell) * unit, Vector2.ONE * unit)
			draw_rect(cell_rect.grow(-0.8), pieces[id].color.darkened(0.42))
			draw_rect(cell_rect.grow(-2.6), pieces[id].color)
			draw_line(cell_rect.position + Vector2(3, 3), Vector2(cell_rect.end.x - 3, cell_rect.position.y + 3), pieces[id].color.lightened(0.3), 1.0)

func _card_rect(slot: int, slot_width: float) -> Rect2:
	return Rect2(slot * slot_width + 10, 8, slot_width - 20, size.y - 16)

func _rotate_rect(card: Rect2) -> Rect2:
	return Rect2(card.end - Vector2(40, 40), Vector2(36, 36))

func _slot_style(active: bool) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color("#18200f")
	style.border_color = Color("#829b45") if active else Color("#303b20")
	style.set_border_width_all(1)
	style.corner_radius_top_left = 14
	style.corner_radius_top_right = 14
	style.corner_radius_bottom_left = 14
	style.corner_radius_bottom_right = 14
	return style

func _panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color("#273417")
	style.border_color = Color("#4d5e29")
	style.set_border_width_all(1)
	style.corner_radius_top_left = 22
	style.corner_radius_top_right = 22
	style.corner_radius_bottom_left = 22
	style.corner_radius_bottom_right = 22
	style.shadow_color = Color(0.05, 0.08, 0.02, 0.35)
	style.shadow_size = 7
	style.shadow_offset = Vector2(0, 4)
	return style
