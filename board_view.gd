@tool
class_name SudorisBoard
extends Control

const EMPTY := -1
const BOARD_SIZE := 9

signal dropped(origin: Vector2i)
signal drag_moved(position: Vector2)

var board: Array = []
var pieces: Array = []
var targets: Array[int] = []
var completed_regions: Array[bool] = []
var dragging_piece := -1
var drag_position := Vector2.ZERO
var drag_lift_cells := 1.65
var animated_cells: Array[Vector2i] = []
var placement_scale := 1.0
var placement_tween: Tween
var completion_regions: Array[int] = []
var completion_pulse := 0.0
var completion_tween: Tween

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP

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

func set_drag_lift(lift_cells: float) -> void:
	drag_lift_cells = lift_cells
	queue_redraw()

func set_completed_regions(regions: Array[bool]) -> void:
	completed_regions = regions.duplicate()
	queue_redraw()

func animate_placement(cells: Array[Vector2i]) -> void:
	animated_cells = cells.duplicate()
	placement_scale = 0.35
	if placement_tween:
		placement_tween.kill()
	placement_tween = create_tween()
	placement_tween.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	placement_tween.tween_method(_set_placement_scale, placement_scale, 1.0, 0.2)
	placement_tween.finished.connect(_finish_placement_animation)

func _set_placement_scale(value: float) -> void:
	placement_scale = value
	queue_redraw()

func _finish_placement_animation() -> void:
	animated_cells.clear()
	placement_scale = 1.0
	placement_tween = null
	queue_redraw()

func animate_completed_regions(regions: Array[int]) -> void:
	if regions.is_empty():
		return
	completion_regions = regions.duplicate()
	completion_pulse = 0.0
	if completion_tween:
		completion_tween.kill()
	completion_tween = create_tween()
	completion_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	completion_tween.tween_method(_set_completion_pulse, 0.0, 1.0, 0.22)
	completion_tween.tween_method(_set_completion_pulse, 1.0, 0.0, 0.42)
	completion_tween.finished.connect(_finish_completion_animation)

func _set_completion_pulse(value: float) -> void:
	completion_pulse = value
	queue_redraw()

func _finish_completion_animation() -> void:
	completion_regions.clear()
	completion_pulse = 0.0
	completion_tween = null
	queue_redraw()

func grid_rect() -> Rect2:
	var grid_size := minf(size.x, size.y) - 8.0
	return Rect2(Vector2((size.x - grid_size) * 0.5, (size.y - grid_size) * 0.5), Vector2.ONE * grid_size)

func origin_at(position: Vector2) -> Vector2i:
	var rect := grid_rect()
	var cell_size := rect.size.x / BOARD_SIZE
	var lifted := position - Vector2(0.0, cell_size * drag_lift_cells)
	return Vector2i(floor((lifted.x - rect.position.x) / cell_size), floor((lifted.y - rect.position.y) / cell_size))

func contains_local(position: Vector2) -> bool:
	return grid_rect().has_point(position)

func _draw() -> void:
	var rect := grid_rect()
	var cell_size := rect.size.x / BOARD_SIZE
	draw_style_box(_panel_style(), Rect2(Vector2.ZERO, size))
	draw_rect(rect.grow(3.0), Color("#18200f"))
	for y in BOARD_SIZE:
		for x in BOARD_SIZE:
			var cell_rect := Rect2(rect.position + Vector2(x, y) * cell_size, Vector2.ONE * cell_size)
			var id := EMPTY
			if not board.is_empty():
				id = board[y][x]
			var color := Color("#eee8cf")
			if id != EMPTY and id < pieces.size():
				color = pieces[id].color
			if id != EMPTY and _is_completed_region(y / 3 * 3 + x / 3):
				color = Color("#5eaf4d")
			var fill_rect := cell_rect.grow(-1.5)
			if animated_cells.has(Vector2i(x, y)):
				fill_rect = Rect2(fill_rect.get_center(), Vector2.ZERO).grow_individual(
					fill_rect.size.x * placement_scale * 0.5,
					fill_rect.size.y * placement_scale * 0.5,
					fill_rect.size.x * placement_scale * 0.5,
					fill_rect.size.y * placement_scale * 0.5
				)
			if id != EMPTY and id < pieces.size():
				draw_rect(fill_rect, color.darkened(0.38))
				draw_rect(fill_rect.grow(-2.4), color)
				draw_line(fill_rect.position + Vector2(3, 3), Vector2(fill_rect.end.x - 3, fill_rect.position.y + 3), color.lightened(0.28), 1.2)
			else:
				draw_rect(fill_rect, color)
			draw_rect(cell_rect, Color("#a9a68d"), false, 1.0)
	for line in [3, 6]:
		draw_line(rect.position + Vector2(line * cell_size, 0), rect.position + Vector2(line * cell_size, rect.size.y), Color("#30391f"), 4.0)
		draw_line(rect.position + Vector2(0, line * cell_size), rect.position + Vector2(rect.size.x, line * cell_size), Color("#30391f"), 4.0)
	if not targets.is_empty() and not board.is_empty():
		for region in BOARD_SIZE:
			var rx := region % 3
			var ry := region / 3
			var count := _region_count(region)
			var region_rect := Rect2(rect.position + Vector2(rx, ry) * 3.0 * cell_size, Vector2.ONE * cell_size * 3.0)
			var text_color := Color("#ffffff") if count > 0 else Color("#11180b")
			var label := "%d/%d" % [count, targets[region]]
			draw_string(ThemeDB.fallback_font, region_rect.position + Vector2(0, region_rect.size.y * 0.5 + 8), label, HORIZONTAL_ALIGNMENT_CENTER, region_rect.size.x, 18, text_color)
	for region in completion_regions:
		if region < 0 or region >= BOARD_SIZE:
			continue
		var rx := region % 3
		var ry := region / 3
		var region_rect := Rect2(rect.position + Vector2(rx, ry) * 3.0 * cell_size, Vector2.ONE * cell_size * 3.0)
		var glow := Color(0.55, 1.0, 0.35, 0.16 * completion_pulse)
		draw_rect(region_rect.grow(8.0 * completion_pulse), glow, false, 7.0)
		draw_rect(region_rect.grow(3.0 * completion_pulse), Color(0.72, 1.0, 0.45, 0.9 * completion_pulse), false, 3.0)
	if dragging_piece != -1 and dragging_piece < pieces.size():
		var origin := origin_at(drag_position)
		for cell in pieces[dragging_piece].rotated_cells():
			var preview := Rect2(rect.position + Vector2(origin + cell) * cell_size, Vector2.ONE * cell_size)
			var preview_fill := preview.grow(-3)
			draw_rect(preview_fill, pieces[dragging_piece].color.darkened(0.4))
			draw_rect(preview_fill.grow(-2), pieces[dragging_piece].color.lightened(0.12))

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
