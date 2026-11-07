class_name SudorisPieceIcon
extends Control
## A small tappable picture of a piece, used in the joker windows. With
## editable on, tapping a square turns it on or off (for the Build joker).

signal pressed
signal cell_toggled(cell: Vector2i)

var skin: SudorisSkin
var cells: Array[Vector2i] = []
var color := Color.WHITE
var selected := false
## Draw a grid of this many squares a side whose squares can be tapped.
var editable_size := 0
var _default_skin := SudorisSkin.new()

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP

func current_skin() -> SudorisSkin:
	return skin if skin else _default_skin

func _gui_input(event: InputEvent) -> void:
	# Mouse clicks also arrive as emulated touches, so only touches are handled.
	if not (event is InputEventScreenTouch and not event.pressed and event.index == 0):
		return
	accept_event()
	if editable_size > 0:
		var unit := _unit()
		var origin := _grid_origin(unit)
		var cell := Vector2i(((event.position - origin) / unit).floor())
		if cell.x >= 0 and cell.y >= 0 and cell.x < editable_size and cell.y < editable_size:
			cell_toggled.emit(cell)
		return
	pressed.emit()

func _unit() -> float:
	if editable_size > 0:
		return (minf(size.x, size.y) - 8.0) / editable_size
	var extent := _extent()
	return minf(18.0, (minf(size.x, size.y) - 16.0) / (maxi(extent.x, extent.y) + 1))

func _extent() -> Vector2i:
	var extent := Vector2i.ZERO
	for cell in cells:
		extent = Vector2i(maxi(extent.x, cell.x), maxi(extent.y, cell.y))
	return extent

func _grid_origin(unit: float) -> Vector2:
	return (size - Vector2.ONE * unit * editable_size) * 0.5

func _draw() -> void:
	var look := current_skin()
	var border := Color("#f2d35e") if selected else look.slot_border_active_color
	draw_style_box(look.rounded_box(look.slot_color, 12, border, 3 if selected else 1), Rect2(Vector2.ZERO, size))
	var unit := _unit()
	if editable_size > 0:
		var origin := _grid_origin(unit)
		for y in editable_size:
			for x in editable_size:
				var rect := Rect2(origin + Vector2(x, y) * unit, Vector2.ONE * unit).grow(-1.5)
				if cells.has(Vector2i(x, y)):
					look.draw_block(self, rect, color)
				else:
					draw_rect(rect, look.slot_border_empty_color)
		return
	var start := size * 0.5 - Vector2(_extent() + Vector2i.ONE) * unit * 0.5
	for cell in cells:
		look.draw_block(self, Rect2(start + Vector2(cell) * unit, Vector2.ONE * unit).grow(-0.6), color)
