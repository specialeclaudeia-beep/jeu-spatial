extends SceneTree
## Captures d'écran de l'étape 4 de l'atelier (analyse ingénieur, salle à part), pour montrer ce qui a été
## fait sans lancer le jeu. Parcours : le tableau ingénieur (8 tuiles) → plusieurs pièces choisies ensemble
## (Ctrl + clic) → la page des masses → la page des poussées (flèche du couple) → un moteur d'un seul côté
## (couple en rouge) → la page de symétrie → une aile et son moteur seuls dans la salle à part → une pièce posée dans la
## salle → remise en place.
## Ligne de commande (Linux, sans écran : xvfb-run) :
##   xvfb-run -s "-screen 0 1600x900x24" Godot --rendering-driver opengl3 --path . -s outils/captures_atelier_etape4.gd -- <dossier>
## Les images sont écrites dans <dossier> (par défaut user://captures_atelier_etape4/). Les vaisseaux enregistrés
## pendant le parcours vont dans user://captures_vaisseaux/ (pas avec ceux du joueur).

const Partie = preload("res://scripts/partie.gd")
const Plan = preload("res://scripts/atelier/plan.gd")

var dossier := "user://captures_atelier_etape4/"


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


## La souris va sur ce point de l'écran, et la pièce à poser la suit (comme avec une vraie souris).
func _viser(at, pt: Vector2) -> void:
	Input.warp_mouse(pt)
	at.calculer_pose(pt)


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
	at.bulle.visible = false   # info-bulle laissée par la souris qui saute d'un point à l'autre
	Input.warp_mouse(Vector2(1598, 898))


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
	at.case_cg.button_pressed = true
	_vue(at, 145.0, -22.0)
	await _attendre(10)
	await _capture("01_tableau_ingenieur_8_tuiles")
	# Ctrl + clic : les deux ailes du haut et le moteur central ; la boule bleue = leur centre de gravité
	at.choisir("module", "aile_haut_droit")
	at.basculer_dans_selection("module", "aile_haut_gauche")
	at.basculer_dans_selection("module", "moteur_central")
	await _attendre(6)
	_propre(at)
	await _capture("02_plusieurs_pieces_ctrl_clic")
	# la page des masses (clic sur la tuile MASSE)
	_clic_tuile(at, 0)
	await _attendre(6)
	_propre(at)
	await _capture("03_page_des_masses")
	# la page des poussées : une flèche par moteur, la résultante, et la flèche courbe du couple
	_clic_tuile(at, 1)
	at.case_neutre.button_pressed = true
	_vue(at, 130.0, -16.0)
	await _attendre(8)
	_propre(at)
	await _capture("04_page_des_poussees_et_couple")
	# un gros moteur posé d'un seul côté (symétrie coupée) : le couple devient rouge
	at.case_symetrie.button_pressed = false
	at.case_neutre.button_pressed = false
	_vue(at, 145.0, -22.0)
	await _attendre(4)
	at.commencer_pose("moteur_ionique", {"poussee_kn": 400.0})
	_viser(at, _ecran(at, "Aile_bas_droit"))
	at.valider_pose()
	_propre(at)
	await _attendre(8)
	for i in 4:
		await physics_frame
	_clic_tuile(at, 1)
	at.case_neutre.button_pressed = true
	_vue(at, 130.0, -16.0)
	await _attendre(8)
	_propre(at)
	await _capture("05_moteur_d_un_seul_cote_couple_rouge")
	# la page de symétrie : ce qui n'a pas de jumelle est en orange
	_clic_tuile(at, 7)
	at.case_poussees.button_pressed = false
	_vue(at, 180.0, -60.0)
	await _attendre(8)
	_propre(at)
	await _capture("06_page_symetrie")
	# la salle à part : le morceau du chasseur qui porte le moteur posé, seul, avec le moteur
	at.case_neutre.button_pressed = false
	var sur := "Aile_bas_droit"
	for e in at.edition.ajouts():
		if e["modele"] == "moteur_ionique":
			sur = String(e.get("fixe_a", sur))
	var module := String(at.analyse.piece(sur).get("module", "aile_bas_droit"))
	print("moteur posé sur %s (module %s)" % [sur, module])
	at.choisir("module", module)
	at.entrer_salle()
	await _attendre(4)
	_vue(at, 125.0, -20.0)
	await _attendre(8)
	_propre(at)
	await _capture("07_salle_a_part_aile_et_moteur")
	# poser un propulseur dans la salle (fantôme vert qui suit la souris)
	at.commencer_pose("propulseur", {})
	_viser(at, _ecran(at, sur if at.maillages.has(sur) else "Aile_bas_droit", Vector3(0.0, 0.0, 0.6)))
	await _attendre(6)
	at.bulle.visible = false
	await _capture("08_poser_une_piece_dans_la_salle")
	at.valider_pose()
	_propre(at)
	await _attendre(8)
	for i in 4:
		await physics_frame
	at.case_poussees.button_pressed = true
	await _attendre(4)
	_propre(at)
	await _capture("09_piece_posee_dans_la_salle")
	# remettre en place : le vaisseau entier revient, avec ce qui a été posé
	at.sortir_salle()
	at.case_poussees.button_pressed = false
	at.deselectionner()
	_vue(at, 145.0, -22.0)
	await _attendre(8)
	for i in 4:
		await physics_frame
	_propre(at)
	await _capture("10_remis_en_place")
	print("pièces posées : %d, qui flottent : %d" % [at.edition.ajouts().size(), at.nb_flottantes])
	quit()
