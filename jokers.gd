extends RefCounted
## The jokers sold in the shop between Classic levels. Edit names, texts and
## prices here; Turkish texts live in strings.gd like every other string.

const PICK_THREE := "pick_three"
const SOLVE_REGION := "solve_region"
const POCKET := "pocket"
const ERASER := "eraser"
const AUTO_PLACE := "auto_place"
const MAKE_PIECE := "make_piece"
const LAST_BREATH := "last_breath"

## Shop order. price is in gold; passive jokers work on their own and can't be tapped.
const CATALOG := {
	POCKET: {"name": "POCKET", "text": "A spare slot for one piece until the level ends. Drag a piece onto it.", "price": 3, "passive": false},
	ERASER: {"name": "ERASER", "text": "Tap a piece on the board to take it off.", "price": 4, "passive": false},
	PICK_THREE: {"name": "PICK 3", "text": "Choose your next 3 pieces yourself.", "price": 4, "passive": false},
	SOLVE_REGION: {"name": "SOLVE", "text": "Tap a region and it is filled correctly.", "price": 5, "passive": false},
	MAKE_PIECE: {"name": "BUILD", "text": "Draw your own piece of 3 or 4 squares.", "price": 5, "passive": false},
	AUTO_PLACE: {"name": "AUTO PLACE", "text": "Puts your 3 tray pieces in the best spots.", "price": 6, "passive": false},
	LAST_BREATH: {"name": "LAST BREATH", "text": "Passive: your next failure keeps your level, then it breaks.", "price": 5, "passive": true},
}

static func ids() -> Array:
	return CATALOG.keys()

static func joker_name(id: String) -> String:
	return CATALOG[id].name if CATALOG.has(id) else ""

static func text(id: String) -> String:
	return CATALOG[id].text if CATALOG.has(id) else ""

static func price(id: String) -> int:
	return CATALOG[id].price if CATALOG.has(id) else 0

## Loaded icons, kept so they stay alive while the canvas still draws them.
static var _icons := {}

## Small picture of the joker, drawn in white in art/jokers/<id>.svg and tinted by the game.
static func icon(id: String) -> Texture2D:
	if not _icons.has(id):
		var path := "res://art/jokers/%s.svg" % id
		_icons[id] = load(path) if CATALOG.has(id) and ResourceLoader.exists(path) else null
	return _icons[id]

static func is_passive(id: String) -> bool:
	return CATALOG.has(id) and CATALOG[id].passive
