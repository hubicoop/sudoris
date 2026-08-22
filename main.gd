extends Control

const BOARD_SIZE := 9
const REGION_SIZE := 3
const EMPTY := -1
const SAVE_PATH := "user://progress.cfg"
const PALETTE := [Color("#ef5d50"), Color("#f59f45"), Color("#f2d35e"), Color("#4ec982"), Color("#30b8b0"), Color("#49a5e6"), Color("#8b78e6"), Color("#e46aa8")]

class PuzzlePiece:
	var cells: Array[Vector2i]
	var solution_cells: Array[Vector2i]
	var color: Color
	var rotation := 0

	func _init(new_cells: Array[Vector2i], new_solution_cells: Array[Vector2i], new_color: Color) -> void:
		cells = new_cells
		solution_cells = new_solution_cells
		color = new_color

	func rotated_cells() -> Array[Vector2i]:
		var result: Array[Vector2i] = []
		for cell in cells:
			var turned := cell
			for turn in rotation:
				turned = Vector2i(-turned.y, turned.x)
			result.append(turned)
		var min_x := result[0].x
		var min_y := result[0].y
		for cell in result:
			min_x = min(min_x, cell.x)
			min_y = min(min_y, cell.y)
		for index in result.size():
			result[index] -= Vector2i(min_x, min_y)
		return result

class Placement:
	var local_cells: Array[Vector2i]
	var board_cells: Array[Vector2i]

	func _init(new_local_cells: Array[Vector2i], new_board_cells: Array[Vector2i]) -> void:
		local_cells = new_local_cells
		board_cells = new_board_cells

@onready var board_view: SudorisBoard = %BoardView
@onready var tray_view: SudorisTray = %TrayView
@onready var status_label: Label = %StatusLabel
@onready var pause_modal: Control = %PauseModal
@onready var game_over_modal: Control = %GameOverModal
@onready var game_over_reason: Label = %GameOverReason
@onready var how_to_modal: Control = %HowToModal
@onready var win_modal: Control = %WinModal
@onready var level_label: Label = %LevelLabel
@onready var score_label: Label = %ScoreLabel
@onready var combo_label: Label = %ComboLabel

var rng := RandomNumberGenerator.new()
var pieces: Array[PuzzlePiece] = []
var board: Array = []
var targets: Array[int] = []
var active_slots: Array[int] = [-1, -1, -1]
var draw_order: Array[int] = []
var next_piece := 0
var dragging_piece := -1
var drag_position := Vector2.ZERO
var message := "Fill every square. Match the region counts."
var last_rotation_ms := -1000
var level := 1
var score := 0
var combo := 0
var combo_deadline_ms := 0

func _ready() -> void:
	rng.randomize()
	load_progress()
	%ResetButton.pressed.connect(reset_puzzle)
	%PauseButton.pressed.connect(show_pause_menu)
	%ResumeButton.pressed.connect(hide_pause_menu)
	%NewPuzzleButton.pressed.connect(new_puzzle)
	%RestartButton.pressed.connect(reset_puzzle)
	%HowToPlayButton.pressed.connect(hide_how_to)
	%HowToPlayButton.gui_input.connect(_on_how_to_button_input)
	%NextLevelButton.pressed.connect(next_level)
	tray_view.piece_picked.connect(start_drag)
	tray_view.rotate_requested.connect(rotate_piece)
	board_view.dropped.connect(drop_piece)
	board_view.drag_moved.connect(move_drag)
	new_puzzle()
	how_to_modal.visible = true
	how_to_modal.move_to_front()

func _process(_delta: float) -> void:
	if combo > 0 and Time.get_ticks_msec() > combo_deadline_ms:
		combo = 0
		refresh_views()

func _on_how_to_button_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch and not event.pressed:
		hide_how_to()
		get_viewport().set_input_as_handled()

func new_puzzle() -> void:
	draw_order.clear()
	var valid_puzzle := false
	for attempt in 160:
		prepare_empty_board()
		build_solution_from_catalog()
		calculate_targets()
		if targets_match_difficulty():
			valid_puzzle = true
			break
	if not valid_puzzle:
		push_warning("Could not generate every requested target after 160 attempts; using the closest valid puzzle.")
	for y in BOARD_SIZE:
		for x in BOARD_SIZE:
			board[y][x] = EMPTY
	draw_order.resize(pieces.size())
	for index in pieces.size():
		draw_order[index] = index
	draw_order.shuffle()
	next_piece = 0
	score = 0
	combo = 0
	combo_deadline_ms = 0
	for slot in active_slots.size():
		active_slots[slot] = take_next_piece()
	dragging_piece = -1
	message = "Fill the board and make every region count match."
	hide_pause_menu()
	hide_game_over()
	hide_win()
	refresh_views()

func prepare_empty_board() -> void:
	pieces.clear()
	board.clear()
	for y in BOARD_SIZE:
		var row: Array[int] = []
		for x in BOARD_SIZE:
			row.append(EMPTY)
		board.append(row)

func calculate_targets() -> void:
	targets.resize(BOARD_SIZE)
	targets.fill(0)
	for piece in pieces:
		var regions: Array[int] = []
		for cell in piece.solution_cells:
			var region_index := int(cell.y / REGION_SIZE) * 3 + int(cell.x / REGION_SIZE)
			if not regions.has(region_index):
				regions.append(region_index)
		for region_index in regions:
			targets[region_index] += 1

func maximum_region_target() -> int:
	if level <= 2:
		return 5
	if level <= 4:
		return 6
	return 7

func targets_match_difficulty() -> bool:
	var maximum := maximum_region_target()
	for target in targets:
		if target < 3 or target > maximum:
			return false
	# New values are introduced deliberately instead of only becoming possible.
	return maximum == 5 or targets.has(maximum)

func monomino_chance() -> float:
	var maximum := maximum_region_target()
	if maximum == 5:
		return 0.0
	if maximum == 6:
		return 0.01
	return 0.04

func build_solution_from_catalog() -> void:
	var filled_cells := 0
	while filled_cells < BOARD_SIZE * BOARD_SIZE:
		var anchor := first_empty_cell()
		var candidates := placement_candidates(anchor, false)
		# Monominoes remain uncommon, but guarantee that every generated board can finish.
		if candidates.is_empty() or rng.randf() < monomino_chance():
			candidates.append_array(placement_candidates(anchor, true))
		var placement: Placement = candidates[rng.randi_range(0, candidates.size() - 1)]
		var piece_id := pieces.size()
		var palette_cycle: int = int(piece_id / PALETTE.size())
		var piece_color: Color = PALETTE[piece_id % PALETTE.size()].lightened(palette_cycle * 0.08)
		pieces.append(PuzzlePiece.new(placement.local_cells, placement.board_cells, piece_color))
		for cell in placement.board_cells:
			board[cell.y][cell.x] = piece_id
			filled_cells += 1

func first_empty_cell() -> Vector2i:
	for y in BOARD_SIZE:
		for x in BOARD_SIZE:
			if board[y][x] == EMPTY:
				return Vector2i(x, y)
	return Vector2i(-1, -1)

func placement_candidates(anchor: Vector2i, monomino_only: bool) -> Array[Placement]:
	var candidates: Array[Placement] = []
	var catalog := shape_catalog()
	for base_shape in catalog:
		var typed_shape: Array[Vector2i] = []
		for cell in base_shape:
			typed_shape.append(cell)
		if monomino_only != (typed_shape.size() == 1):
			continue
		for orientation in unique_orientations(typed_shape):
			var oriented_shape: Array[Vector2i] = orientation
			for anchor_cell in oriented_shape:
				var origin := anchor - anchor_cell
				var board_cells: Array[Vector2i] = []
				var valid := true
				for local_cell in oriented_shape:
					var target := origin + local_cell
					if target.x < 0 or target.x >= BOARD_SIZE or target.y < 0 or target.y >= BOARD_SIZE or board[target.y][target.x] != EMPTY:
						valid = false
						break
					board_cells.append(target)
				if valid:
					candidates.append(Placement.new(oriented_shape.duplicate(), board_cells))
	return candidates

func shape_catalog() -> Array:
	return [
		# Extra rectangular pieces: 2x3, 1x3, 2x1 and 1x1.
		[Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1), Vector2i(0, 2), Vector2i(1, 2)],
		[Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0)],
		[Vector2i(0, 0), Vector2i(1, 0)],
		# Seven classic tetrominoes: I, O, T, S, Z, J and L.
		[Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(3, 0)],
		[Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1)],
		[Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(1, 1)],
		[Vector2i(1, 0), Vector2i(2, 0), Vector2i(0, 1), Vector2i(1, 1)],
		[Vector2i(0, 0), Vector2i(1, 0), Vector2i(1, 1), Vector2i(2, 1)],
		[Vector2i(0, 0), Vector2i(0, 1), Vector2i(1, 1), Vector2i(2, 1)],
		[Vector2i(2, 0), Vector2i(0, 1), Vector2i(1, 1), Vector2i(2, 1)],
		[Vector2i(0, 0)]
	]

func unique_orientations(base_shape: Array[Vector2i]) -> Array:
	var orientations: Array = []
	var keys := {}
	var current := base_shape.duplicate()
	for rotation_index in 4:
		var normalized := normalize_shape(current)
		var key := shape_key(normalized)
		if not keys.has(key):
			keys[key] = true
			orientations.append(normalized)
		var rotated: Array[Vector2i] = []
		for cell in current:
			rotated.append(Vector2i(-cell.y, cell.x))
		current = rotated
	return orientations

func normalize_shape(shape: Array[Vector2i]) -> Array[Vector2i]:
	var normalized: Array[Vector2i] = []
	var min_x := shape[0].x
	var min_y := shape[0].y
	for cell in shape:
		min_x = min(min_x, cell.x)
		min_y = min(min_y, cell.y)
	for cell in shape:
		normalized.append(cell - Vector2i(min_x, min_y))
	normalized.sort()
	return normalized

func shape_key(shape: Array[Vector2i]) -> String:
	var key := ""
	for cell in shape:
		key += "%d,%d;" % [cell.x, cell.y]
	return key

func reset_puzzle() -> void:
	for y in BOARD_SIZE:
		for x in BOARD_SIZE:
			board[y][x] = EMPTY
	for piece in pieces:
		piece.rotation = 0
	next_piece = 0
	score = 0
	combo = 0
	combo_deadline_ms = 0
	for slot in active_slots.size():
		active_slots[slot] = take_next_piece()
	dragging_piece = -1
	message = "Puzzle reset. Try a new arrangement."
	hide_game_over()
	hide_win()
	refresh_views()

func take_next_piece() -> int:
	if next_piece >= draw_order.size():
		return create_extra_piece()
	var fitting_large: Array[int] = []
	var fitting_single: Array[int] = []
	for index in range(next_piece, draw_order.size()):
		var candidate_id: int = draw_order[index]
		if piece_can_fit(candidate_id):
			if pieces[candidate_id].cells.size() == 1:
				fitting_single.append(index)
			else:
				fitting_large.append(index)
	var chosen_index := next_piece
	if not fitting_large.is_empty():
		chosen_index = fitting_large[rng.randi_range(0, fitting_large.size() - 1)]
	elif not fitting_single.is_empty():
		chosen_index = fitting_single[rng.randi_range(0, fitting_single.size() - 1)]
	var id: int = draw_order[chosen_index]
	draw_order[chosen_index] = draw_order[next_piece]
	draw_order[next_piece] = id
	next_piece += 1
	return id

func create_extra_piece() -> int:
	var fitting_shapes: Array = []
	var largest_size := 0
	for base_shape in shape_catalog():
		var typed_shape: Array[Vector2i] = []
		for cell in base_shape:
			typed_shape.append(cell)
		for orientation in unique_orientations(typed_shape):
			var cells: Array[Vector2i] = orientation
			if cells_can_fit(cells):
				fitting_shapes.append(cells)
				largest_size = maxi(largest_size, cells.size())
	if fitting_shapes.is_empty():
		var fallback: Array[Vector2i] = [Vector2i.ZERO]
		var fallback_color: Color = PALETTE[pieces.size() % PALETTE.size()]
		pieces.append(PuzzlePiece.new(fallback, [], fallback_color))
		return pieces.size() - 1
	var chosen: Array[Vector2i] = fitting_shapes[rng.randi_range(0, fitting_shapes.size() - 1)]
	# Give a useful large piece often enough to keep the late game alive.
	if rng.randf() < 0.35:
		var largest: Array = []
		for candidate in fitting_shapes:
			if candidate.size() == largest_size:
				largest.append(candidate)
		if not largest.is_empty():
			chosen = largest[rng.randi_range(0, largest.size() - 1)]
	var piece_color: Color = PALETTE[pieces.size() % PALETTE.size()]
	pieces.append(PuzzlePiece.new(chosen.duplicate(), [], piece_color))
	return pieces.size() - 1

func piece_can_fit(piece_id: int) -> bool:
	return cells_can_fit(pieces[piece_id].cells)

func cells_can_fit(base_cells: Array[Vector2i]) -> bool:
	for orientation in unique_orientations(base_cells):
		for y in BOARD_SIZE:
			for x in BOARD_SIZE:
				var valid := true
				for cell in orientation:
					var target: Vector2i = Vector2i(x, y) + cell
					if target.x >= BOARD_SIZE or target.y >= BOARD_SIZE or board[target.y][target.x] != EMPTY:
						valid = false
						break
				if valid:
					return true
	return false

func has_available_move() -> bool:
	for piece_id in active_slots:
		if piece_id != -1 and piece_can_fit(piece_id):
			return true
	return false

func start_drag(piece_id: int, global_position: Vector2) -> void:
	dragging_piece = piece_id
	drag_position = board_local_position(global_position)
	update_drag_lift()
	refresh_views()

func update_drag_lift() -> void:
	if dragging_piece == -1:
		return
	var max_y := 0
	for cell in pieces[dragging_piece].rotated_cells():
		max_y = maxi(max_y, cell.y)
	board_view.set_drag_lift(maxf(1.65, max_y + 1.25))

func rotate_piece(piece_id: int) -> void:
	var now := Time.get_ticks_msec()
	# Some Android devices emit both touch and mouse events for one tap.
	# Ignore the duplicate so every user tap rotates exactly 90 degrees.
	if now - last_rotation_ms < 180:
		return
	last_rotation_ms = now
	pieces[piece_id].rotation = (pieces[piece_id].rotation + 1) % 4
	if dragging_piece == piece_id:
		update_drag_lift()
	refresh_views()

func move_drag(position: Vector2) -> void:
	if dragging_piece == -1:
		return
	drag_position = position
	refresh_views()

func board_local_position(global_position: Vector2) -> Vector2:
	return board_view.get_global_transform_with_canvas().affine_inverse() * global_position

func drop_piece(origin: Vector2i) -> void:
	if dragging_piece == -1:
		return
	var piece_id := dragging_piece
	var placed := place_piece(piece_id, origin)
	dragging_piece = -1
	refresh_views()
	if placed:
		var placed_cells: Array[Vector2i] = []
		for cell in pieces[piece_id].rotated_cells():
			placed_cells.append(origin + cell)
		board_view.animate_placement(placed_cells)

func _input(event: InputEvent) -> void:
	if how_to_modal.visible or game_over_modal.visible or win_modal.visible or dragging_piece == -1:
		return
	var position := Vector2.ZERO
	var moving := false
	var released := false
	if event is InputEventMouseMotion:
		position = event.position
		moving = true
	elif event is InputEventScreenDrag:
		position = event.position
		moving = true
	elif event is InputEventMouseButton:
		position = event.position
		released = event.button_index == MOUSE_BUTTON_LEFT and not event.pressed
	elif event is InputEventScreenTouch:
		position = event.position
		released = not event.pressed
	if moving:
		drag_position = board_local_position(position)
		refresh_views()
	elif released:
		var local_position: Vector2 = board_local_position(position)
		# Place using the lifted block preview, not the finger's physical position.
		# This keeps bottom-row placement reliable even when the finger is below the board.
		drop_piece(board_view.origin_at(local_position))

func place_piece(piece_id: int, origin: Vector2i) -> bool:
	if not can_place(piece_id, origin):
		message = "That piece does not fit there."
		return false
	var completed_before := completed_region_count()
	var completed_before_regions := completed_regions_list()
	var placed_cells := pieces[piece_id].rotated_cells()
	for cell in placed_cells:
		var target := origin + cell
		board[target.y][target.x] = piece_id
	if Time.get_ticks_msec() > combo_deadline_ms:
		combo = 0
	combo += 1
	combo_deadline_ms = Time.get_ticks_msec() + 1500
	var completed_regions := completed_region_count() - completed_before
	var completed_after_regions := completed_regions_list()
	var newly_completed: Array[int] = []
	for region in completed_after_regions:
		if not completed_before_regions.has(region):
			newly_completed.append(region)
	var multiplier := combo
	if completed_regions > 0:
		multiplier *= int(pow(5, completed_regions))
	var earned := placed_cells.size() * 7 * multiplier
	score += earned
	for slot in active_slots.size():
		if active_slots[slot] == piece_id:
			active_slots[slot] = take_next_piece()
	message = "+%d points  /  Combo x%d" % [earned, combo]
	board_view.animate_completed_regions(newly_completed)
	if check_failure():
		return true
	check_completion()
	if not win_modal.visible and not has_available_move():
		message = "No available piece can fit on the board."
		show_game_over()
	return true

func completed_region_count() -> int:
	var completed := 0
	for region in BOARD_SIZE:
		if region_is_full(region) and region_count(region) == targets[region]:
			completed += 1
	return completed

func completed_regions_list() -> Array[int]:
	var completed: Array[int] = []
	for region in BOARD_SIZE:
		if region_is_full(region) and region_count(region) == targets[region]:
			completed.append(region)
	return completed

func can_place(piece_id: int, origin: Vector2i) -> bool:
	for cell in pieces[piece_id].rotated_cells():
		var target := origin + cell
		if target.x < 0 or target.x >= BOARD_SIZE or target.y < 0 or target.y >= BOARD_SIZE or board[target.y][target.x] != EMPTY:
			return false
	return true

func check_completion() -> void:
	for row in board:
		if row.has(EMPTY):
			return
	for region in BOARD_SIZE:
		if region_count(region) != targets[region]:
			message = "Board full, but some region counts do not match."
			return
	message = "Puzzle complete! Every region is satisfied."
	show_win()

func check_failure() -> bool:
	for region in BOARD_SIZE:
		var count := region_count(region)
		if count > targets[region]:
			message = "Too many pieces touch a region."
			show_game_over()
			return true
		if region_is_full(region) and count < targets[region]:
			message = "A full region does not have enough pieces."
			show_game_over()
			return true
	return false

func region_is_full(region: int) -> bool:
	var start_x := (region % 3) * 3
	var start_y := (region / 3) * 3
	for y in range(start_y, start_y + 3):
		for x in range(start_x, start_x + 3):
			if board[y][x] == EMPTY:
				return false
	return true

func region_count(region: int) -> int:
	var touched := {}
	var start_x := (region % 3) * 3
	var start_y := (region / 3) * 3
	for y in range(start_y, start_y + 3):
		for x in range(start_x, start_x + 3):
			if board[y][x] != EMPTY:
				touched[board[y][x]] = true
	return touched.size()

func show_pause_menu() -> void:
	pause_modal.visible = true

func hide_pause_menu() -> void:
	pause_modal.visible = false

func show_game_over() -> void:
	game_over_reason.text = message
	game_over_modal.visible = true

func hide_game_over() -> void:
	game_over_modal.visible = false

func hide_how_to() -> void:
	how_to_modal.visible = false

func show_win() -> void:
	win_modal.visible = true

func hide_win() -> void:
	win_modal.visible = false

func next_level() -> void:
	level += 1
	save_progress()
	new_puzzle()

func load_progress() -> void:
	var config := ConfigFile.new()
	if config.load(SAVE_PATH) == OK:
		level = maxi(1, int(config.get_value("progress", "level", 1)))

func save_progress() -> void:
	var config := ConfigFile.new()
	config.set_value("progress", "level", level)
	config.save(SAVE_PATH)

func refresh_views() -> void:
	status_label.text = message
	level_label.text = "LEVEL %d  /  TARGETS 3-%d" % [level, maximum_region_target()]
	score_label.text = "%s" % score
	combo_label.text = "COMBO x%d" % maxi(1, combo)
	combo_label.visible = combo > 0
	board_view.configure(board, pieces, targets, dragging_piece, drag_position)
	var completed_flags: Array[bool] = []
	completed_flags.resize(BOARD_SIZE)
	completed_flags.fill(false)
	for region in completed_regions_list():
		completed_flags[region] = true
	board_view.set_completed_regions(completed_flags)
	tray_view.configure(pieces, active_slots)
