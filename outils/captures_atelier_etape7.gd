extends SceneTree
## Captures d'écran de l'étape 7 de l'atelier (les pièces mobiles), pour montrer ce qui a été fait sans lancer
## le jeu à la main. Parcours (symétrie allumée) : le catalogue « Pièces mobiles » et une aile repliable qui suit
## la souris sur le flanc du fuselage (sa jumelle de l'autre côté) → les deux ailes posées, repliées, et leur
## fiche (boutons « Essayer ») → une charnière sur le dos et une boîte posée sur son battant → le menu
## « Mouvements » → les ailes qui s'ouvrent (à mi-course, puis ouvertes : la boîte suit le battant) → la page
## « Pièces mobiles » (masses emmenées, centre de gravité qui bouge) → le contrôle avant le vol → le jeu, vu de
## dehors, posé ailes repliées, puis ailes ouvertes.
## Ligne de commande (Linux, sans écran : xvfb-run) :
##   xvfb-run -s "-screen 0 1600x900x24" Godot --rendering-driver opengl3 --path . -s outils/captures_atelier_etape7.gd -- <dossier>
## Les images sont écrites dans <dossier> (par défaut user://captures_atelier_etape7/). Les vaisseaux enregistrés
## pendant le parcours vont dans user://captures_vaisseaux/ (pas avec ceux du joueur).

const Partie = preload("res://scripts/partie.gd")
const Plan = preload("res://scripts/atelier/plan.gd")
const Pieces = preload("res://scripts/atelier/pieces_toutes_faites.gd")

var dossier := "user://captures_atelier_etape7/"


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		dossier = args[0].trim_suffix("/") + "/"
	DirAccess.make_dir_recursive_absolute(dossier)
	DisplayServer.window_set_size(Vector2i(1600, 900))
	root.size = Vector2i(1600, 900)
	_parcours.call_deferred()


func _attendre(images: int) -> void:
	for i in images:
		await process_frame


func _physique(n := 6) -> void:
	for i in n:
		await physics_frame


func _capture(nom: String) -> void:
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	img.save_png(dossier + nom + ".png")
	print("capture : ", dossier + nom + ".png")


func _vue(at, lacet: float, tangage: float, boite = null, recul := 1.0) -> void:
	# une boîte donnée l'est dans le repère du vaisseau
	at.camera.cadrer(at.boite_visible() if boite == null else at.corps.global_transform * (boite as AABB))
	at.camera.lacet = deg_to_rad(lacet)
	at.camera.tangage = deg_to_rad(tangage)
	at.camera.distance *= recul
	at.camera.appliquer()


func _propre(at) -> void:
	at.bulle.visible = false
	at._souris = Vector2(-1, -1)
	Input.warp_mouse(Vector2(1598, 898))


## La pièce à poser suit un rayon (repère du vaisseau) : d'où il part, dans quelle direction ; la souris est
## mise là où le rayon touche, comme si elle y était.
func _viser(at, p: Vector3, dir: Vector3) -> void:
	var xf: Transform3D = at.corps.global_transform
	var d: Vector3 = (xf.basis * dir).normalized()
	at.calculer_pose_rayon(xf * p - d * 25.0, d)
	print("  pose %s : touche %s, sur « %s » (%s)" % [p, at.pose.get("touche", false), at.pose.get("fixe_a", ""), at.pose.get("articulation", "")])


func _proposition(at, nom: String) -> void:
	var it: TreeItem = at.arbre.get_root()
	while it != null:
		var m = it.get_metadata(0)
		if m is Dictionary and String(m["genre"]) == "modele" and Pieces.PROPOSITIONS[int(m["id"])][1] == nom:
			it.select(0)
			at.arbre.scroll_to_item(it)
			return
		it = it.get_next_in_tree()


func _clic_tuile(at, k: int) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	(at.tableau.get_child(k) as Control).gui_input.emit(ev)


func _ajout(at, modele: String) -> String:
	var r := ""
	for id in at.analyse.ajouts:
		if String(at.analyse.ajouts[id]["modele"]) == modele:
			r = id
	return r


func _apres_pose(at) -> void:
	_propre(at)
	await _attendre(4)
	await _physique(8)
	await _attendre(4)


func _parcours() -> void:
	Input.warp_mouse(Vector2(1598, 898))
	Engine.set_meta("partie", {"plan": Plan.PLAN_PAR_DEFAUT, "depart": "", "plan_lu": true})
	change_scene_to_file(Partie.SCENE_ATELIER)
	await _attendre(20)
	var at = current_scene
	at.dossier_vaisseaux = "user://captures_vaisseaux/"
	at.case_symetrie.button_pressed = true
	at.case_neutre.button_pressed = false
	at.case_poussees.button_pressed = false
	at.case_cg.button_pressed = false
	var avant := AABB(Vector3(-4.0, -1.5, -5.5), Vector3(8.0, 4.0, 7.0))   # l'avant du vaisseau
	# 1. le catalogue « Pièces mobiles » : une aile repliable qui suit la souris sur le flanc droit
	_proposition(at, "Aile repliable (2,5 × 1,4 m)")
	await _attendre(4)
	_vue(at, -130.0, -18.0, avant, 1.2)
	await _attendre(6)
	_viser(at, Vector3(4.0, 0.0, -2.6), Vector3.LEFT)
	await _attendre(6)
	await _capture("01_catalogue_pieces_mobiles_aile_repliable")
	at.valider_pose()
	await _apres_pose(at)
	# 2. les deux ailes posées (repliées : pose du hangar) et leur fiche, avec « Essayer »
	var aile := _ajout(at, "aile_repliable")
	if aile != "":
		at.choisir("ajout", aile)
	await _attendre(6)
	_propre(at)
	await _capture("02_ailes_repliables_posees_fiche")
	# 3. une charnière sur le dos, derrière le cockpit, puis une boîte posée sur son battant
	at.deselectionner()
	at.commencer_pose("charniere", {})
	_viser(at, Vector3(0.0, 6.0, 1.3), Vector3.DOWN)
	at.valider_pose()
	await _apres_pose(at)
	var ch := _ajout(at, "charniere")
	var battant: MeshInstance3D = null
	if ch != "":
		for m in at.dessin.maillages_ajouts[ch]:
			if (m as Node).has_meta("articulation"):
				battant = m
	if battant != null:
		var c: Vector3 = at.corps.global_transform.affine_inverse() * (battant.global_transform * battant.get_aabb()).get_center()
		at.commencer_pose("boite", {"masse_kg": 80.0, "largeur_m": 0.4, "hauteur_m": 0.25, "longueur_m": 0.3})
		_viser(at, c + Vector3(0.0, 4.0, 0.0), Vector3.DOWN)
		at.valider_pose()
		await _apres_pose(at)
	var boite := _ajout(at, "boite")
	if boite != "":
		at.choisir("ajout", boite)
	_vue(at, 130.0, -30.0, AABB(Vector3(-2.5, -0.5, -1.5), Vector3(5.0, 3.0, 4.5)), 1.3)
	await _attendre(6)
	_propre(at)
	await _capture("03_charniere_et_boite_sur_son_battant")
	# 4. le menu « Mouvements »
	at.deselectionner()
	_vue(at, 45.0, -16.0, null, 1.05)
	await _attendre(4)
	at._ouvrir_menu_mouvements(at.bouton_mouvements)
	await _attendre(6)
	_propre(at)
	await _capture("04_menu_mouvements")
	for n in at.ui.get_children():
		if n is PopupPanel:
			(n as Window).hide()
	await _attendre(4)
	# 5. ouvrir les ailes : à mi-course, puis ouvertes (la boîte suit le battant de la charnière)
	at.essayer_mouvement("ailes", 1.0)
	var t0 := Time.get_ticks_msec()
	while at.vaisseau_pose.ailes < 0.5 and Time.get_ticks_msec() - t0 < 20000:
		await process_frame
	_propre(at)
	await _capture("05_ailes_a_mi_course")
	t0 = Time.get_ticks_msec()
	while not at._essai.is_empty() and Time.get_ticks_msec() - t0 < 20000:
		await process_frame
	await _attendre(8)
	_propre(at)
	await _capture("06_ailes_ouvertes_avis_sol")
	_vue(at, 130.0, -30.0, AABB(Vector3(-2.5, -0.5, -1.5), Vector3(5.0, 3.0, 4.5)), 1.3)
	await _attendre(6)
	_propre(at)
	await _capture("07_battant_leve_la_boite_suit")
	# 6. la page « Pièces mobiles » (tuile du centre de gravité), puis le contrôle avant le vol
	at.remettre_pose_hangar()
	await _attendre(6)
	_vue(at, 145.0, -22.0, null, 1.0)
	_clic_tuile(at, 6)
	await _attendre(6)
	_propre(at)
	await _capture("08_page_pieces_mobiles")
	_clic_tuile(at, 8)
	await _attendre(6)
	_propre(at)
	await _capture("09_controle_avant_le_vol")
	print("contrôle : %s" % [at.controle.tuile()])
	for el in at.controle.elements:
		if String(el["niveau"]) != "ok" or String(el["categorie"]) == "Pièces mobiles":
			print("  %s · %s · %s : %s" % [el["categorie"], el["niveau"], el["titre"], el["texte"]])
	# 7. le jeu, vu de dehors : ailes ouvertes (départ), puis repliées
	at.deselectionner()
	at.lancer_jeu(true)
	await _attendre(4)
	t0 = Time.get_ticks_msec()
	while not (current_scene != null and current_scene.has_method("_poser_devant_hangar")) and Time.get_ticks_msec() - t0 < 60000:
		await process_frame
	var jeu = current_scene
	await _attendre(90)
	jeu.aide.visible = false
	jeu.vue_interieure = false
	jeu._appliquer_vue()
	jeu.hud.visible = false
	Input.action_press("regard_gauche", 0.01)
	Input.action_press("zoom")
	jeu.tete = Vector2(0.3, deg_to_rad(-140.0))
	await _attendre(30)
	jeu.tete = Vector2(0.3, deg_to_rad(-140.0))
	await _capture("10_jeu_pose_ailes_repliees")
	jeu.vaisseau.ouvrir_ailes(true)
	t0 = Time.get_ticks_msec()
	while jeu.vaisseau.ailes < 1.0 and Time.get_ticks_msec() - t0 < 30000:
		jeu.tete = Vector2(0.3, deg_to_rad(-140.0))
		await process_frame
	await _attendre(20)
	jeu.tete = Vector2(0.3, deg_to_rad(-140.0))
	print("jeu : ailes %.2f, au sol %s" % [jeu.vaisseau.ailes, jeu.vaisseau.au_sol])
	await _capture("11_jeu_ailes_ouvertes")
	Input.action_release("zoom")
	Input.action_release("regard_gauche")
	quit()
