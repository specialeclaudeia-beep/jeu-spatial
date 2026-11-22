extends Control
## Écran d'accueil (PROVISOIRE, réponse de Gwenaël Q1) : trois boutons.
##   - Atelier : ouvre l'atelier avec le dernier vaisseau ;
##   - Jouer : lance le jeu tout de suite avec le dernier vaisseau, posé au sol devant le hangar ;
##   - Charger un vaisseau : liste des plans de vaisseau (ceux du jeu, puis les tiens), ouvert dans l'atelier.
## « Jouer » passe d'abord par le CONTRÔLE AVANT LE VOL (atelier, étape 5 : scripts/atelier/controle_vol.gd) :
## ce qui casserait le jeu est refusé (avec « Ouvrir l'atelier ») ; un avertissement propose « Jouer quand même ».
## Rien de lourd ici : ni planète, ni lumière, ni son. Le fond étoilé est dessiné en 2D.
## Lancé avec « -- --mesure » (mesure de vitesse), on passe directement au jeu, en orbite, comme avant.

const Partie = preload("res://scripts/partie.gd")
const Style = preload("res://scripts/atelier/style.gd")
const Plan = preload("res://scripts/atelier/plan.gd")
const ControleVol = preload("res://scripts/atelier/controle_vol.gd")

var _etoiles := PackedVector3Array()   # x, y (0..1), éclat
var liste_plans: ItemList
var panneau_charger: PanelContainer
var chargement: Label
var _plans: Array = []
var texte_vaisseau: Label
var controle                           # dernier contrôle avant le vol (ControleVol)
var fenetre_controle: Control          # sa fenêtre, ouverte par « Jouer » (ou null)


func _ready() -> void:
	if "--mesure" in OS.get_cmdline_user_args():
		get_tree().change_scene_to_file.call_deferred(Partie.SCENE_JEU)
		return
	set_anchors_preset(Control.PRESET_FULL_RECT)
	theme = Style.theme()
	var rng := RandomNumberGenerator.new()
	rng.seed = 27
	for i in 420:
		_etoiles.append(Vector3(rng.randf(), rng.randf(), pow(rng.randf(), 3.0)))
	resized.connect(queue_redraw)
	_creer_interface()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.015, 0.02, 0.035))
	# une bande de Voie lactée en diagonale, puis les étoiles
	for e in _etoiles:
		var p := Vector2(e.x * size.x, e.y * size.y)
		var c := Color(0.75 + 0.25 * e.z, 0.8 + 0.2 * e.z, 1.0, 0.25 + 0.75 * e.z)
		draw_circle(p, 0.6 + 1.4 * e.z, c)
	var h := size.y
	draw_rect(Rect2(0, h * 0.82, size.x, h * 0.18), Color(0.04, 0.05, 0.07, 0.8))
	draw_line(Vector2(0, h * 0.82), Vector2(size.x, h * 0.82), Color(Style.ACCENT, 0.35), 1.0)


func _creer_interface() -> void:
	var centre := VBoxContainer.new()
	centre.set_anchors_preset(Control.PRESET_CENTER)
	centre.grow_horizontal = Control.GROW_DIRECTION_BOTH
	centre.grow_vertical = Control.GROW_DIRECTION_BOTH
	centre.custom_minimum_size = Vector2(420, 0)
	centre.add_theme_constant_override("separation", 14)
	add_child(centre)
	var titre := Style.label("JEU SPATIAL", 46, Color.WHITE)
	titre.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	centre.add_child(titre)
	var sous := Style.label("physique réelle · lumière vraie · atelier de vaisseaux", 15, Style.TEXTE_DOUX)
	sous.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	centre.add_child(sous)
	centre.add_child(_espace(22))
	var atelier := _gros_bouton("ATELIER", "Construire et analyser le vaisseau, dans le hangar")
	atelier.pressed.connect(ouvrir_atelier)
	centre.add_child(atelier)
	var jouer := Style.bouton_principal("▶  JOUER", 22)
	jouer.custom_minimum_size = Vector2(420, 64)
	jouer.tooltip_text = "Le vaisseau part posé au sol, devant le hangar (F3 dans le jeu : retour à l'atelier)"
	jouer.pressed.connect(jouer_maintenant)
	centre.add_child(jouer)
	var charger := _gros_bouton("CHARGER UN VAISSEAU", "Choisir un autre plan de vaisseau")
	charger.pressed.connect(montrer_plans)
	centre.add_child(charger)
	texte_vaisseau = Style.label("", 14, Style.TEXTE_DOUX)
	texte_vaisseau.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	centre.add_child(texte_vaisseau)
	_maj_texte_vaisseau()
	var quitter := Style.bouton("Quitter", 14)
	quitter.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	quitter.pressed.connect(func(): get_tree().quit())
	centre.add_child(quitter)
	# fenêtre « Charger un vaisseau »
	panneau_charger = PanelContainer.new()
	panneau_charger.set_anchors_preset(Control.PRESET_CENTER)
	panneau_charger.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panneau_charger.grow_vertical = Control.GROW_DIRECTION_BOTH
	panneau_charger.custom_minimum_size = Vector2(560, 380)
	panneau_charger.add_theme_stylebox_override("panel", Style.boite(Style.FOND_CLAIR, Style.ACCENT.darkened(0.4), 8, 16.0))
	panneau_charger.visible = false
	add_child(panneau_charger)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	panneau_charger.add_child(v)
	v.add_child(Style.label("CHARGER UN VAISSEAU", 13, Style.TEXTE_DOUX))
	liste_plans = ItemList.new()
	liste_plans.size_flags_vertical = Control.SIZE_EXPAND_FILL
	liste_plans.add_theme_font_size_override("font_size", 15)
	liste_plans.item_activated.connect(func(i): ouvrir_plan(i))
	v.add_child(liste_plans)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	h.alignment = BoxContainer.ALIGNMENT_END
	v.add_child(h)
	var annuler := Style.bouton("Annuler")
	annuler.pressed.connect(func(): panneau_charger.visible = false)
	h.add_child(annuler)
	var ouvrir := Style.bouton_principal("Ouvrir dans l'atelier", 15)
	ouvrir.pressed.connect(func():
		var s := liste_plans.get_selected_items()
		if s.size() > 0:
			ouvrir_plan(s[0]))
	h.add_child(ouvrir)
	# écran de chargement
	chargement = Style.label("Chargement…", 24, Color.WHITE)
	chargement.set_anchors_preset(Control.PRESET_FULL_RECT)
	chargement.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	chargement.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	chargement.add_theme_stylebox_override("normal", Style.boite(Color(0.015, 0.02, 0.035, 0.94), Color(0, 0, 0, 0), 0))
	chargement.visible = false
	add_child(chargement)


func _gros_bouton(texte: String, aide: String) -> Button:
	var b := Style.bouton(texte, 20)
	b.custom_minimum_size = Vector2(420, 56)
	b.tooltip_text = aide
	return b


static func _espace(h: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	return c


func _maj_texte_vaisseau() -> void:
	var chemin := Partie.plan_choisi()
	var nom := chemin.get_file().trim_suffix(".plan.json")
	for p in Partie.plans_disponibles():
		if p["chemin"] == chemin:
			nom = p["nom"]
	texte_vaisseau.text = "Vaisseau : %s" % nom


func montrer_plans() -> void:
	_plans = Partie.plans_disponibles()
	liste_plans.clear()
	var choisi := Partie.plan_choisi()
	for p in _plans:
		var i := liste_plans.add_item("%s%s" % [p["nom"], "   (tes vaisseaux)" if String(p["chemin"]).begins_with("user://") else ""])
		liste_plans.set_item_tooltip(i, String(p["description"]))
		if p["chemin"] == choisi:
			liste_plans.select(i)
	panneau_charger.visible = true


func ouvrir_plan(i: int) -> void:
	if i < 0 or i >= _plans.size():
		return
	Partie.choisir_plan(String(_plans[i]["chemin"]))
	ouvrir_atelier()


func ouvrir_atelier() -> void:
	fermer_fenetre_controle()
	_changer("Ouverture de l'atelier…", func(): Partie.aller_atelier(get_tree()))


## « Jouer » : le contrôle avant le vol, puis le jeu (forcer : malgré un avertissement).
func jouer_maintenant(forcer := false) -> bool:
	if chargement.visible:
		return false
	fermer_fenetre_controle()
	var chemin := Partie.plan_choisi()
	var plan = Plan.par_defaut()
	if chemin != Plan.PLAN_PAR_DEFAUT:
		plan = Plan.new()
		plan.charger(chemin)
	controle = ControleVol.new(plan)
	if controle.bloque() or (controle.avertit() and not forcer):
		var boutons := [["Ouvrir l'atelier", ouvrir_atelier, controle.bloque()], ["Revenir", fermer_fenetre_controle, false]]
		if not controle.bloque():
			boutons.append(["▶  Jouer quand même", func(): jouer_maintenant(true), true])
		fenetre_controle = controle.fenetre(boutons)
		add_child(fenetre_controle)
		return false
	_changer("Chargement du jeu…\nLe vaisseau part posé au sol, devant le hangar.\nDans le jeu, F3 ouvre l'atelier.",
		func(): Partie.lancer_jeu(get_tree(), Partie.DEPART_HANGAR))
	return true


func fermer_fenetre_controle() -> void:
	if fenetre_controle != null and is_instance_valid(fenetre_controle):
		fenetre_controle.queue_free()
	fenetre_controle = null


## Affiche « Chargement… » pendant deux images, puis change d'écran.
func _changer(texte: String, action: Callable) -> void:
	if chargement.visible:
		return
	chargement.text = texte
	chargement.visible = true
	await get_tree().process_frame
	await get_tree().process_frame
	action.call()
