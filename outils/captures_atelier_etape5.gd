extends SceneTree
## Captures d'écran de l'étape 5 de l'atelier (le jeu dessine le vaisseau construit, contrôle avant le vol),
## pour montrer ce qui a été fait sans lancer le jeu à la main. Parcours : la tuile AVANT LE VOL (« prêt »)
## et sa page → deux moteurs, une vitre et une boîte devant la verrière posés → la page dit l'avertissement →
## « Lancer » ouvre la fenêtre du contrôle → une boîte dans le vide : « Lancer » refusé → la vitre dans
## l'atelier → « Lancer quand même » : le jeu dessine tout (pièces posées fusionnées, vraie vitre), vue
## cockpit et vues extérieures → l'accueil : « Jouer » passe aussi par le contrôle.
## Ligne de commande (Linux, sans écran : xvfb-run) :
##   xvfb-run -s "-screen 0 1600x900x24" Godot --rendering-driver opengl3 --path . -s outils/captures_atelier_etape5.gd -- <dossier>
## Les images sont écrites dans <dossier> (par défaut user://captures_atelier_etape5/). Les vaisseaux enregistrés
## pendant le parcours vont dans user://captures_vaisseaux/ (pas avec ceux du joueur).

const Partie = preload("res://scripts/partie.gd")
const Plan = preload("res://scripts/atelier/plan.gd")

var dossier := "user://captures_atelier_etape5/"


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


## Point de l'écran qui montre le centre d'une pièce du chasseur.
func _ecran(at, id: String, decalage := Vector3.ZERO) -> Vector2:
	var mi: MeshInstance3D = at.maillages[id][0]
	var c: Vector3 = (mi.global_transform * mi.get_aabb()).get_center() + decalage
	return at.camera.unproject_position(c)


func _viser(at, pt: Vector2) -> void:
	Input.warp_mouse(pt)
	at.calculer_pose(pt)


## Pose la pièce en train d'être posée en la faisant tomber d'en haut sur le point (x, z) du vaisseau.
func _poser_d_en_haut(at, x: float, z: float) -> void:
	var xf: Transform3D = at.corps.global_transform
	at.calculer_pose_rayon(xf * Vector3(x, 6.0, z), -xf.basis.y.normalized())
	at.valider_pose()


func _clic_tuile(at, k: int) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	(at.tableau.get_child(k) as Control).gui_input.emit(ev)


func _vue(at, lacet: float, tangage: float, boite = null) -> void:
	at.camera.cadrer(at.boite_visible() if boite == null else boite)
	at.camera.lacet = deg_to_rad(lacet)
	at.camera.tangage = deg_to_rad(tangage)
	at.camera.appliquer()


func _propre(at) -> void:
	at.bulle.visible = false
	Input.warp_mouse(Vector2(1598, 898))


func _dernier_ajout(at, modele: String) -> String:
	var id := ""
	for e in at.edition.ajouts():
		if e["modele"] == modele:
			id = String(e["id"])
	return id


func _parcours() -> void:
	Input.warp_mouse(Vector2(1598, 898))
	Engine.set_meta("partie", {"plan": Plan.PLAN_PAR_DEFAUT, "depart": "", "plan_lu": true})
	change_scene_to_file(Partie.SCENE_ATELIER)
	await _attendre(20)
	var at = current_scene
	at.dossier_vaisseaux = "user://captures_vaisseaux/"
	at.case_symetrie.button_pressed = false
	at.case_neutre.button_pressed = false
	at.case_poussees.button_pressed = false
	at.case_cg.button_pressed = true
	_vue(at, 145.0, -22.0)
	await _attendre(10)
	# 1. le chasseur de départ : la 9e tuile dit « prêt » ; un clic ouvre la page du contrôle
	_clic_tuile(at, 8)
	await _attendre(6)
	_propre(at)
	await _capture("01_tuile_avant_le_vol_pret")
	# 2. deux moteurs sous les ailes basses (symétrie), une vitre sur le dos, une boîte sur le nez
	at.case_symetrie.button_pressed = true
	at.commencer_pose("moteur_ionique", {"poussee_kn": 150.0})
	_viser(at, _ecran(at, "Aile_bas_droit"))
	at.valider_pose()
	await _attendre(4)
	await _physique()
	at.case_symetrie.button_pressed = false
	at.commencer_pose("plaque", {"matiere": "verre_aluminosilicate", "longueur_m": 1.4, "largeur_m": 0.9, "epaisseur_m": 0.03})
	_poser_d_en_haut(at, 0.0, 2.6)
	await _attendre(4)
	await _physique()
	at.commencer_pose("boite", {"hauteur_m": 0.6, "largeur_m": 0.6, "longueur_m": 0.7})
	_poser_d_en_haut(at, 0.0, -2.4)
	await _attendre(4)
	await _physique(8)
	at.deselectionner()
	_clic_tuile(at, 8)
	_vue(at, 150.0, -18.0)
	await _attendre(8)
	_propre(at)
	await _capture("02_page_controle_boite_devant_la_verriere")
	# 3. « Lancer » : la fenêtre du contrôle, avec « Lancer quand même »
	await at.lancer_jeu()
	await _attendre(6)
	_propre(at)
	await _capture("03_lancer_fenetre_avertissement")
	at.fermer_fenetre_controle()
	# 4. une boîte posée dans le vide : « Lancer » refusé (pas de « Lancer quand même »)
	at.commencer_pose("boite", {})
	at.calculer_pose_rayon(at.corps.global_transform * Vector3(9.0, 6.0, 0.0) - Vector3(0, 0, 40.0), Vector3(0, 0, 1))
	at.valider_pose()
	await _attendre(4)
	await _physique(8)
	await at.lancer_jeu()
	await _attendre(6)
	_propre(at)
	await _capture("04_lancer_refuse_piece_qui_flotte")
	at.fermer_fenetre_controle()
	var flotte := ""
	for id in at.flottantes:
		if at.edition.est_ajout(String(id)):
			flotte = String(id)
	if flotte != "":
		at.choisir("ajout", flotte)
		at.supprimer_selection()
	await _attendre(4)
	await _physique(8)
	# 5. la vitre dans l'atelier (vue de près)
	var vitre := _dernier_ajout(at, "plaque")
	at.choisir("ajout", vitre)
	at.cadrer_selection()
	at.camera.lacet = deg_to_rad(160.0)
	at.camera.tangage = deg_to_rad(-28.0)
	at.camera.distance *= 2.2
	at.camera.appliquer()
	await _attendre(8)
	_propre(at)
	await _capture("05_vitre_dans_l_atelier")
	at.deselectionner()
	print("atelier : %d pièces posées, %d flottent ; contrôle : %s" % [at.edition.ajouts().size(), at.nb_flottantes, at.controle.tuile()])
	# 6. « Lancer quand même » : le jeu, posé devant le hangar
	at.lancer_jeu(true)
	await _attendre(4)
	var t0 := Time.get_ticks_msec()
	while not (current_scene != null and current_scene.has_method("_poser_devant_hangar")) and Time.get_ticks_msec() - t0 < 60000:
		await process_frame
	var jeu = current_scene
	await _attendre(90)
	print("jeu : %d maillages fusionnés, %d pièces posées dessinées, %d vitres" % [jeu.dessin.fusions.size(), jeu.dessin.ajouts.size(),
		jeu.dessin.maillages_ajouts.values().reduce(func(n, l): return n + (l as Array).filter(func(m): return bool((m as Node).get_meta("vitre", false))).size(), 0)])
	jeu.aide.visible = false
	await _attendre(2)
	await _capture("06_jeu_cockpit_boite_sur_le_nez")
	jeu.vue_interieure = false
	jeu._appliquer_vue()
	jeu.hud.visible = false
	Input.action_press("regard_gauche", 0.01)
	Input.action_press("zoom")   # la caméra extérieure est à 24 m : le zoom (champ de 25°) la rapproche 3 fois
	for cible in [[0.15, 150.0, "07_jeu_exterieur_avant"], [0.5, 25.0, "08_jeu_exterieur_dessus_vitre"], [0.05, -95.0, "09_jeu_exterieur_cote_moteurs"]]:
		jeu.tete = Vector2(cible[0], deg_to_rad(cible[1]))
		await _attendre(30)
		jeu.tete = Vector2(cible[0], deg_to_rad(cible[1]))
		await _capture(cible[2])
	Input.action_release("zoom")
	Input.action_release("regard_gauche")
	# 7. l'accueil : « Jouer » avec ce vaisseau passe aussi par le contrôle
	change_scene_to_file(Partie.SCENE_ACCUEIL)
	await _attendre(20)
	current_scene.jouer_maintenant()
	await _attendre(6)
	await _capture("10_accueil_jouer_fenetre")
	quit()
