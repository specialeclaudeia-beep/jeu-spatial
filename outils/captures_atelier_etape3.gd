extends SceneTree
## Captures d'écran de l'étape 3 de l'atelier (poser des pièces), pour montrer ce qui a été fait sans lancer le jeu.
## Parcours : catalogue des pièces → un moteur qui suit la souris (fantôme vert + sa jumelle) → moteurs posés et
## leur fiche (réglages) → une boîte dans le vide (rouge, « Lancer » refusé) → un module enlevé → vue de dessus
## → « Lancer » : le vaisseau avec ses nouveaux moteurs, posé devant le hangar.
## Ligne de commande (Linux, sans écran : xvfb-run) :
##   xvfb-run -s "-screen 0 1600x900x24" Godot --rendering-driver opengl3 --path . -s outils/captures_atelier_etape3.gd -- <dossier>
## Les images sont écrites dans <dossier> (par défaut user://captures_atelier_etape3/). Les vaisseaux enregistrés
## pendant le parcours vont dans user://captures_vaisseaux/ (pas avec ceux du joueur).

const Partie = preload("res://scripts/partie.gd")
const Plan = preload("res://scripts/atelier/plan.gd")

var dossier := "user://captures_atelier_etape3/"


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
	at.camera.cadrer(at.boite_vaisseau())
	at.camera.vue("trois_quarts")
	at.camera.lacet = deg_to_rad(145.0)
	at.camera.tangage = deg_to_rad(-24.0)
	at.camera.appliquer()
	await _attendre(10)
	await _capture("01_catalogue_pieces_a_poser")
	# un moteur ionique de 400 kN qui suit la souris : fantôme vert sur l'aile basse droite, sa jumelle à gauche
	at.commencer_pose("moteur_ionique", {"poussee_kn": 400.0})
	_viser(at, _ecran(at, "Aile_bas_droit"))
	await _attendre(6)
	await _capture("02_moteur_qui_suit_la_souris")
	at.valider_pose()
	Input.warp_mouse(Vector2(1598, 898))
	await _attendre(8)
	for i in 4:
		await physics_frame
	await _attendre(4)
	at.bulle.visible = false   # info-bulle laissée par la souris qui saute d'un point à l'autre
	await _capture("03_moteurs_poses_et_reglages")
	# un propulseur sur le dessus du fuselage (au milieu : pas de jumelle)
	at.commencer_pose("propulseur", {})
	_viser(at, _ecran(at, "Fuselage", Vector3(0, 0.6, 0)))
	at.valider_pose()
	Input.warp_mouse(Vector2(1598, 898))
	await _attendre(6)
	# une boîte posée dans le vide : rouge, et « Lancer » refusé
	at.commencer_pose("boite", {})
	var haut: Vector3 = at.pilote.global_position + at.corps.global_transform.basis * Vector3(6.5, 3.5, 0.0)
	_viser(at, at.camera.unproject_position(haut))
	at.valider_pose()
	Input.warp_mouse(Vector2(1598, 898))
	await _attendre(6)
	for i in 5:
		await physics_frame
	at.deselectionner()
	await _attendre(2)
	var lance := true
	if at.nb_flottantes > 0:
		lance = await at.lancer_jeu()
	print("pièces qui flottent : %d, Lancer : %s" % [at.nb_flottantes, "refusé" if not lance else "ACCEPTÉ"])
	await _attendre(6)
	at.bulle.visible = false   # info-bulle laissée par la souris qui saute d'un point à l'autre
	await _capture("04_piece_dans_le_vide_lancer_refuse")
	at.annuler()
	await _attendre(6)
	for i in 5:
		await physics_frame
	at.avis.visible = false
	# un module enlevé : l'aile haute gauche (avec son moteur et ses lueurs)
	at.choisir("module", "aile_haut_gauche")
	await _attendre(4)
	at.bulle.visible = false   # info-bulle laissée par la souris qui saute d'un point à l'autre
	await _capture("05_module_choisi")
	at.supprimer_selection()
	await _attendre(8)
	at.bulle.visible = false   # info-bulle laissée par la souris qui saute d'un point à l'autre
	await _capture("06_module_enleve")
	at.annuler()
	await _attendre(8)
	# vue de dessus, fond neutre et poussées : les deux moteurs ajoutés, bien en miroir
	at.deselectionner()
	at.case_neutre.button_pressed = true
	at.case_poussees.button_pressed = true
	at.camera.cadrer(at.boite_vaisseau())
	at.avis.visible = false
	at.camera.vue("dessus")
	await _attendre(8)
	at.bulle.visible = false   # info-bulle laissée par la souris qui saute d'un point à l'autre
	await _capture("07_vue_dessus_symetrie")
	at.case_neutre.button_pressed = false
	at.case_poussees.button_pressed = false
	at.renommer("Chasseur aux gros moteurs")
	at.enregistrer()
	print("enregistré : ", at.edition.chemin)
	await _attendre(4)
	# « Lancer » : le jeu, posé devant le hangar, avec les nouveaux moteurs
	at.lancer_jeu()
	await _attendre(4)
	var t0 := Time.get_ticks_msec()
	while not (current_scene != null and current_scene.has_method("_poser_devant_hangar")) and Time.get_ticks_msec() - t0 < 60000:
		await process_frame
	var jeu = current_scene
	await _attendre(90)
	jeu.aide.visible = false
	jeu.vue_interieure = false
	jeu._appliquer_vue()
	jeu.hud.visible = false
	Input.action_press("regard_gauche", 0.01)
	Input.action_press("zoom")   # champ de vision resserré : le vaisseau paraît plus grand
	for cible in [[0.18, 150.0, "08_jeu_avec_les_moteurs_poses"], [0.3, -120.0, "09_jeu_vu_de_cote"]]:
		jeu.tete = Vector2(cible[0], deg_to_rad(cible[1]))
		await _attendre(12)
		jeu.tete = Vector2(cible[0], deg_to_rad(cible[1]))
		await _capture(cible[2])
	Input.action_release("regard_gauche")
	Input.action_release("zoom")
	jeu.hud.visible = true
	await _attendre(4)
	await _capture("10_jeu_tableau_moteurs")
	print("moteurs dans le jeu : %d" % jeu.vaisseau.moteurs.size())
	quit()
