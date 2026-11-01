extends Control

const BOARD_SIZE := 9
const REGION_SIZE := 3
const EMPTY := -1
const SAVE_PATH := "user://progress.cfg"
# Preloaded rather than global class_names, so the game runs even before the
# editor has rescanned the project for new classes.
const SudorisSettings := preload("res://settings.gd")
const SudorisStrings := preload("res://strings.gd")

## Piece colours, used in order. Select the root "Sudoris" node to edit them.
@export var palette: Array[Color] = [Color("#ef5d50"), Color("#f59f45"), Color("#f2d35e"), Color("#4ec982"), Color("#30b8b0"), Color("#49a5e6"), Color("#8b78e6"), Color("#e46aa8")]

@export_group("Scoring")
## Points for each square of a placed piece (before multipliers).
@export var points_per_square := 7
## Each region completed by one move multiplies the points by this, again per region.
@export var region_multiplier := 5
## Milliseconds the next move has to keep the combo going.
@export var combo_window_ms := 1500

@export_group("Level Help")
## Levels up to and including this one deal helpful pieces. 0 turns the help off.
@export var help_max_level := 1
## Completed regions needed before helpful pieces start to appear.
@export_range(0, 9) var help_after_regions := 5
## Chance that a refilled tray slot gets a piece that can complete a region.
## Only used while no piece in the tray can already complete one, so at most
## one slot is helped at a time and the player can still lose.
@export_range(0.0, 1.0, 0.05) var help_chance := 0.6

@export_group("Drag")
## Minimum height (in cells) of the dragged piece above the finger.
@export_range(0.5, 4.0, 0.05) var min_drag_lift := 1.65
## Extra gap (in cells) between the finger and the bottom of a tall piece.
@export_range(0.0, 3.0, 0.05) var drag_lift_margin := 1.25

@export_group("Haptics")
## Vibrate the phone when a piece is placed and when a region is completed.
@export var haptics_enabled := true
## Length of the tiny buzz when a piece lands, in milliseconds.
@export_range(1, 200) var place_vibration_ms := 20
## Strength of that buzz (Android only; browsers ignore it).
@export_range(0.0, 1.0, 0.05) var place_vibration_strength := 0.3
## Completing a region buzzes this many times stronger and longer than a placement.
@export_range(1.0, 4.0, 0.5) var region_vibration_scale := 2.0

@export_group("Time Attack")
## Seconds on the clock when a Time Attack run starts.
@export_range(5.0, 300.0, 1.0) var time_attack_start_seconds := 45.0
## Seconds added for every completed region.
@export_range(0.0, 120.0, 1.0) var time_attack_bonus_seconds := 20.0
## The clock turns red below this many seconds.
@export_range(0.0, 60.0, 1.0) var time_attack_warning_seconds := 10.0
## New regions get counts from 3 to 4 at first; every this many completed regions
## the highest possible count grows by one, up to 6.
@export_range(1, 20) var time_attack_target_growth := 3
## Clock colour while time is running low.
@export var time_attack_warning_color := Color("#ff8a6b")

@export_group("Settings Toggles")
## Look of a settings switch that is on.
@export var toggle_on_style: StyleBox
## Look of a settings switch that is off.
@export var toggle_off_style: StyleBox

enum Mode { CLASSIC, TIME_ATTACK }

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
@onready var timer_label: Label = %TimerLabel
@onready var game_over_title: Label = %GameOverTitle
@onready var main_menu: Control = %MainMenu
@onready var classic_info: Label = %ClassicInfo
@onready var time_attack_info: Label = %TimeAttackInfo
@onready var settings_modal: Control = %SettingsModal
@onready var sound_toggle: Button = %SoundToggle
@onready var music_toggle: Button = %MusicToggle
@onready var vibration_toggle: Button = %VibrationToggle
@onready var language_button: Button = %LanguageButton

var rng := RandomNumberGenerator.new()
var pieces: Array[PuzzlePiece] = []
var board: Array = []
var targets: Array[int] = []
var active_slots: Array[int] = [-1, -1, -1]
var draw_order: Array[int] = []
var next_piece := 0
var dragging_piece := -1
var drag_position := Vector2.ZERO
var message := ""
var last_rotation_ms := -1000
var last_action_ms := -1000
var solution_piece_count := 0
var drag_layer: Control
var level := 1
var score := 0
var combo := 0
var combo_deadline_ms := 0
## Duration and strength of the last vibration sent, for tests.
var last_vibration := Vector2.ZERO
var mode := Mode.CLASSIC
## Seconds left in a Time Attack run.
var time_left := 0.0
var best_time_attack_score := 0
## Regions completed in the current Time Attack run.
var time_attack_regions := 0
## The rules are shown automatically before the very first game.
var how_to_seen := false
var settings := SudorisSettings.new()

func _ready() -> void:
	rng.randomize()
	settings.load_settings()
	settings.apply()
	load_progress()
	_connect_action_button(%ResetButton, reset_puzzle)
	_connect_action_button(%PauseButton, show_pause_menu)
	_connect_action_button(%ResumeButton, hide_pause_menu)
	_connect_action_button(%NewPuzzleButton, new_puzzle)
	_connect_action_button(%RestartButton, new_puzzle)
	_connect_action_button(%HowToPlayButton, hide_how_to)
	_connect_action_button(%NextLevelButton, next_level)
	_connect_action_button(%ClassicButton, start_mode.bind(Mode.CLASSIC))
	_connect_action_button(%TimeAttackButton, start_mode.bind(Mode.TIME_ATTACK))
	_connect_action_button(%MenuSettingsButton, show_settings)
	_connect_action_button(%PauseSettingsButton, show_settings)
	_connect_action_button(%PauseMenuButton, show_main_menu)
	_connect_action_button(%GameOverMenuButton, show_main_menu)
	_connect_action_button(%WinMenuButton, show_main_menu)
	_connect_action_button(sound_toggle, toggle_sound)
	_connect_action_button(music_toggle, toggle_music)
	_connect_action_button(vibration_toggle, toggle_vibration)
	_connect_action_button(language_button, change_language)
	_connect_action_button(%SettingsHowToButton, show_how_to)
	_connect_action_button(%SettingsCloseButton, hide_settings)
	tray_view.piece_picked.connect(start_drag)
	tray_view.rotate_requested.connect(rotate_piece)
	board_view.dropped.connect(drop_piece)
	board_view.drag_moved.connect(move_drag)
	# Holds the piece that follows the finger; sits above the tray but below the modals.
	drag_layer = Control.new()
	drag_layer.name = "DragLayer"
	drag_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	drag_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(drag_layer)
	move_child(drag_layer, $Margin.get_index() + 1)
	drag_layer.draw.connect(func() -> void: board_view.draw_floating(drag_layer))
	board_view.floating_layer = drag_layer
	new_puzzle()
	show_main_menu()

func _process(delta: float) -> void:
	if combo > 0 and Time.get_ticks_msec() > combo_deadline_ms:
		combo = 0
		refresh_views()
	if mode == Mode.TIME_ATTACK and is_playing():
		tick_clock(delta)

## Runs the Time Attack clock down; the run ends when it reaches zero.
func tick_clock(delta: float) -> void:
	time_left = maxf(time_left - delta, 0.0)
	refresh_timer()
	if time_left <= 0.0:
		time_up()

## True while the board is on screen and no menu or window covers it.
func is_playing() -> bool:
	return not (main_menu.visible or pause_modal.visible or game_over_modal.visible or win_modal.visible or how_to_modal.visible or settings_modal.visible)

func _connect_action_button(button: Button, action: Callable) -> void:
	button.gui_input.connect(_on_action_button_input.bind(action))

func _on_action_button_input(event: InputEvent, action: Callable) -> void:
	var released := false
	if event is InputEventScreenTouch:
		released = not event.pressed
	elif event is InputEventMouseButton:
		released = event.button_index == MOUSE_BUTTON_LEFT and not event.pressed
	if released:
		get_viewport().set_input_as_handled()
		# Mouse clicks also emit an emulated touch (emulate_touch_from_mouse), so one
		# click arrives twice. Run the action once per tap.
		var now := Time.get_ticks_msec()
		if now - last_action_ms < 250:
			return
		last_action_ms = now
		action.call()

func new_puzzle() -> void:
	draw_order.clear()
	var valid_puzzle := false
	var built := false
	for attempt in 160:
		prepare_empty_board()
		built = build_solution_from_catalog()
		if not built:
			continue
		calculate_targets()
		if targets_match_difficulty():
			valid_puzzle = true
			break
	if not valid_puzzle:
		push_warning("Could not generate every requested target after 160 attempts; using the closest valid puzzle.")
	while not built:
		prepare_empty_board()
		built = build_solution_from_catalog()
		calculate_targets()
	solution_piece_count = pieces.size()
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
	time_left = time_attack_start_seconds
	time_attack_regions = 0
	for slot in active_slots.size():
		active_slots[slot] = take_next_piece()
	dragging_piece = -1
	message = intro_message()
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

func intro_message() -> String:
	if mode == Mode.TIME_ATTACK:
		return tr("Complete regions to win more time.")
	return tr("Fill the board and make every region count match.")

func maximum_region_target() -> int:
	# Time Attack always plays with the first level's targets.
	var difficulty := 1 if mode == Mode.TIME_ATTACK else level
	if difficulty <= 2:
		return 5
	if difficulty <= 4:
		return 6
	return 7

func targets_match_difficulty() -> bool:
	var maximum := maximum_region_target()
	for target in targets:
		if target < 3 or target > maximum:
			return false
	# New values are introduced deliberately instead of only becoming possible.
	return maximum == 5 or targets.has(maximum)

## Placements the generator may try before it gives up on one attempt.
const GENERATOR_STEP_LIMIT := 4000

# Tiles the board with catalog pieces, backtracking when a choice leaves a hole
# no piece can fill. Returns false if the step limit runs out first.
func build_solution_from_catalog() -> bool:
	var steps_left: Array[int] = [GENERATOR_STEP_LIMIT]
	# Levels that need a crowded region fill one region and its edges with small
	# pieces first, so many pieces can touch it.
	var busy_region := -1
	if maximum_region_target() > 5:
		busy_region = rng.randi_range(0, BOARD_SIZE - 1)
	return fill_from_first_empty(steps_left, busy_region)

func fill_from_first_empty(steps_left: Array[int], busy_region: int) -> bool:
	var anchor := first_empty_cell()
	if anchor.x == -1:
		return true
	var candidates := placement_candidates(anchor)
	# Shuffle with our own rng so a seed always builds the same puzzle.
	for index in range(candidates.size() - 1, 0, -1):
		var other := rng.randi_range(0, index)
		var swap := candidates[index]
		candidates[index] = candidates[other]
		candidates[other] = swap
	if busy_region != -1 and near_region(anchor, busy_region):
		var small_first: Array[Placement] = []
		for size in [2, 3, 4, 6]:
			for placement in candidates:
				if placement.board_cells.size() == size:
					small_first.append(placement)
		candidates = small_first
	for placement in candidates:
		if steps_left[0] <= 0:
			return false
		steps_left[0] -= 1
		var piece_id := pieces.size()
		var palette_cycle: int = int(piece_id / palette.size())
		var piece_color: Color = palette[piece_id % palette.size()].lightened(palette_cycle * 0.08)
		pieces.append(PuzzlePiece.new(placement.local_cells, placement.board_cells, piece_color))
		for cell in placement.board_cells:
			board[cell.y][cell.x] = piece_id
		if not leaves_stranded_cell(placement.board_cells) and fill_from_first_empty(steps_left, busy_region):
			return true
		for cell in placement.board_cells:
			board[cell.y][cell.x] = EMPTY
		pieces.pop_back()
	return false

# True if the cell is inside the region or right next to its edge.
func near_region(cell: Vector2i, region: int) -> bool:
	var start := Vector2i((region % 3) * REGION_SIZE, (region / 3) * REGION_SIZE)
	return cell.x >= start.x - 1 and cell.x <= start.x + REGION_SIZE and cell.y >= start.y - 1 and cell.y <= start.y + REGION_SIZE

# True if filling these (already occupied) cells cut off an empty square from
# every other empty square. Every piece is at least two squares, so such a hole
# can never be filled.
func leaves_stranded_cell(filled: Array[Vector2i]) -> bool:
	const SIDES: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	for cell in filled:
		for side in SIDES:
			var neighbour := cell + side
			if not cell_is_empty(neighbour):
				continue
			var stranded := true
			for other_side in SIDES:
				if cell_is_empty(neighbour + other_side):
					stranded = false
					break
			if stranded:
				return true
	return false

# Like leaves_stranded_cell, but ignores squares that were cut off before.
func strands_new_cell(filled: Array[Vector2i], ignored: Dictionary) -> bool:
	const SIDES: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	for cell in filled:
		for side in SIDES:
			var neighbour := cell + side
			if not cell_is_empty(neighbour) or ignored.has(neighbour):
				continue
			var stranded := true
			for other_side in SIDES:
				if cell_is_empty(neighbour + other_side):
					stranded = false
					break
			if stranded:
				return true
	return false

func cell_is_empty(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.x < BOARD_SIZE and cell.y >= 0 and cell.y < BOARD_SIZE and board[cell.y][cell.x] == EMPTY

func first_empty_cell() -> Vector2i:
	for y in BOARD_SIZE:
		for x in BOARD_SIZE:
			if board[y][x] == EMPTY:
				return Vector2i(x, y)
	return Vector2i(-1, -1)

func placement_candidates(anchor: Vector2i) -> Array[Placement]:
	var candidates: Array[Placement] = []
	var catalog := shape_catalog()
	for base_shape in catalog:
		var typed_shape: Array[Vector2i] = []
		for cell in base_shape:
			typed_shape.append(cell)
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
		# Extra rectangular pieces: 2x3, 1x3 and 2x1.
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
		[Vector2i(2, 0), Vector2i(0, 1), Vector2i(1, 1), Vector2i(2, 1)]
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
	if mode == Mode.TIME_ATTACK:
		# A Time Attack board changes as it goes, so resetting starts a new run.
		new_puzzle()
		return
	for y in BOARD_SIZE:
		for x in BOARD_SIZE:
			board[y][x] = EMPTY
	# Drop extra pieces generated during the previous attempt.
	pieces.resize(solution_piece_count)
	for piece in pieces:
		piece.rotation = 0
	next_piece = 0
	score = 0
	combo = 0
	combo_deadline_ms = 0
	for slot in active_slots.size():
		active_slots[slot] = take_next_piece()
	dragging_piece = -1
	message = tr("Puzzle reset. Try a new arrangement.")
	hide_game_over()
	hide_win()
	refresh_views()

func take_next_piece() -> int:
	if help_is_active() and rng.randf() < help_chance and not tray_can_complete_region():
		var helpful := take_helpful_piece()
		if helpful != -1:
			return helpful
	if next_piece >= draw_order.size():
		return create_extra_piece()
	var fitting: Array[int] = []
	for index in range(next_piece, draw_order.size()):
		if piece_can_fit(draw_order[index]):
			fitting.append(index)
	var chosen_index := next_piece
	if not fitting.is_empty():
		chosen_index = fitting[rng.randi_range(0, fitting.size() - 1)]
	var id: int = draw_order[chosen_index]
	draw_order[chosen_index] = draw_order[next_piece]
	draw_order[next_piece] = id
	next_piece += 1
	return id

func help_is_active() -> bool:
	return mode == Mode.CLASSIC and level <= help_max_level and completed_region_count() >= help_after_regions

func tray_can_complete_region() -> bool:
	for piece_id in active_slots:
		if piece_id != -1 and cells_can_complete_region(pieces[piece_id].cells):
			return true
	return false

# Deals a piece that can finish a region without breaking any rule: an undrawn
# solution piece if one works, otherwise a fresh catalog shape. Returns -1 if none can.
func take_helpful_piece() -> int:
	var helpful: Array[int] = []
	for index in range(next_piece, draw_order.size()):
		if cells_can_complete_region(pieces[draw_order[index]].cells):
			helpful.append(index)
	if not helpful.is_empty():
		var chosen_index := helpful[rng.randi_range(0, helpful.size() - 1)]
		var id: int = draw_order[chosen_index]
		draw_order[chosen_index] = draw_order[next_piece]
		draw_order[next_piece] = id
		next_piece += 1
		return id
	var helpful_shapes: Array = []
	for base_shape in shape_catalog():
		var typed_shape: Array[Vector2i] = []
		typed_shape.assign(base_shape)
		if cells_can_complete_region(typed_shape):
			helpful_shapes.append(typed_shape)
	if helpful_shapes.is_empty():
		return -1
	var chosen: Array[Vector2i] = helpful_shapes[rng.randi_range(0, helpful_shapes.size() - 1)]
	var no_solution: Array[Vector2i] = []
	pieces.append(PuzzlePiece.new(chosen.duplicate(), no_solution, palette[pieces.size() % palette.size()]))
	return pieces.size() - 1

# True if some rotation and position of these cells completes a region,
# leaves every region it touches within the rules and does not cut off a
# one-square hole that no piece could fill afterwards.
func cells_can_complete_region(base_cells: Array[Vector2i]) -> bool:
	const PROBE := -2
	for orientation in unique_orientations(base_cells):
		for y in BOARD_SIZE:
			for x in BOARD_SIZE:
				var placed: Array[Vector2i] = []
				for cell in orientation:
					var target: Vector2i = Vector2i(x, y) + cell
					if target.x >= BOARD_SIZE or target.y >= BOARD_SIZE or board[target.y][target.x] != EMPTY:
						placed.clear()
						break
					placed.append(target)
				if placed.is_empty():
					continue
				var touched := {}
				for target in placed:
					board[target.y][target.x] = PROBE
					touched[int(target.y / REGION_SIZE) * 3 + int(target.x / REGION_SIZE)] = true
				var safe := not leaves_stranded_cell(placed)
				var completes := false
				if safe:
					for region in touched:
						if region_failure(region) != "":
							safe = false
							break
						if region_is_full(region):
							completes = true
				for target in placed:
					board[target.y][target.x] = EMPTY
				if safe and completes:
					return true
	return false

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
		# Only one-square holes are left, so nothing fits; the smallest piece ends the game.
		var fallback: Array[Vector2i] = [Vector2i(0, 0), Vector2i(1, 0)]
		var fallback_color: Color = palette[pieces.size() % palette.size()]
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
	var piece_color: Color = palette[pieces.size() % palette.size()]
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
	board_view.begin_drag(drag_position)
	update_drag_lift()
	refresh_views()

func update_drag_lift() -> void:
	if dragging_piece == -1:
		return
	var max_y := 0
	for cell in pieces[dragging_piece].rotated_cells():
		max_y = maxi(max_y, cell.y)
	board_view.set_drag_lift(maxf(min_drag_lift, max_y + drag_lift_margin))

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
	tray_view.animate_rotation(piece_id)

func move_drag(position: Vector2) -> void:
	if dragging_piece == -1:
		return
	update_drag_position(position)

func update_drag_position(position: Vector2) -> void:
	# Only redraw the board and the floating piece; a full refresh per motion event is too slow.
	drag_position = position
	board_view.update_drag(drag_position)
	drag_layer.queue_redraw()

func board_local_position(global_position: Vector2) -> Vector2:
	return board_view.get_global_transform_with_canvas().affine_inverse() * global_position

func drop_piece(origin: Vector2i) -> void:
	if dragging_piece == -1:
		return
	var piece_id := dragging_piece
	if origin == SudorisBoard.NO_ORIGIN:
		# Released away from the board: return the piece to the tray quietly.
		dragging_piece = -1
		refresh_views()
		return
	var from_offset := board_view.settle_offset(origin)
	var placed := place_piece(piece_id, origin)
	dragging_piece = -1
	refresh_views()
	if placed:
		var placed_cells: Array[Vector2i] = []
		for cell in pieces[piece_id].rotated_cells():
			placed_cells.append(origin + cell)
		board_view.animate_placement(placed_cells, from_offset)

func _input(event: InputEvent) -> void:
	if not is_playing() or dragging_piece == -1:
		return
	var position := Vector2.ZERO
	var moving := false
	var released := false
	if event is InputEventMouseMotion:
		position = event.position
		moving = true
	elif event is InputEventScreenDrag:
		# Only the first finger drags; a second finger must not move or drop the piece.
		if event.index != 0:
			return
		position = event.position
		moving = true
	elif event is InputEventMouseButton:
		position = event.position
		released = event.button_index == MOUSE_BUTTON_LEFT and not event.pressed
	elif event is InputEventScreenTouch:
		if event.index != 0:
			return
		position = event.position
		released = not event.pressed
	if moving:
		update_drag_position(board_local_position(position))
	elif released:
		var local_position: Vector2 = board_local_position(position)
		# Place using the lifted block preview, not the finger's physical position.
		# This keeps bottom-row placement reliable even when the finger is below the board.
		drop_piece(board_view.origin_at(local_position))

func place_piece(piece_id: int, origin: Vector2i) -> bool:
	if not can_place(piece_id, origin):
		message = tr("That piece does not fit there.")
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
	combo_deadline_ms = Time.get_ticks_msec() + combo_window_ms
	var completed_regions := completed_region_count() - completed_before
	var completed_after_regions := completed_regions_list()
	var newly_completed: Array[int] = []
	for region in completed_after_regions:
		if not completed_before_regions.has(region):
			newly_completed.append(region)
	var multiplier := combo
	if completed_regions > 0:
		multiplier *= int(pow(region_multiplier, completed_regions))
	var earned := placed_cells.size() * points_per_square * multiplier
	score += earned
	var vanishing := {}
	if mode == Mode.TIME_ATTACK and not newly_completed.is_empty():
		# Completed regions empty out before the tray refills, so new pieces suit the new board.
		vanishing = replace_regions(newly_completed)
		time_left += time_attack_bonus_seconds * newly_completed.size()
	for slot in active_slots.size():
		if active_slots[slot] == piece_id:
			# Clear the slot first so the placed piece is not counted as still in the tray.
			active_slots[slot] = -1
			active_slots[slot] = take_next_piece()
	message = tr("+%d points  /  Combo x%d") % [earned, combo]
	if mode == Mode.TIME_ATTACK and not newly_completed.is_empty():
		message += tr("  /  +%d s") % int(time_attack_bonus_seconds * newly_completed.size())
	var board_cells: Array[Vector2i] = []
	for cell in placed_cells:
		board_cells.append(origin + cell)
	board_view.animate_completed_regions(newly_completed, board_cells, vanishing)
	vibrate_for_move(not newly_completed.is_empty())
	board_view.animate_wave(new_completed_lines(completed_before_regions, completed_after_regions))
	if check_failure():
		return true
	if mode == Mode.CLASSIC:
		check_completion()
	if not win_modal.visible and not has_available_move():
		message = tr("No available piece can fit on the board.")
		show_game_over()
	return true

# A tiny buzz for a placed piece, a stronger and longer one when a region completes.
# Browsers can only vary the length, so the length grows with the strength.
func vibrate_for_move(completed_region: bool) -> void:
	if not haptics_enabled or not settings.vibration:
		return
	var factor := region_vibration_scale if completed_region else 1.0
	var duration := int(round(place_vibration_ms * factor))
	var strength := minf(place_vibration_strength * factor, 1.0)
	last_vibration = Vector2(duration, strength)
	Input.vibrate_handheld(duration, strength)

const REGION_LINES := [[0, 1, 2], [3, 4, 5], [6, 7, 8], [0, 3, 6], [1, 4, 7], [2, 5, 8]]

# Rows or columns of three regions that became fully completed with this move.
func new_completed_lines(before: Array[int], after: Array[int]) -> Array:
	var lines: Array = []
	for line in REGION_LINES:
		var done_after := true
		var done_before := true
		for region in line:
			done_after = done_after and after.has(region)
			done_before = done_before and before.has(region)
		if done_after and not done_before:
			lines.append(line)
	return lines

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
			message = tr("Board full, but some region counts do not match.")
			return
	message = tr("Puzzle complete! Every region is satisfied.")
	show_win()

func check_failure() -> bool:
	for region in BOARD_SIZE:
		var failure := region_failure(region)
		if failure != "":
			message = tr(failure)
			show_game_over()
			return true
	return false

# Why this region breaks the rules, or "" if it is fine.
func region_failure(region: int) -> String:
	var count := region_count(region)
	if count > targets[region]:
		return "Too many pieces touch a region."
	if count == targets[region] and not region_is_full(region):
		return "A region reached its target before all squares were filled."
	if region_is_full(region) and count < targets[region]:
		return "A full region does not have enough pieces."
	return ""

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

# Shows a modal and plays the "open" animation of its Animator (an AnimationPlayer
# child), which can be edited in the Animation panel.
func open_modal(modal: Control) -> void:
	modal.visible = true
	var animator := modal.get_node_or_null("Animator") as AnimationPlayer
	if animator and animator.has_animation("open"):
		animator.stop()
		animator.play("open")

func show_pause_menu() -> void:
	open_modal(pause_modal)

func hide_pause_menu() -> void:
	pause_modal.visible = false

func show_game_over() -> void:
	dragging_piece = -1
	if mode == Mode.TIME_ATTACK:
		var record := score > best_time_attack_score
		best_time_attack_score = maxi(best_time_attack_score, score)
		save_progress()
		game_over_title.text = tr("TIME'S UP") if time_left <= 0.0 else tr("RUN OVER")
		game_over_reason.text = message + "\n" + tr("Score: %d  /  Best: %d") % [score, best_time_attack_score]
		if record and score > 0:
			game_over_reason.text += "\n" + tr("New record!")
	else:
		# Failing a puzzle sends the player back to the first level.
		level = 1
		save_progress()
		game_over_title.text = tr("GAME FAILED")
		game_over_reason.text = message + "\n" + tr("Back to level 1.")
	refresh_views()
	open_modal(game_over_modal)

func time_up() -> void:
	time_left = 0.0
	message = tr("Time is up.")
	show_game_over()

func hide_game_over() -> void:
	game_over_modal.visible = false

func show_how_to() -> void:
	open_modal(how_to_modal)

func hide_how_to() -> void:
	how_to_modal.visible = false

func start_mode(new_mode: Mode) -> void:
	mode = new_mode
	new_puzzle()
	main_menu.visible = false
	if not how_to_seen:
		how_to_seen = true
		save_progress()
		show_how_to()

func show_main_menu() -> void:
	dragging_piece = -1
	hide_pause_menu()
	hide_game_over()
	hide_win()
	refresh_menu()
	main_menu.visible = true

func refresh_menu() -> void:
	classic_info.text = tr("LEVEL %d") % level
	if best_time_attack_score > 0:
		time_attack_info.text = tr("BEST %d") % best_time_attack_score
	else:
		time_attack_info.text = tr("%d S START  /  +%d S PER REGION") % [int(time_attack_start_seconds), int(time_attack_bonus_seconds)]

func show_settings() -> void:
	refresh_settings()
	open_modal(settings_modal)

func hide_settings() -> void:
	settings_modal.visible = false

func toggle_sound() -> void:
	settings.sound = not settings.sound
	save_and_apply_settings()

func toggle_music() -> void:
	settings.music = not settings.music
	save_and_apply_settings()

func toggle_vibration() -> void:
	settings.vibration = not settings.vibration
	save_and_apply_settings()
	# A short buzz so the player feels that vibration is back on.
	if settings.vibration:
		vibrate_for_move(false)

func change_language() -> void:
	settings.next_language()
	save_and_apply_settings()
	message = intro_message()
	refresh_menu()
	refresh_views()

func save_and_apply_settings() -> void:
	settings.save_settings()
	settings.apply()
	refresh_settings()

func refresh_settings() -> void:
	_show_toggle(sound_toggle, settings.sound)
	_show_toggle(music_toggle, settings.music)
	_show_toggle(vibration_toggle, settings.vibration)
	language_button.text = "TÜRKÇE" if settings.language == "tr" else "ENGLISH"

func _show_toggle(toggle: Button, on: bool) -> void:
	toggle.text = tr("ON") if on else tr("OFF")
	var style := toggle_on_style if on else toggle_off_style
	if style:
		for state in ["normal", "hover", "pressed", "focus"]:
			toggle.add_theme_stylebox_override(state, style)
	var text_color := Color(1, 1, 1) if on else Color(0.137255, 0.180392, 0.0784314)
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		toggle.add_theme_color_override(state, text_color)

func show_win() -> void:
	open_modal(win_modal)

func hide_win() -> void:
	win_modal.visible = false

func next_level() -> void:
	if not win_modal.visible:
		return
	level += 1
	save_progress()
	new_puzzle()

func load_progress() -> void:
	var config := ConfigFile.new()
	if config.load(SAVE_PATH) == OK:
		level = maxi(1, int(config.get_value("progress", "level", 1)))
		how_to_seen = bool(config.get_value("progress", "how_to_seen", false))
		best_time_attack_score = maxi(0, int(config.get_value("time_attack", "best_score", 0)))

func save_progress() -> void:
	var config := ConfigFile.new()
	config.set_value("progress", "level", level)
	config.set_value("progress", "how_to_seen", how_to_seen)
	config.set_value("time_attack", "best_score", best_time_attack_score)
	config.save(SAVE_PATH)

func refresh_views() -> void:
	status_label.text = message
	if mode == Mode.TIME_ATTACK:
		level_label.text = tr("TIME ATTACK  /  BEST %d") % best_time_attack_score
	else:
		level_label.text = tr("LEVEL %d  /  TARGETS 3-%d") % [level, maximum_region_target()]
	timer_label.visible = mode == Mode.TIME_ATTACK
	refresh_timer()
	score_label.text = "%s" % score
	combo_label.text = tr("COMBO x%d") % maxi(1, combo)
	combo_label.visible = combo > 0
	board_view.configure(board, pieces, targets, dragging_piece, drag_position)
	var completed_flags: Array[bool] = []
	completed_flags.resize(BOARD_SIZE)
	completed_flags.fill(false)
	for region in completed_regions_list():
		completed_flags[region] = true
	board_view.set_completed_regions(completed_flags)
	tray_view.configure(pieces, active_slots, dragging_piece)
	drag_layer.queue_redraw()

func refresh_timer() -> void:
	if mode != Mode.TIME_ATTACK:
		return
	var seconds := int(ceil(time_left))
	timer_label.text = "%d:%02d" % [seconds / 60, seconds % 60]
	timer_label.modulate = time_attack_warning_color if time_left <= time_attack_warning_seconds else Color.WHITE

# --- Time Attack ----------------------------------------------------------------

## Empties completed regions and gives each a new target with fresh pieces that can
## fill it. Returns the colour every emptied square had, for the vanish effect.
func replace_regions(regions: Array[int]) -> Dictionary:
	var vanishing := {}
	for region in regions:
		for cell in region_cells(region):
			if board[cell.y][cell.x] != EMPTY:
				vanishing[cell] = pieces[board[cell.y][cell.x]].color
			board[cell.y][cell.x] = EMPTY
	# Planned pieces stay on the board until every region is dealt, so two regions
	# emptied by one move never plan the same squares.
	var planned: Array[Vector2i] = []
	for region in regions:
		time_attack_regions += 1
		var first_new := pieces.size()
		targets[region] = deal_region_pieces(region, rng.randi_range(3, time_attack_max_target()))
		for id in range(first_new, pieces.size()):
			planned.append_array(pieces[id].solution_cells)
	for cell in planned:
		board[cell.y][cell.x] = EMPTY
	return vanishing

## Highest count a new region may get: starts at 4 and grows with completed regions.
func time_attack_max_target() -> int:
	var growth := time_attack_regions / maxi(time_attack_target_growth, 1)
	return mini(4 + growth, 6)

func region_cells(region: int) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	var start := Vector2i((region % 3) * REGION_SIZE, (region / 3) * REGION_SIZE)
	for y in range(start.y, start.y + REGION_SIZE):
		for x in range(start.x, start.x + REGION_SIZE):
			cells.append(Vector2i(x, y))
	return cells

## Plans pieces that fill the (empty) region, adds them to the pieces still to be
## dealt and returns how many there are: the region's new target. Counts above 4
## need pieces that reach into neighbouring regions; those only use empty squares
## and keep the neighbours within their rules. Planned pieces are left on the board.
func deal_region_pieces(region: int, wanted: int) -> int:
	var best: Array[Placement] = []
	for attempt in 40:
		var tiling := plan_region_tiling(region, wanted)
		if tiling.is_empty():
			continue
		if best.is_empty() or absi(tiling.size() - wanted) < absi(best.size() - wanted):
			best = tiling
		if best.size() == wanted:
			break
	if best.is_empty() and wanted > 4:
		# Crowded neighbours left no room to reach out; the region can always be
		# filled from inside.
		return deal_region_pieces(region, 4)
	for placement in best:
		var id := pieces.size()
		pieces.append(PuzzlePiece.new(placement.local_cells, placement.board_cells, palette[rng.randi_range(0, palette.size() - 1)]))
		for cell in placement.board_cells:
			board[cell.y][cell.x] = id
		draw_order.insert(rng.randi_range(next_piece, draw_order.size()), id)
	return best.size()

## One random way to fill the region, or [] if the search ran out of steps.
func plan_region_tiling(region: int, wanted: int) -> Array[Placement]:
	var cells := region_cells(region)
	var steps_left: Array[int] = [400]
	var result: Array[Placement] = []
	var first_id := pieces.size()
	# Squares outside the region already cut off from other empty squares outside it
	# (their only way out was through the full region) must not block the plan.
	var already_stranded := {}
	const SIDES: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	for y in BOARD_SIZE:
		for x in BOARD_SIZE:
			var cell := Vector2i(x, y)
			if board[y][x] != EMPTY or cells.has(cell):
				continue
			var cut_off := true
			for side in SIDES:
				if cell_is_empty(cell + side) and not cells.has(cell + side):
					cut_off = false
			if cut_off:
				already_stranded[cell] = true
	# Placements write temporary ids past the real pieces; region_count only needs them distinct.
	if not _tile_region(region, cells, wanted, first_id, steps_left, result, already_stranded):
		result.clear()
	for placement in result:
		for cell in placement.board_cells:
			board[cell.y][cell.x] = EMPTY
	return result

func _tile_region(region: int, cells: Array[Vector2i], wanted: int, next_id: int, steps_left: Array[int], result: Array[Placement], already_stranded: Dictionary) -> bool:
	var anchor := Vector2i(-1, -1)
	for cell in cells:
		if board[cell.y][cell.x] == EMPTY:
			anchor = cell
			break
	if anchor.x == -1:
		return true
	var inside := func(placement: Placement) -> int:
		var count := 0
		for cell in placement.board_cells:
			if int(cell.y / REGION_SIZE) * 3 + int(cell.x / REGION_SIZE) == region:
				count += 1
		return count
	var candidates: Array[Placement] = []
	for placement in placement_candidates(anchor):
		# Up to 4 pieces fit inside a region; only higher counts reach outside it.
		if wanted > 4 or inside.call(placement) == placement.board_cells.size():
			candidates.append(placement)
	for index in range(candidates.size() - 1, 0, -1):
		var other := rng.randi_range(0, index)
		var swap := candidates[index]
		candidates[index] = candidates[other]
		candidates[other] = swap
	if result.size() + 1 < wanted:
		# Still short of the count: try pieces that use few of the region's squares first.
		candidates.sort_custom(func(a: Placement, b: Placement) -> bool: return inside.call(a) < inside.call(b))
	for placement in candidates:
		if steps_left[0] <= 0:
			return false
		steps_left[0] -= 1
		var touched := {}
		for cell in placement.board_cells:
			board[cell.y][cell.x] = next_id
			touched[int(cell.y / REGION_SIZE) * 3 + int(cell.x / REGION_SIZE)] = true
		var safe := result.size() < wanted and not strands_new_cell(placement.board_cells, already_stranded)
		for other_region in touched:
			if safe and other_region != region and region_failure(other_region) != "":
				safe = false
		if safe:
			result.append(placement)
			if _tile_region(region, cells, wanted, next_id + 1, steps_left, result, already_stranded):
				return true
			result.pop_back()
		for cell in placement.board_cells:
			board[cell.y][cell.x] = EMPTY
	return false
