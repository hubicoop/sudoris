@tool
class_name SudorisJokerBar
extends Control
## The two joker slots under the tray, drawn as big square cards with the joker's
## icon. Tap to use a joker; hold to read what it does. Colours come from the skin.

const SudorisJokers := preload("res://jokers.gd")

signal slot_pressed(slot: int, global_position: Vector2)

## Colours, sprites and font. Use the same skin as the BoardView.
@export var skin: SudorisSkin
## Outline and icon of the slot whose joker is waiting for a tap on the board.
@export var armed_color := Color("#f2d35e")
## Tint of the joker icons.
@export var icon_color := Color("#c4d578")
## Side of a joker card, in pixels (shrinks to fit the bar's height).
@export_range(48.0, 160.0, 1.0) var card_size := 92.0
## Gap between the two cards, in pixels.
@export_range(0.0, 80.0, 1.0) var card_gap := 20.0
## Icon size as a share of the card.
@export_range(0.2, 0.9, 0.05) var icon_scale := 0.62
## Seconds a finger has to stay on a card before its description opens.
@export_range(0.1, 1.5, 0.05) var hold_seconds := 0.4
## Width of the description bubble, in pixels.
@export_range(120.0, 400.0, 1.0) var bubble_width := 250.0
## Shows sample jokers in the editor.
@export var editor_preview := true

var gold := 0
var slots: Array[String] = ["", ""]
## Slot waiting for a tap on the board, or -1.
var armed_slot := -1
## Slot whose Pocket is open (holds or can hold a piece), or -1.
var pocket_slot := -1
var pocket_piece := -1
var pieces: Array = []
var dragging_piece := -1
## Slot under the finger and when it went down, for telling a tap from a hold.
var held_slot := -1
var held_since_ms := 0
## Slot whose description is open, or -1.
var info_slot := -1
var _default_skin := SudorisSkin.new()

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP

func _process(_delta: float) -> void:
	if Engine.is_editor_hint():
		if editor_preview and slots == ["", ""]:
			slots = [SudorisJokers.ERASER, SudorisJokers.LAST_BREATH]
		queue_redraw()
		return
	if held_slot != -1 and info_slot == -1 and Time.get_ticks_msec() - held_since_ms >= hold_seconds * 1000.0:
		show_info(held_slot)

func current_skin() -> SudorisSkin:
	return skin if skin else _default_skin

func configure(new_gold: int, new_slots: Array[String], new_armed_slot: int, new_pocket_slot: int, new_pocket_piece: int, new_pieces: Array, new_dragging_piece: int) -> void:
	gold = new_gold
	slots = new_slots
	armed_slot = new_armed_slot
	pocket_slot = new_pocket_slot
	pocket_piece = new_pocket_piece
	pieces = new_pieces
	dragging_piece = new_dragging_piece
	queue_redraw()

func slot_rect(slot: int) -> Rect2:
	var side := minf(card_size, size.y)
	var total := side * slots.size() + card_gap * (slots.size() - 1)
	var left := (size.x - total) * 0.5
	return Rect2(left + slot * (side + card_gap), (size.y - side) * 0.5, side, side)

## The slot under a point given in canvas coordinates, or -1.
func slot_at_global(global_point: Vector2) -> int:
	var local := get_global_transform_with_canvas().affine_inverse() * global_point
	for slot in slots.size():
		if slot_rect(slot).has_point(local):
			return slot
	return -1

## Opens the description bubble above a slot that holds a joker.
func show_info(slot: int) -> void:
	if slot < 0 or slot >= slots.size() or slots[slot] == "":
		return
	info_slot = slot
	queue_redraw()

func hide_info() -> void:
	info_slot = -1
	queue_redraw()

func _gui_input(event: InputEvent) -> void:
	if Engine.is_editor_hint():
		return
	# Mouse clicks also arrive as emulated touches, so only touches are handled.
	if not (event is InputEventScreenTouch and event.index == 0):
		return
	var slot := -1
	for index in slots.size():
		if slot_rect(index).has_point(event.position):
			slot = index
	if event.pressed:
		hide_info()
		if slot == -1:
			return
		accept_event()
		if slot == pocket_slot and pocket_piece != -1:
			# A piece in the Pocket is dragged out straight away.
			slot_pressed.emit(slot, get_global_transform_with_canvas() * event.position)
			return
		held_slot = slot
		held_since_ms = Time.get_ticks_msec()
		return
	# Finger up: a quick tap uses the joker, a hold only showed its description.
	var was_held := held_slot
	held_slot = -1
	if info_slot != -1:
		hide_info()
		return
	if was_held != -1 and was_held == slot:
		accept_event()
		slot_pressed.emit(slot, get_global_transform_with_canvas() * event.position)

func _draw() -> void:
	var look := current_skin()
	for slot in slots.size():
		var rect := slot_rect(slot)
		var id: String = slots[slot]
		var border := look.slot_border_active_color if id != "" else look.slot_border_empty_color
		var width := 1
		if slot == armed_slot or slot == pocket_slot:
			border = armed_color
			width = 3
		draw_style_box(look.rounded_box(look.slot_color, 16, border, width), rect)
		if id == "":
			continue
		if slot == pocket_slot and pocket_piece != -1 and pocket_piece < pieces.size():
			_draw_pocket_piece(look, rect)
			continue
		var icon := SudorisJokers.icon(id)
		if icon:
			var side := rect.size.x * icon_scale
			var tint := armed_color if slot == armed_slot or slot == pocket_slot else icon_color
			draw_texture_rect(icon, Rect2(rect.get_center() - Vector2.ONE * side * 0.5, Vector2.ONE * side), false, tint)
	if info_slot != -1:
		_draw_info(look, info_slot)

func _draw_pocket_piece(look: SudorisSkin, rect: Rect2) -> void:
	var cells: Array[Vector2i] = pieces[pocket_piece].rotated_cells()
	var extent := Vector2i.ZERO
	for cell in cells:
		extent = Vector2i(maxi(extent.x, cell.x), maxi(extent.y, cell.y))
	var unit := minf(look.tray_block_size * 0.75, (rect.size.x - 16.0) / (maxi(extent.x, extent.y) + 1))
	var start := rect.get_center() - Vector2(extent + Vector2i.ONE) * unit * 0.5
	for cell in cells:
		var cell_rect := Rect2(start + Vector2(cell) * unit, Vector2.ONE * unit)
		if pocket_piece == dragging_piece:
			draw_rect(cell_rect.grow(-1.5), Color(pieces[pocket_piece].color, 0.35), false, 1.5)
		else:
			look.draw_block(self, cell_rect.grow(-0.6), pieces[pocket_piece].color)

## A bubble above the card with the joker's name and what it does.
func _draw_info(look: SudorisSkin, slot: int) -> void:
	var id := slots[slot]
	var font := look.font()
	var card := slot_rect(slot)
	var pad := 12.0
	var text_width := bubble_width - pad * 2.0
	var body := tr(SudorisJokers.text(id))
	var body_size := font.get_multiline_string_size(body, HORIZONTAL_ALIGNMENT_LEFT, text_width, 13)
	var height := pad * 2.0 + 20.0 + body_size.y
	var x := clampf(card.get_center().x - bubble_width * 0.5, 0.0, maxf(0.0, size.x - bubble_width))
	var bubble := Rect2(x, card.position.y - height - 10.0, bubble_width, height)
	var box := look.rounded_box(look.board_panel_color, 14, look.board_border_color, 2)
	box.shadow_color = Color(0.0, 0.0, 0.0, 0.35)
	box.shadow_size = 6
	draw_style_box(box, bubble)
	# Little arrow pointing at the card.
	var tip := Vector2(card.get_center().x, bubble.end.y + 8.0)
	draw_colored_polygon(PackedVector2Array([tip, tip + Vector2(-9, -10), tip + Vector2(9, -10)]), look.board_panel_color)
	var title := tr(SudorisJokers.joker_name(id))
	if SudorisJokers.is_passive(id):
		title += "  ·  " + tr("PASSIVE")
	draw_string(font, bubble.position + Vector2(pad, pad + 14.0), title, HORIZONTAL_ALIGNMENT_LEFT, text_width, 15, look.board_border_color)
	draw_multiline_string(font, bubble.position + Vector2(pad, pad + 36.0), body, HORIZONTAL_ALIGNMENT_LEFT, text_width, 13, -1, look.region_line_color)
