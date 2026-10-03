@tool
class_name SudorisBoard
extends Control

const EMPTY := -1
const BOARD_SIZE := 9
const NO_ORIGIN := Vector2i(-100, -100)
# How far (in cells) a piece may hang over the edge and still snap onto the board.
const SNAP_TOLERANCE := 1.5
const COMPLETION_DURATION := 0.95
# Higher follows the finger more tightly; lower glides more.
const DRAG_SMOOTHING := 32.0
const LABEL_FONT := preload("res://fonts/Roboto-Bold.ttf")

signal dropped(origin: Vector2i)
signal drag_moved(position: Vector2)

var board: Array = []
var pieces: Array = []
var targets: Array[int] = []
var completed_regions: Array[bool] = []
var dragging_piece := -1
var drag_position := Vector2.ZERO
# Where the floating piece is drawn; eases toward drag_position every frame so the
# piece glides even when touch events arrive unevenly.
var visual_drag_position := Vector2.ZERO
var floating_layer: CanvasItem
var drag_lift_cells := 1.65
var animated_cells: Array[Vector2i] = []
var placement_offset := Vector2.ZERO
var placement_tween: Tween
var completion_regions: Array[int] = []
var completion_progress := 0.0
var completion_tween: Tween

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP

func _process(delta: float) -> void:
	if dragging_piece == -1 or visual_drag_position == drag_position:
		return
	visual_drag_position = visual_drag_position.lerp(drag_position, 1.0 - exp(-delta * DRAG_SMOOTHING))
	if visual_drag_position.distance_squared_to(drag_position) < 0.01:
		visual_drag_position = drag_position
	if floating_layer:
		floating_layer.queue_redraw()

func _gui_input(event: InputEvent) -> void:
	if Engine.is_editor_hint():
		return
	if event is InputEventMouseMotion or event is InputEventScreenDrag:
		drag_moved.emit(event.position)
	elif event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
			dropped.emit(origin_at(event.position))
	elif event is InputEventScreenTouch:
		if not event.pressed:
			dropped.emit(origin_at(event.position))

func configure(new_board: Array, new_pieces: Array, new_targets: Array[int], new_dragging_piece: int, new_drag_position: Vector2) -> void:
	board = new_board
	pieces = new_pieces
	targets = new_targets
	dragging_piece = new_dragging_piece
	drag_position = new_drag_position
	queue_redraw()

func update_drag(new_drag_position: Vector2) -> void:
	drag_position = new_drag_position
	queue_redraw()

func begin_drag(start_position: Vector2) -> void:
	drag_position = start_position
	visual_drag_position = start_position

# Pixel offset from the landing cells to where the floating piece is currently drawn,
# so the placement animation can slide the piece into place from there.
func settle_offset(origin: Vector2i) -> Vector2:
	var rect := grid_rect()
	return floating_top_left(visual_drag_position) - (rect.position + Vector2(origin) * cell_size())

func set_drag_lift(lift_cells: float) -> void:
	drag_lift_cells = lift_cells
	queue_redraw()

func set_completed_regions(regions: Array[bool]) -> void:
	completed_regions = regions.duplicate()
	queue_redraw()

func animate_placement(cells: Array[Vector2i], from_offset: Vector2) -> void:
	animated_cells = cells.duplicate()
	placement_offset = from_offset
	if placement_tween:
		placement_tween.kill()
	placement_tween = create_tween()
	placement_tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	placement_tween.tween_method(_set_placement_offset, from_offset, Vector2.ZERO, 0.14)
	placement_tween.finished.connect(_finish_placement_animation)

func _set_placement_offset(value: Vector2) -> void:
	placement_offset = value
	queue_redraw()

func _finish_placement_animation() -> void:
	animated_cells.clear()
	placement_offset = Vector2.ZERO
	placement_tween = null
	queue_redraw()

func animate_completed_regions(regions: Array[int]) -> void:
	if regions.is_empty():
		return
	completion_regions = regions.duplicate()
	completion_progress = 0.0
	if completion_tween:
		completion_tween.kill()
	completion_tween = create_tween()
	completion_tween.tween_method(_set_completion_progress, 0.0, 1.0, COMPLETION_DURATION)
	completion_tween.finished.connect(_finish_completion_animation)

func _set_completion_progress(value: float) -> void:
	completion_progress = value
	queue_redraw()

func _finish_completion_animation() -> void:
	completion_regions.clear()
	completion_progress = 0.0
	completion_tween = null
	queue_redraw()

func grid_rect() -> Rect2:
	var grid_size := minf(size.x, size.y) - 8.0
	return Rect2(Vector2((size.x - grid_size) * 0.5, (size.y - grid_size) * 0.5), Vector2.ONE * grid_size)

func cell_size() -> float:
	return grid_rect().size.x / BOARD_SIZE

func _dragged_cells() -> Array[Vector2i]:
	if dragging_piece == -1 or dragging_piece >= pieces.size():
		return []
	return pieces[dragging_piece].rotated_cells()

func _cells_extent(cells: Array[Vector2i]) -> Vector2i:
	var extent := Vector2i.ZERO
	for cell in cells:
		extent.x = maxi(extent.x, cell.x + 1)
		extent.y = maxi(extent.y, cell.y + 1)
	return extent

# Top-left corner of the lifted piece that follows the finger, in board-local pixels.
func floating_top_left(position: Vector2) -> Vector2:
	var cs := cell_size()
	var extent := _cells_extent(_dragged_cells())
	return position - Vector2(extent.x * cs * 0.5, cs * (drag_lift_cells + 0.5))

# Board cell the dragged piece snaps to. Pieces hanging slightly over an edge are
# pulled back onto the board; pieces far outside return NO_ORIGIN.
func origin_at(position: Vector2) -> Vector2i:
	var cells := _dragged_cells()
	if cells.is_empty():
		return NO_ORIGIN
	var rect := grid_rect()
	var cs := rect.size.x / BOARD_SIZE
	var extent := _cells_extent(cells)
	var float_origin := (floating_top_left(position) - rect.position) / cs
	var snapped := Vector2(
		clampf(roundf(float_origin.x), 0.0, BOARD_SIZE - extent.x),
		clampf(roundf(float_origin.y), 0.0, BOARD_SIZE - extent.y)
	)
	if absf(float_origin.x - snapped.x) > SNAP_TOLERANCE or absf(float_origin.y - snapped.y) > SNAP_TOLERANCE:
		return NO_ORIGIN
	return Vector2i(snapped)

func contains_local(position: Vector2) -> bool:
	return grid_rect().has_point(position)

func _fits(cells: Array[Vector2i], origin: Vector2i) -> bool:
	for cell in cells:
		var target := origin + cell
		if target.x < 0 or target.x >= BOARD_SIZE or target.y < 0 or target.y >= BOARD_SIZE or board[target.y][target.x] != EMPTY:
			return false
	return true

func _completion_pop(region: int) -> float:
	if not completion_regions.has(region):
		return 1.0
	var t := clampf(completion_progress * 2.2, 0.0, 1.0)
	return 1.0 + 0.22 * sin(PI * t)

func _draw() -> void:
	var rect := grid_rect()
	var cs := rect.size.x / BOARD_SIZE
	draw_style_box(_panel_style(), Rect2(Vector2.ZERO, size))
	draw_rect(rect.grow(3.0), Color("#18200f"))
	for y in BOARD_SIZE:
		for x in BOARD_SIZE:
			var cell_rect := Rect2(rect.position + Vector2(x, y) * cs, Vector2.ONE * cs)
			var id := EMPTY
			if not board.is_empty():
				id = board[y][x]
			var region := y / 3 * 3 + x / 3
			var color := Color("#eee8cf")
			if id != EMPTY and id < pieces.size():
				color = pieces[id].color
			if id != EMPTY and _is_completed_region(region):
				color = Color("#5eaf4d")
			var fill_rect := cell_rect.grow(-1.5)
			var cell_scale := _completion_pop(region)
			if animated_cells.has(Vector2i(x, y)):
				fill_rect.position += placement_offset
			if cell_scale != 1.0:
				var half := fill_rect.size * cell_scale * 0.5
				fill_rect = Rect2(fill_rect.get_center() - half, half * 2.0)
			if id != EMPTY and id < pieces.size():
				draw_rect(fill_rect, color.darkened(0.38))
				draw_rect(fill_rect.grow(-2.4), color)
				draw_line(fill_rect.position + Vector2(3, 3), Vector2(fill_rect.end.x - 3, fill_rect.position.y + 3), color.lightened(0.28), 1.2)
			else:
				draw_rect(fill_rect, color)
			draw_rect(cell_rect, Color("#a9a68d"), false, 1.0)
	for line in [3, 6]:
		draw_line(rect.position + Vector2(line * cs, 0), rect.position + Vector2(line * cs, rect.size.y), Color("#30391f"), 4.0)
		draw_line(rect.position + Vector2(0, line * cs), rect.position + Vector2(rect.size.x, line * cs), Color("#30391f"), 4.0)
	_draw_drop_ghost(rect, cs)
	if not targets.is_empty() and not board.is_empty():
		for region in BOARD_SIZE:
			_draw_region_label(_region_rect(rect, cs, region), region)
	for region in completion_regions:
		if region >= 0 and region < BOARD_SIZE:
			_draw_completion_effect(_region_rect(rect, cs, region), region)

func _region_rect(rect: Rect2, cs: float, region: int) -> Rect2:
	return Rect2(rect.position + Vector2(region % 3, region / 3) * 3.0 * cs, Vector2.ONE * cs * 3.0)

# Faint outline of where the piece will land (red when blocked); kept subtle so the
# snapping does not distract from the gliding piece.
func _draw_drop_ghost(rect: Rect2, cs: float) -> void:
	var cells := _dragged_cells()
	if cells.is_empty() or board.is_empty():
		return
	var origin := origin_at(drag_position)
	if origin == NO_ORIGIN:
		return
	var fits := _fits(cells, origin)
	var tint: Color = pieces[dragging_piece].color if fits else Color("#d8433a")
	for cell in cells:
		var ghost := Rect2(rect.position + Vector2(origin + cell) * cs, Vector2.ONE * cs).grow(-3.0)
		draw_rect(ghost, Color(tint, 0.14))
		draw_rect(ghost, Color(tint.darkened(0.3), 0.5), false, 1.5)

# Region count in a light pill so the black text stays readable on any piece colour.
func _draw_region_label(region_rect: Rect2, region: int) -> void:
	var label := "%d/%d" % [_region_count(region), targets[region]]
	var font_size := 17
	var text_size := LABEL_FONT.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	var pill_size := text_size + Vector2(14, 4)
	var pill := Rect2(region_rect.get_center() - pill_size * 0.5, pill_size)
	draw_style_box(_label_style(), pill)
	var baseline := Vector2(pill.position.x + 7, pill.get_center().y + LABEL_FONT.get_ascent(font_size) * 0.5 - LABEL_FONT.get_descent(font_size) * 0.5 + 1)
	draw_string(LABEL_FONT, baseline, label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color("#11180b"))

func _draw_completion_effect(region_rect: Rect2, region: int) -> void:
	var t := completion_progress
	var fade := 1.0 - t
	var center := region_rect.get_center()
	# Bright flash that settles from white into green.
	var flash := Color(1.0, 1.0, 0.85).lerp(Color(0.6, 1.0, 0.4), clampf(t * 3.0, 0.0, 1.0))
	draw_rect(region_rect, Color(flash, 0.75 * pow(fade, 2.0)))
	# Two shock rings expanding outward.
	for ring in 2:
		var ring_t := clampf(t * 1.4 - ring * 0.18, 0.0, 1.0)
		if ring_t <= 0.0 or ring_t >= 1.0:
			continue
		var grow := 4.0 + ease(ring_t, 0.4) * 34.0
		draw_rect(region_rect.grow(grow), Color(0.78, 1.0, 0.45, 0.85 * (1.0 - ring_t)), false, 4.0 - ring * 1.5)
	# Sparkles bursting out of the region centre.
	var sparkle_colors := [Color("#fff6a8"), Color("#ffffff"), Color("#b6f56a"), Color("#ffd24a")]
	var burst := ease(clampf(t * 1.2, 0.0, 1.0), 0.35)
	for index in 16:
		var angle := TAU * index / 16.0 + region * 0.7
		var reach := region_rect.size.x * (0.55 + 0.35 * float((index * 7 + region) % 5) / 4.0)
		var point := center + Vector2.from_angle(angle) * reach * burst
		var radius := (3.0 + float(index % 3) * 1.6) * fade
		if radius <= 0.2:
			continue
		var color: Color = sparkle_colors[index % sparkle_colors.size()]
		_draw_sparkle(point, radius, Color(color, fade))
	# "CLEAR!" pops up and floats away.
	var text_t := clampf(t * 1.6, 0.0, 1.0)
	var text_alpha := clampf((1.0 - t) * 2.0, 0.0, 1.0)
	var text_size := int(16 + 10 * sin(PI * minf(text_t * 1.4, 1.0)) + 6 * text_t)
	var text := "CLEAR!"
	var measured := LABEL_FONT.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, text_size)
	var text_pos := center + Vector2(-measured.x * 0.5, -region_rect.size.y * (0.18 + 0.3 * t))
	draw_string(LABEL_FONT, text_pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, text_size, Color(0.09, 0.19, 0.05, text_alpha))

func _draw_sparkle(point: Vector2, radius: float, color: Color) -> void:
	var points := PackedVector2Array()
	for corner in 8:
		var distance := radius * (2.2 if corner % 2 == 0 else 0.7)
		points.append(point + Vector2.from_angle(corner * TAU / 8.0) * distance)
	draw_colored_polygon(points, color)

# Draws the piece that follows the finger on a layer above the tray, so it is never
# hidden behind other controls while dragging.
func draw_floating(layer: CanvasItem) -> void:
	var cells := _dragged_cells()
	if cells.is_empty():
		return
	var cs := cell_size()
	var to_layer := layer.get_global_transform_with_canvas().affine_inverse() * get_global_transform_with_canvas()
	layer.draw_set_transform_matrix(to_layer)
	var top_left := floating_top_left(visual_drag_position)
	var color: Color = pieces[dragging_piece].color
	for cell in cells:
		var cell_rect := Rect2(top_left + Vector2(cell) * cs, Vector2.ONE * cs).grow(-1.5)
		layer.draw_rect(Rect2(cell_rect.position + Vector2(3, 6), cell_rect.size), Color(0.03, 0.05, 0.01, 0.3))
	for cell in cells:
		var cell_rect := Rect2(top_left + Vector2(cell) * cs, Vector2.ONE * cs).grow(-1.5)
		layer.draw_rect(cell_rect, color.darkened(0.4))
		layer.draw_rect(cell_rect.grow(-2.4), color.lightened(0.08))
		layer.draw_line(cell_rect.position + Vector2(3, 3), Vector2(cell_rect.end.x - 3, cell_rect.position.y + 3), color.lightened(0.35), 1.2)
	layer.draw_set_transform_matrix(Transform2D.IDENTITY)

func _region_count(region: int) -> int:
	var touched := {}
	var region_x := (region % 3) * 3
	var region_y := (region / 3) * 3
	for y in range(region_y, region_y + 3):
		for x in range(region_x, region_x + 3):
			if board[y][x] != EMPTY:
				touched[board[y][x]] = true
	return touched.size()

func _is_completed_region(region: int) -> bool:
	return region >= 0 and region < completed_regions.size() and completed_regions[region]

func _label_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(1.0, 0.99, 0.95, 0.9)
	style.set_corner_radius_all(9)
	return style

func _panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color("#d9d3b8")
	style.border_color = Color("#202910")
	style.set_border_width_all(3)
	style.corner_radius_top_left = 12
	style.corner_radius_top_right = 12
	style.corner_radius_bottom_left = 12
	style.corner_radius_bottom_right = 12
	style.shadow_color = Color(0.05, 0.08, 0.02, 0.45)
	style.shadow_size = 8
	style.shadow_offset = Vector2(0, 5)
	return style
