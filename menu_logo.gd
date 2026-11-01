@tool
extends Control
## The emblem above the main menu title: one finished 3 x 3 region in the board's style.
## Select the Logo node to change its colours.

## Skin shared with the board, for the panel, squares and count label.
@export var skin: SudorisSkin
## Colours of the three pieces, in the order they appear in the pattern.
@export var colors: Array[Color] = [Color("#ef5d50"), Color("#f2d35e"), Color("#30b8b0")]

const PATTERN := ["AAB", "ACB", "CCB"]

var _default_skin := SudorisSkin.new()

func _draw() -> void:
	var look := skin if skin else _default_skin
	var side := minf(size.x, size.y)
	var panel := Rect2((size - Vector2.ONE * side) * 0.5, Vector2.ONE * side)
	var style := look.rounded_box(look.board_panel_color, 18)
	style.shadow_color = Color(0.05, 0.08, 0.02, 0.45)
	style.shadow_size = 8
	style.shadow_offset = Vector2(0, 5)
	draw_style_box(style, panel)
	var grid := panel.grow(-side * 0.09)
	draw_rect(grid.grow(3.0), look.grid_background_color)
	var cs := grid.size.x / 3.0
	for y in 3:
		for x in 3:
			var piece: int = PATTERN[y].unicode_at(x) - "A".unicode_at(0)
			var color: Color = colors[piece % colors.size()] if not colors.is_empty() else Color.WHITE
			look.draw_block(self, Rect2(grid.position + Vector2(x, y) * cs, Vector2.ONE * cs).grow(-1.5), color)
	var font := look.font()
	var font_size := look.label_font_size
	var label := "3/3"
	var text_size := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	var pill_size := text_size + Vector2(14, 4)
	var pill := Rect2(grid.get_center() - pill_size * 0.5, pill_size)
	draw_style_box(look.rounded_box(look.label_background_color, int(pill_size.y * 0.5)), pill)
	var baseline := Vector2(pill.position.x + 7, pill.get_center().y + font.get_ascent(font_size) * 0.5 - font.get_descent(font_size) * 0.5 + 1)
	draw_string(font, baseline, label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, look.label_text_color)
