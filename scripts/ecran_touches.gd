extends Control
## Écran de configuration des commandes (F2, ou Options sur la manette).
## Une ligne par action : une case pour le clavier, une case pour la manette.
## On clique sur une case (ou on la choisit avec la croix directionnelle et Croix),
## puis on appuie sur la touche, le bouton ou le stick voulu.
## Tout est sauvegardé tout de suite.

signal ferme

const Commandes = preload("res://scripts/commandes.gd")
const DELAI_ECOUTE := 0.3   # s : on ignore l'appui qui a servi à choisir la case

var commandes            # l'objet Commandes du jeu (donné par jeu.gd)
var boutons: Dictionary = {}     # boutons["nom/clavier"] = Button
var ecoute := {}                  # {"nom":…, "genre":…, "depuis": temps} pendant qu'on attend un appui
var info: Label
var test_manette: Label


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var fond := ColorRect.new()
	fond.color = Color(0.02, 0.03, 0.06, 0.92)
	fond.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(fond)

	var marge := MarginContainer.new()
	marge.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for cote in ["left", "right", "top", "bottom"]:
		marge.add_theme_constant_override("margin_" + cote, 24)
	add_child(marge)
	var colonne := VBoxContainer.new()
	colonne.add_theme_constant_override("separation", 8)
	marge.add_child(colonne)

	var titre := Label.new()
	titre.text = "Configuration des commandes"
	titre.add_theme_font_size_override("font_size", 26)
	colonne.add_child(titre)
	info = Label.new()
	info.autowrap_mode = TextServer.AUTOWRAP_WORD
	info.add_theme_color_override("font_color", Color(0.8, 0.85, 1.0))
	colonne.add_child(info)
	test_manette = Label.new()
	test_manette.add_theme_color_override("font_color", Color(0.6, 1.0, 0.7))
	colonne.add_child(test_manette)

	var defilement := ScrollContainer.new()
	defilement.size_flags_vertical = Control.SIZE_EXPAND_FILL
	defilement.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	defilement.follow_focus = true   # avec la manette, la liste défile toute seule
	colonne.add_child(defilement)
	var grille := GridContainer.new()
	grille.columns = 3
	grille.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grille.add_theme_constant_override("h_separation", 12)
	grille.add_theme_constant_override("v_separation", 4)
	defilement.add_child(grille)

	for entete in ["Action", "Clavier", "Manette"]:
		var l := Label.new()
		l.text = entete
		l.add_theme_color_override("font_color", Color(1.0, 0.85, 0.5))
		grille.add_child(l)
	for a in Commandes.ACTIONS:
		var nom: String = a[0]
		var l := Label.new()
		l.text = a[1] + ("   (analogique)" if nom in Commandes.ANALOGIQUES else "")
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grille.add_child(l)
		for genre in ["clavier", "manette"]:
			var b := Button.new()
			b.custom_minimum_size = Vector2(260, 0)
			b.pressed.connect(_choisir.bind(nom, genre))
			grille.add_child(b)
			boutons[nom + "/" + genre] = b

	var bas := HBoxContainer.new()
	bas.add_theme_constant_override("separation", 16)
	colonne.add_child(bas)
	var defaut := Button.new()
	defaut.text = "Remettre la disposition par défaut"
	defaut.pressed.connect(_par_defaut)
	bas.add_child(defaut)
	var fermer := Button.new()
	fermer.text = "Fermer (Échap)"
	fermer.pressed.connect(_fermer)
	bas.add_child(fermer)

	_rafraichir()
	_message_normal()
	boutons[Commandes.ACTIONS[0][0] + "/clavier"].grab_focus()


func _message_normal() -> void:
	info.text = ("Clique sur une case (ou choisis-la avec la croix directionnelle puis Croix), "
		+ "puis appuie sur la touche, le bouton ou le stick voulu. Les réglages sont sauvegardés tout de suite.")


func _rafraichir() -> void:
	for a in Commandes.ACTIONS:
		for genre in ["clavier", "manette"]:
			var b: Button = boutons[a[0] + "/" + genre]
			b.text = Commandes.nom_lisible(commandes.liaisons[a[0]][genre])


func _choisir(nom: String, genre: String) -> void:
	ecoute = {"nom": nom, "genre": genre, "depuis": Time.get_ticks_msec()}
	boutons[nom + "/" + genre].text = "… appuie"
	var quoi := "une touche du clavier" if genre == "clavier" else "un bouton, une gâchette ou un stick de la manette"
	info.text = "« %s » : appuie sur %s.   Échap = annuler   Retour arrière = effacer." % [Commandes.titre(nom), quoi]


func _input(e: InputEvent) -> void:
	if ecoute.is_empty():
		# fermer l'écran avec Échap ou la touche « Configurer les commandes » (F2 / Options)
		if e.is_action_pressed("ecran_touches") or (e is InputEventKey and e.is_pressed() and (e as InputEventKey).keycode == KEY_ESCAPE):
			get_viewport().set_input_as_handled()
			_fermer()
		return
	# on attend un appui pour la case choisie
	get_viewport().set_input_as_handled()
	if Time.get_ticks_msec() - int(ecoute["depuis"]) < DELAI_ECOUTE * 1000.0:
		return
	if e is InputEventKey:
		var k := e as InputEventKey
		if not k.is_pressed() or k.is_echo():
			return
		if k.keycode == KEY_ESCAPE:
			_fin_ecoute("Annulé.")
			return
		if k.keycode == KEY_BACKSPACE or k.keycode == KEY_DELETE:
			commandes.assigner(ecoute["nom"], ecoute["genre"], "")
			_fin_ecoute("Case effacée.")
			return
	if ecoute["genre"] == "clavier" and not (e is InputEventKey):
		return
	if ecoute["genre"] == "manette" and not (e is InputEventJoypadButton or e is InputEventJoypadMotion):
		return
	if e is InputEventJoypadButton and not e.is_pressed():
		return
	var code := Commandes.code_depuis_evenement(e)
	if code == "":
		return
	var perdu: String = commandes.assigner(ecoute["nom"], ecoute["genre"], code)
	var texte := "« %s » : %s." % [Commandes.titre(ecoute["nom"]), Commandes.nom_lisible(code)]
	if perdu != "":
		texte += "  (retiré de « %s », qui l'utilisait)" % perdu
	_fin_ecoute(texte)


func _fin_ecoute(texte: String) -> void:
	var b: Button = boutons[ecoute["nom"] + "/" + ecoute["genre"]]
	ecoute = {}
	commandes.appliquer()
	commandes.sauvegarder()
	_rafraichir()
	info.text = texte + "   Choisis une autre case, ou Échap pour revenir au jeu."
	b.grab_focus()


func _par_defaut() -> void:
	commandes.remettre_par_defaut()
	commandes.appliquer()
	commandes.sauvegarder()
	_rafraichir()
	info.text = "Disposition par défaut remise et sauvegardée."


func _fermer() -> void:
	ferme.emit()
	queue_free()


## Petit témoin en direct, pour vérifier que les sticks sont bien analogiques.
func _process(_delta: float) -> void:
	var manettes := Input.get_connected_joypads()
	var nom := "aucune manette détectée" if manettes.is_empty() else Input.get_joy_name(manettes[0])
	test_manette.text = "Manette : %s      Test en direct →  tangage %+4d %%   lacet %+4d %%   roulis %+4d %%   poussée + %3d %%   − %3d %%" % [
		nom,
		int(round(Input.get_axis("tangage_bas", "tangage_haut") * 100.0)),
		int(round(Input.get_axis("lacet_droite", "lacet_gauche") * 100.0)),
		int(round(Input.get_axis("roulis_droite", "roulis_gauche") * 100.0)),
		int(round(Input.get_action_strength("gaz_plus") * 100.0)),
		int(round(Input.get_action_strength("gaz_moins") * 100.0))]
