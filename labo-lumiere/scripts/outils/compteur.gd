extends CanvasLayer
## Compteur affiché en haut à gauche de chaque scène du labo : images par seconde,
## millisecondes de chacun des 4 temps de la boucle, nombre de rayons.
## F3 le cache ou le montre.

const ChronoBoucle = preload("res://scripts/lumiere/chrono_boucle.gd")

## Le chronomètre lu par le compteur. Chaque scène y range ses mesures.
var chrono = ChronoBoucle.new()

var _fond: PanelContainer
var _texte: Label
var _attente := 0.0
const RAFRAICHIR_S := 0.25   # le texte change 4 fois par seconde, pour rester lisible


func _ready() -> void:
	layer = 100
	_fond = PanelContainer.new()
	_fond.position = Vector2(10, 10)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0.6)
	style.set_corner_radius_all(4)
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 6
	style.content_margin_bottom = 6
	_fond.add_theme_stylebox_override("panel", style)
	add_child(_fond)
	_texte = Label.new()
	_texte.add_theme_font_size_override("font_size", 15)
	_fond.add_child(_texte)
	# Demande à Godot de mesurer son propre temps de dessin (processeur et carte graphique).
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)
	_mettre_a_jour()


func _process(delta: float) -> void:
	var vp := get_viewport().get_viewport_rid()
	var dessin := RenderingServer.viewport_get_measured_render_time_cpu(vp) \
		+ RenderingServer.viewport_get_measured_render_time_gpu(vp)
	# Tant que le système ne dessine rien lui-même, le temps « dessiner » = celui de Godot.
	chrono.enregistrer(ChronoBoucle.DESSINER, dessin)
	_attente -= delta
	if _attente <= 0.0:
		_attente = RAFRAICHIR_S
		_mettre_a_jour()


func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventKey and e.is_pressed() and not e.is_echo() and (e as InputEventKey).keycode == KEY_F3:
		basculer()
		get_viewport().set_input_as_handled()


## Cache le compteur s'il est visible, le montre sinon.
func basculer() -> void:
	visible = not visible


## Le texte affiché (aussi utilisé par les tests).
func texte() -> String:
	var lignes := PackedStringArray()
	lignes.append("Images/s : %d    (F3 : cacher)" % Engine.get_frames_per_second())
	var temps := PackedStringArray()
	for i in 4:
		var marque := " !" if chrono.depasse(i) else ""
		temps.append("%s %.2f%s" % [ChronoBoucle.NOMS[i], chrono.moyennes_ms[i], marque])
	lignes.append("Temps (ms) : " + "  ·  ".join(temps))
	lignes.append("Total : %.2f ms sur 16,7    Rayons : %d" % [chrono.total_ms(), chrono.nb_rayons])
	return "\n".join(lignes)


func _mettre_a_jour() -> void:
	if _texte:
		_texte.text = texte()
