@tool
class_name SudorisSkin
extends Resource
## Every colour, sprite and font used to draw the board and the tray.
## Open skin/default_skin.tres in the Inspector to restyle the game.

@export_group("Sprites")
## Sprite for one square of a piece. It is tinted with the piece colour, so draw it in
## white/grey. Leave empty to use the built-in flat block.
@export var block_texture: Texture2D
## Optional sprite for an empty board square (tinted with Empty Cell Color).
@export var empty_cell_texture: Texture2D
## Icon on the rotate button under each tray slot (tinted with Rotate Icon Color).
@export var rotate_icon: Texture2D
## Sprite used for the sparkles that burst out of a completed region.
@export var sparkle_texture: Texture2D

@export_group("Board")
@export var board_panel_color := Color("#d9d3b8")
@export var board_border_color := Color("#202910")
@export var grid_background_color := Color("#18200f")
@export var empty_cell_color := Color("#eee8cf")
@export var grid_line_color := Color("#a9a68d")
@export var region_line_color := Color("#30391f")
@export_range(1.0, 10.0, 0.5) var region_line_width := 4.0
@export var completed_color := Color("#5eaf4d")
@export var blocked_color := Color("#d8433a")

@export_group("Region Labels")
@export var label_font: Font
@export_range(8, 40) var label_font_size := 17
@export var label_text_color := Color("#11180b")
@export var label_background_color := Color(1.0, 0.99, 0.95, 0.9)

@export_group("Tray")
@export var tray_panel_color := Color("#273417")
@export var tray_border_color := Color("#4d5e29")
@export var slot_color := Color("#18200f")
@export var slot_border_active_color := Color("#829b45")
@export var slot_border_empty_color := Color("#303b20")
@export var rotate_button_color := Color("#33431d")
@export var rotate_button_border_color := Color("#708d3c")
@export var rotate_icon_color := Color("#c4d578")
@export_range(12.0, 48.0, 1.0) var tray_block_size := 28.0

@export_group("Effects")
@export var ring_color := Color(0.78, 1.0, 0.45)
@export var sparkle_colors: Array[Color] = [Color("#fff6a8"), Color("#ffffff"), Color("#b6f56a"), Color("#ffd24a")]

## Draws one square of a piece, using block_texture when set.
func draw_block(canvas: CanvasItem, rect: Rect2, color: Color) -> void:
	if block_texture:
		canvas.draw_texture_rect(block_texture, rect, false, color)
		return
	canvas.draw_rect(rect, color.darkened(0.38))
	canvas.draw_rect(rect.grow(-2.4), color)
	canvas.draw_line(rect.position + Vector2(3, 3), Vector2(rect.end.x - 3, rect.position.y + 3), color.lightened(0.28), 1.2)

func draw_empty_cell(canvas: CanvasItem, rect: Rect2) -> void:
	if empty_cell_texture:
		canvas.draw_texture_rect(empty_cell_texture, rect, false, empty_cell_color)
	else:
		canvas.draw_rect(rect, empty_cell_color)

func font() -> Font:
	return label_font if label_font else ThemeDB.fallback_font

func rounded_box(background: Color, radius: int, border := Color.TRANSPARENT, border_width := 0) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(border_width)
	style.set_corner_radius_all(radius)
	return style
