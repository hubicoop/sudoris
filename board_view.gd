@tool
class_name SudorisBoard
extends Control
## Draws the 9x9 board, the dragged piece and the region-clear effects.
## Select the BoardView node to tune everything below in the Inspector.

const EMPTY := -1
const BOARD_SIZE := 9
const NO_ORIGIN := Vector2i(-100, -100)

signal dropped(origin: Vector2i)
signal drag_moved(position: Vector2)

## Colours, sprites and font. Shared with the tray.
@export var skin: SudorisSkin

@export_group("Drag")
## Higher follows the finger more tightly; lower glides more.
@export_range(4.0, 80.0, 1.0) var drag_smoothing := 32.0
## How far (in cells) a piece may hang over the edge and still snap onto the board.
@export_range(0.0, 3.0, 0.1) var snap_tolerance := 1.5
## Seconds a dropped piece takes to slide into its squares.
@export_range(0.0, 1.0, 0.01) var placement_duration := 0.14
## How the dropped piece slides in: x = time, y = share of the distance covered.
## Empty = ease out.
@export var placement_curve: Curve

@export_group("Region Clear")
## Total length of the region-clear effect in seconds.
@export_range(0.1, 3.0, 0.05) var completion_duration := 1.0
## Share of the effect spent spreading green through the region; rings and
## sparkles play in the rest.
@export_range(0.1, 0.9, 0.05) var spread_share := 0.5
## How much each square grows as the green reaches it.
@export_range(0.0, 1.0, 0.01) var pop_amount := 0.2
## Shape of that growth: x = how green the square is, y = growth. Empty = smooth bump.
@export var pop_curve: Curve
@export_range(0, 5) var ring_count := 2
## How far (pixels) the rings travel outward.
@export_range(0.0, 120.0, 1.0) var ring_distance := 34.0
@export_range(0, 64) var sparkle_count := 16
@export_range(0.0, 16.0, 0.5) var sparkle_size := 3.0

@export_group("Line Wave")
## Seconds the wave takes to cross a row or column of three completed regions.
@export_range(0.1, 3.0, 0.05) var wave_duration := 0.85
## How high (in cells) each square jumps.
@export_range(0.0, 1.5, 0.05) var wave_height := 0.3
@export_range(0.0, 0.5, 0.01) var wave_scale := 0.08
## Shape of one square's jump: x = time, y = height. Empty = smooth bump.
@export var wave_curve: Curve

@export_group("Editor Preview")
## Shows a sample board in the editor so the skin and effects can be seen while editing.
@export var editor_preview := true
@export_tool_button("Preview Region Clear", "Play") var preview_clear_button := preview_region_clear
@export_tool_button("Preview Line Wave", "Play") var preview_wave_button := preview_line_wave

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
var placement_from := Vector2.ZERO
var placement_progress := 1.0
var placement_tween: Tween
var completion_regions: Array[int] = []
# Cell -> 0..1 delay before it turns green, measured from the cells of the piece that
# completed the region.
var completion_delays := {}
var completion_progress := 0.0
var completion_tween: Tween
# Cell -> 0..1 position along a row or column of three completed regions doing a wave.
var wave_positions := {}
var wave_progress := 0.0
var wave_tween: Tween
var _default_skin := SudorisSkin.new()

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP

func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		# Redraw continuously so skin and effect edits show up immediately.
		if editor_preview and board.is_empty():
			_build_preview()
		queue_redraw()
		return
	if dragging_piece == -1 or visual_drag_position == drag_position:
		return
	visual_drag_position = visual_drag_position.lerp(drag_position, 1.0 - exp(-delta * drag_smoothing))
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

func current_skin() -> SudorisSkin:
	return skin if skin else _default_skin

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

static func _sample(curve: Curve, t: float, fallback: float) -> float:
	return curve.sample_baked(t) if curve else fallback

func animate_placement(cells: Array[Vector2i], from_offset: Vector2) -> void:
	animated_cells = cells.duplicate()
	placement_from = from_offset
	placement_progress = 0.0
	if placement_tween:
		placement_tween.kill()
	placement_tween = create_tween()
	placement_tween.tween_method(_set_placement_progress, 0.0, 1.0, maxf(placement_duration, 0.001))
	placement_tween.finished.connect(_finish_placement_animation)

func _set_placement_progress(value: float) -> void:
	placement_progress = value
	queue_redraw()

func _placement_offset() -> Vector2:
	var moved := _sample(placement_curve, placement_progress, 1.0 - pow(1.0 - placement_progress, 3.0))
	return placement_from * (1.0 - moved)

func _finish_placement_animation() -> void:
	animated_cells.clear()
	placement_progress = 1.0
	placement_tween = null
	queue_redraw()

func animate_completed_regions(regions: Array[int], source_cells: Array[Vector2i]) -> void:
	if regions.is_empty():
		return
	completion_regions = regions.duplicate()
	completion_delays.clear()
	for region in regions:
		_compute_spread_delays(region, source_cells)
	completion_progress = 0.0
	if completion_tween:
		completion_tween.kill()
	completion_tween = create_tween()
	completion_tween.tween_method(_set_completion_progress, 0.0, 1.0, completion_duration)
	completion_tween.finished.connect(_finish_completion_animation)

func _compute_spread_delays(region: int, source_cells: Array[Vector2i]) -> void:
	var start := Vector2i((region % 3) * 3, (region / 3) * 3)
	var sources: Array[Vector2i] = []
	for cell in source_cells:
		if cell.x >= start.x and cell.x < start.x + 3 and cell.y >= start.y and cell.y < start.y + 3:
			sources.append(cell)
	if sources.is_empty():
		sources.append(start + Vector2i.ONE)
	var distances := {}
	var farthest := 0.0
	for y in range(start.y, start.y + 3):
		for x in range(start.x, start.x + 3):
			var cell := Vector2i(x, y)
			var nearest := INF
			for source in sources:
				nearest = minf(nearest, Vector2(cell - source).length())
			distances[cell] = nearest
			farthest = maxf(farthest, nearest)
	for cell in distances:
		completion_delays[cell] = distances[cell] / farthest if farthest > 0.0 else 0.0

# How far a cell has turned green: 0 = original colour, 1 = fully green.
func _green_amount(cell: Vector2i) -> float:
	if not completion_delays.has(cell):
		return 1.0
	var spread := completion_progress / spread_share
	return clampf((spread - completion_delays[cell] * 0.7) / 0.3, 0.0, 1.0)

func animate_wave(lines: Array) -> void:
	if lines.is_empty():
		return
	wave_positions.clear()
	for line in lines:
		var horizontal: bool = line[1] - line[0] == 1
		for region in line:
			var start := Vector2i((region % 3) * 3, (region / 3) * 3)
			for y in range(start.y, start.y + 3):
				for x in range(start.x, start.x + 3):
					wave_positions[Vector2i(x, y)] = (x if horizontal else y) / float(BOARD_SIZE - 1)
	wave_progress = 0.0
	if wave_tween:
		wave_tween.kill()
	wave_tween = create_tween()
	# Start once the green has finished spreading.
	wave_tween.tween_interval(completion_duration * spread_share)
	wave_tween.tween_method(_set_wave_progress, 0.0, 1.0, wave_duration)
	wave_tween.finished.connect(_finish_wave)

func _set_wave_progress(value: float) -> void:
	wave_progress = value
	queue_redraw()

func _finish_wave() -> void:
	wave_positions.clear()
	wave_progress = 0.0
	wave_tween = null
	queue_redraw()

# 0..1 height of a cell in the wave; each cell rises and falls a little after the one before.
func _wave_height(cell: Vector2i) -> float:
	if not wave_positions.has(cell):
		return 0.0
	var local := clampf((wave_progress - wave_positions[cell] * 0.6) / 0.4, 0.0, 1.0)
	if local <= 0.0 or local >= 1.0:
		return 0.0
	return _sample(wave_curve, local, sin(PI * local))

func _set_completion_progress(value: float) -> void:
	completion_progress = value
	queue_redraw()

func _finish_completion_animation() -> void:
	completion_regions.clear()
	completion_delays.clear()
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
	if absf(float_origin.x - snapped.x) > snap_tolerance or absf(float_origin.y - snapped.y) > snap_tolerance:
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

func _draw() -> void:
	var look := current_skin()
	var rect := grid_rect()
	var cs := rect.size.x / BOARD_SIZE
	draw_style_box(_panel_style(look), Rect2(Vector2.ZERO, size))
	draw_rect(rect.grow(3.0), look.grid_background_color)
	# Grid first, then pieces on top, so cells lifted by the wave are not crossed by grid lines.
	for y in BOARD_SIZE:
		for x in BOARD_SIZE:
			var cell_rect := Rect2(rect.position + Vector2(x, y) * cs, Vector2.ONE * cs)
			if board.is_empty() or board[y][x] == EMPTY:
				look.draw_empty_cell(self, cell_rect.grow(-1.5))
			draw_rect(cell_rect, look.grid_line_color, false, 1.0)
	for line in [3, 6]:
		draw_line(rect.position + Vector2(line * cs, 0), rect.position + Vector2(line * cs, rect.size.y), look.region_line_color, look.region_line_width)
		draw_line(rect.position + Vector2(0, line * cs), rect.position + Vector2(rect.size.x, line * cs), look.region_line_color, look.region_line_width)
	var placement_offset := _placement_offset()
	for y in BOARD_SIZE:
		for x in BOARD_SIZE:
			var cell_rect := Rect2(rect.position + Vector2(x, y) * cs, Vector2.ONE * cs)
			var id := EMPTY
			if not board.is_empty():
				id = board[y][x]
			if id == EMPTY or id >= pieces.size():
				continue
			var region := y / 3 * 3 + x / 3
			var color: Color = pieces[id].color
			var cell := Vector2i(x, y)
			var cell_scale := 1.0
			if _is_completed_region(region):
				var green := _green_amount(cell)
				color = color.lerp(look.completed_color, green)
				# Each cell pops briefly as the green reaches it.
				if completion_delays.has(cell):
					cell_scale += pop_amount * _sample(pop_curve, green, sin(PI * green))
			var fill_rect := cell_rect.grow(-1.5)
			var wave := _wave_height(cell)
			if wave != 0.0:
				fill_rect.position.y -= wave * cs * wave_height
				cell_scale += wave_scale * wave
			if animated_cells.has(cell):
				fill_rect.position += placement_offset
			if cell_scale != 1.0:
				var half := fill_rect.size * cell_scale * 0.5
				fill_rect = Rect2(fill_rect.get_center() - half, half * 2.0)
			look.draw_block(self, fill_rect, color)
	_draw_drop_ghost(look, rect, cs)
	if not targets.is_empty() and not board.is_empty():
		for region in BOARD_SIZE:
			_draw_region_label(look, _region_rect(rect, cs, region), region)
	for region in completion_regions:
		if region >= 0 and region < BOARD_SIZE:
			_draw_completion_effect(look, _region_rect(rect, cs, region), region)

func _region_rect(rect: Rect2, cs: float, region: int) -> Rect2:
	return Rect2(rect.position + Vector2(region % 3, region / 3) * 3.0 * cs, Vector2.ONE * cs * 3.0)

# Faint outline of where the piece will land (red when blocked); kept subtle so the
# snapping does not distract from the gliding piece.
func _draw_drop_ghost(look: SudorisSkin, rect: Rect2, cs: float) -> void:
	var cells := _dragged_cells()
	if cells.is_empty() or board.is_empty():
		return
	var origin := origin_at(drag_position)
	if origin == NO_ORIGIN:
		return
	var fits := _fits(cells, origin)
	var tint: Color = pieces[dragging_piece].color if fits else look.blocked_color
	for cell in cells:
		var ghost := Rect2(rect.position + Vector2(origin + cell) * cs, Vector2.ONE * cs).grow(-3.0)
		draw_rect(ghost, Color(tint, 0.14))
		draw_rect(ghost, Color(tint.darkened(0.3), 0.5), false, 1.5)

# Region count in a light pill so the text stays readable on any piece colour.
func _draw_region_label(look: SudorisSkin, region_rect: Rect2, region: int) -> void:
	var font := look.font()
	var font_size := look.label_font_size
	var label := "%d/%d" % [_region_count(region), targets[region]]
	var text_size := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	var pill_size := text_size + Vector2(14, 4)
	var pill := Rect2(region_rect.get_center() - pill_size * 0.5, pill_size)
	draw_style_box(look.rounded_box(look.label_background_color, 9), pill)
	var baseline := Vector2(pill.position.x + 7, pill.get_center().y + font.get_ascent(font_size) * 0.5 - font.get_descent(font_size) * 0.5 + 1)
	draw_string(font, baseline, label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, look.label_text_color)

func _draw_completion_effect(look: SudorisSkin, region_rect: Rect2, region: int) -> void:
	if completion_progress < spread_share:
		return
	var t := (completion_progress - spread_share) / (1.0 - spread_share)
	var fade := 1.0 - t
	var center := region_rect.get_center()
	# Rings expanding outward.
	for ring in ring_count:
		var ring_t := clampf(t * 1.4 - ring * 0.18, 0.0, 1.0)
		if ring_t <= 0.0 or ring_t >= 1.0:
			continue
		var grow := 4.0 + ease(ring_t, 0.4) * ring_distance
		draw_rect(region_rect.grow(grow), Color(look.ring_color, 0.85 * (1.0 - ring_t)), false, maxf(4.0 - ring * 1.5, 1.0))
	# Sparkles bursting out of the region centre.
	if look.sparkle_colors.is_empty():
		return
	var burst := ease(clampf(t * 1.2, 0.0, 1.0), 0.35)
	for index in sparkle_count:
		var angle := TAU * index / float(sparkle_count) + region * 0.7
		var reach := region_rect.size.x * (0.55 + 0.35 * float((index * 7 + region) % 5) / 4.0)
		var point := center + Vector2.from_angle(angle) * reach * burst
		var radius := (sparkle_size + float(index % 3) * 1.6) * fade
		if radius <= 0.2:
			continue
		var color: Color = look.sparkle_colors[index % look.sparkle_colors.size()]
		_draw_sparkle(look, point, radius, Color(color, fade))

func _draw_sparkle(look: SudorisSkin, point: Vector2, radius: float, color: Color) -> void:
	if look.sparkle_texture:
		var half := Vector2.ONE * radius * 2.2
		draw_texture_rect(look.sparkle_texture, Rect2(point - half, half * 2.0), false, color)
		return
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
	var look := current_skin()
	var cs := cell_size()
	var to_layer := layer.get_global_transform_with_canvas().affine_inverse() * get_global_transform_with_canvas()
	layer.draw_set_transform_matrix(to_layer)
	var top_left := floating_top_left(visual_drag_position)
	var color: Color = pieces[dragging_piece].color
	for cell in cells:
		var cell_rect := Rect2(top_left + Vector2(cell) * cs, Vector2.ONE * cs).grow(-1.5)
		layer.draw_rect(Rect2(cell_rect.position + Vector2(3, 6), cell_rect.size), Color(0.03, 0.05, 0.01, 0.3))
	for cell in cells:
		look.draw_block(layer, Rect2(top_left + Vector2(cell) * cs, Vector2.ONE * cs).grow(-1.5), color.lightened(0.08))
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

func _panel_style(look: SudorisSkin) -> StyleBoxFlat:
	var style := look.rounded_box(look.board_panel_color, 12, look.board_border_color, 3)
	style.shadow_color = Color(0.05, 0.08, 0.02, 0.45)
	style.shadow_size = 8
	style.shadow_offset = Vector2(0, 5)
	return style

# --- Editor preview -------------------------------------------------------------

class PreviewPiece:
	var color: Color
	func _init(new_color: Color) -> void:
		color = new_color
	func rotated_cells() -> Array[Vector2i]:
		return [Vector2i.ZERO]

# A hand-made sample position: the top three regions are complete so the green and
# the wave can be previewed, the rest is partly filled.
const PREVIEW_ROWS := [
	"AABBBCCDD",
	"AEEBFFCDD",
	"GEEHFFCII",
	"G........",
	"....JJ...",
	"....J....",
	".........",
	"......KKK",
	".........",
]
const PREVIEW_COLORS := [Color("#ef5d50"), Color("#f59f45"), Color("#f2d35e"), Color("#4ec982"), Color("#30b8b0"), Color("#49a5e6"), Color("#8b78e6"), Color("#e46aa8")]

func _build_preview() -> void:
	var ids := {}
	board = []
	pieces = []
	for y in BOARD_SIZE:
		var row: Array[int] = []
		for x in BOARD_SIZE:
			var letter: String = PREVIEW_ROWS[y][x]
			if letter == ".":
				row.append(EMPTY)
				continue
			if not ids.has(letter):
				ids[letter] = pieces.size()
				pieces.append(PreviewPiece.new(PREVIEW_COLORS[pieces.size() % PREVIEW_COLORS.size()]))
			row.append(ids[letter])
		board.append(row)
	targets = [4, 4, 4, 3, 5, 4, 3, 4, 5]
	for region in 3:
		targets[region] = _region_count(region)
	completed_regions = [true, true, true, false, false, false, false, false, false]

func preview_region_clear() -> void:
	_build_preview()
	# Spread from the piece in the top-right corner, as if it had just been placed.
	animate_completed_regions([0, 1, 2] as Array[int], [Vector2i(7, 2), Vector2i(8, 2)] as Array[Vector2i])

func preview_line_wave() -> void:
	_build_preview()
	animate_completed_regions([0, 1, 2] as Array[int], [Vector2i(7, 2), Vector2i(8, 2)] as Array[Vector2i])
	animate_wave([[0, 1, 2]])
