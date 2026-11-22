extends RefCounted
## Style (provisoire) des menus de l'atelier et de l'écran d'accueil : sombre et technique, comme les
## écrans du cockpit, avec des listes qui se déplient comme dans Notion. Tout le visuel peut changer plus
## tard : il est rassemblé ici.

const FOND := Color(0.065, 0.075, 0.098, 0.94)
const FOND_CLAIR := Color(0.11, 0.125, 0.16, 0.96)
const BORD := Color(0.2, 0.24, 0.31)
const TEXTE := Color(0.88, 0.9, 0.94)
const TEXTE_DOUX := Color(0.58, 0.63, 0.71)
const ACCENT := Color(0.36, 0.76, 1.0)
const SELECTION := Color(1.0, 0.62, 0.22)
const VERT := Color(0.19, 0.72, 0.42)
const ROUGE := Color(1.0, 0.42, 0.38)


static func boite(fond: Color, bord := BORD, rayon := 6, marge := 8.0, epaisseur := 1) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = fond
	s.border_color = bord
	s.set_border_width_all(epaisseur)
	s.set_corner_radius_all(rayon)
	s.content_margin_left = marge
	s.content_margin_right = marge
	s.content_margin_top = marge * 0.6
	s.content_margin_bottom = marge * 0.6
	s.anti_aliasing = true
	return s


static func theme() -> Theme:
	var t := Theme.new()
	t.default_font_size = 15
	t.set_color("font_color", "Label", TEXTE)
	t.set_stylebox("panel", "PanelContainer", boite(FOND))
	t.set_stylebox("panel", "Panel", boite(FOND))
	# boutons
	t.set_stylebox("normal", "Button", boite(Color(0.13, 0.15, 0.19), BORD, 5, 10.0))
	t.set_stylebox("hover", "Button", boite(Color(0.18, 0.21, 0.27), ACCENT.darkened(0.3), 5, 10.0))
	t.set_stylebox("pressed", "Button", boite(Color(0.1, 0.24, 0.34), ACCENT, 5, 10.0))
	t.set_stylebox("hover_pressed", "Button", boite(Color(0.12, 0.28, 0.38), ACCENT, 5, 10.0))
	t.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	t.set_stylebox("disabled", "Button", boite(Color(0.1, 0.11, 0.13), BORD, 5, 10.0))
	t.set_color("font_color", "Button", TEXTE)
	t.set_color("font_hover_color", "Button", Color.WHITE)
	t.set_color("font_pressed_color", "Button", Color.WHITE)
	t.set_color("font_hover_pressed_color", "Button", Color.WHITE)
	# champ de recherche
	t.set_stylebox("normal", "LineEdit", boite(Color(0.04, 0.05, 0.065), BORD, 5, 9.0))
	t.set_stylebox("focus", "LineEdit", boite(Color(0.04, 0.05, 0.065), ACCENT, 5, 9.0))
	t.set_color("font_color", "LineEdit", TEXTE)
	t.set_color("font_placeholder_color", "LineEdit", TEXTE_DOUX)
	# liste des pièces (façon Notion : pas de cadre, lignes aérées, survol discret)
	t.set_stylebox("panel", "Tree", StyleBoxEmpty.new())
	t.set_stylebox("focus", "Tree", StyleBoxEmpty.new())
	t.set_stylebox("selected", "Tree", boite(Color(0.16, 0.3, 0.42), Color(0, 0, 0, 0), 4, 2.0, 0))
	t.set_stylebox("selected_focus", "Tree", boite(Color(0.18, 0.34, 0.48), Color(0, 0, 0, 0), 4, 2.0, 0))
	t.set_stylebox("hovered", "Tree", boite(Color(1, 1, 1, 0.05), Color(0, 0, 0, 0), 4, 2.0, 0))
	t.set_stylebox("cursor", "Tree", StyleBoxEmpty.new())
	t.set_stylebox("cursor_unfocused", "Tree", StyleBoxEmpty.new())
	t.set_color("font_color", "Tree", TEXTE)
	t.set_color("font_selected_color", "Tree", Color.WHITE)
	t.set_color("guide_color", "Tree", Color(0, 0, 0, 0))
	t.set_color("relationship_line_color", "Tree", Color(0, 0, 0, 0))
	t.set_constant("v_separation", "Tree", 5)
	t.set_constant("item_margin", "Tree", 14)
	t.set_constant("draw_guides", "Tree", 0)
	t.set_constant("draw_relationship_lines", "Tree", 0)
	t.set_font_size("font_size", "Tree", 14)
	# curseur (vitesse de la caméra)
	t.set_stylebox("slider", "HSlider", boite(Color(0.05, 0.06, 0.08), BORD, 3, 2.0))
	t.set_stylebox("grabber_area", "HSlider", boite(ACCENT.darkened(0.35), Color(0, 0, 0, 0), 3, 2.0, 0))
	t.set_stylebox("grabber_area_highlight", "HSlider", boite(ACCENT.darkened(0.2), Color(0, 0, 0, 0), 3, 2.0, 0))
	t.set_stylebox("panel", "PopupPanel", boite(FOND_CLAIR, BORD, 6, 12.0))
	t.set_stylebox("panel", "PopupMenu", boite(FOND_CLAIR, BORD, 6, 8.0))
	t.set_color("font_color", "PopupMenu", TEXTE)
	t.set_color("font_color", "CheckBox", TEXTE)
	t.set_color("font_hover_color", "CheckBox", Color.WHITE)
	t.set_color("font_pressed_color", "CheckBox", TEXTE)
	t.set_color("font_hover_pressed_color", "CheckBox", Color.WHITE)
	t.set_stylebox("normal", "CheckBox", boite(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 4, 6.0, 0))
	t.set_stylebox("hover", "CheckBox", boite(Color(1, 1, 1, 0.06), Color(0, 0, 0, 0), 4, 6.0, 0))
	t.set_stylebox("pressed", "CheckBox", boite(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 4, 6.0, 0))
	t.set_stylebox("hover_pressed", "CheckBox", boite(Color(1, 1, 1, 0.06), Color(0, 0, 0, 0), 4, 6.0, 0))
	t.set_stylebox("focus", "CheckBox", StyleBoxEmpty.new())
	t.set_stylebox("panel", "ItemList", boite(Color(0.04, 0.05, 0.065), BORD, 5, 6.0))
	t.set_color("font_color", "ItemList", TEXTE)
	t.set_stylebox("selected", "ItemList", boite(Color(0.16, 0.3, 0.42), Color(0, 0, 0, 0), 4, 4.0, 0))
	t.set_stylebox("selected_focus", "ItemList", boite(Color(0.18, 0.34, 0.48), Color(0, 0, 0, 0), 4, 4.0, 0))
	t.set_stylebox("focus", "ItemList", StyleBoxEmpty.new())
	t.set_stylebox("normal", "TooltipPanel", boite(FOND_CLAIR))
	t.set_stylebox("panel", "TooltipPanel", boite(FOND_CLAIR))
	t.set_color("font_color", "TooltipLabel", TEXTE)
	return t


static func label(texte: String, taille := 15, couleur := TEXTE) -> Label:
	var l := Label.new()
	l.text = texte
	l.add_theme_font_size_override("font_size", taille)
	l.add_theme_color_override("font_color", couleur)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


static func bouton(texte: String, taille := 15) -> Button:
	var b := Button.new()
	b.text = texte
	b.add_theme_font_size_override("font_size", taille)
	b.focus_mode = Control.FOCUS_NONE
	return b


## Gros bouton vert (« Lancer », « Jouer »).
static func bouton_principal(texte: String, taille := 18) -> Button:
	var b := bouton(texte, taille)
	b.add_theme_stylebox_override("normal", boite(VERT.darkened(0.25), VERT, 6, 18.0))
	b.add_theme_stylebox_override("hover", boite(VERT.darkened(0.05), VERT.lightened(0.3), 6, 18.0))
	b.add_theme_stylebox_override("pressed", boite(VERT.darkened(0.4), VERT, 6, 18.0))
	return b
