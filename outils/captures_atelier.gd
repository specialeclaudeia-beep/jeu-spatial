extends SceneTree
## Captures d'écran de l'atelier (étape 2), pour montrer ce qui a été fait sans lancer le jeu.
## Parcours : accueil → atelier (vue d'ensemble, une pièce choisie, recherche, vue technique, poussées)
## → « Lancer » → jeu posé devant le hangar (vue cockpit, vue extérieure). Mesure aussi la mémoire.
## Ligne de commande (Linux, sans écran : xvfb-run) :
##   xvfb-run -s "-screen 0 1600x900x24" Godot --rendering-driver opengl3 --path . -s outils/captures_atelier.gd -- <dossier>
## Les images sont écrites dans <dossier> (par défaut user://captures_atelier/).

const Partie = preload("res://scripts/partie.gd")

var dossier := "user://captures_atelier/"
var memoire := {}


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


func _mesurer_memoire(nom: String) -> void:
	memoire[nom] = {
		"ram_mo": Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0,
		"video_mo": RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_VIDEO_MEM_USED) / 1048576.0,
		"objets": Performance.get_monitor(Performance.OBJECT_COUNT),
	}
	print("mémoire %s : %s" % [nom, memoire[nom]])


func _parcours() -> void:
	# souris dans un coin (sinon une info-bulle s'ouvre sous elle, au milieu de l'écran)
	Input.warp_mouse(Vector2(1598, 898))
	# 1. l'accueil
	change_scene_to_file(Partie.SCENE_ACCUEIL)
	await _attendre(8)
	await _capture("01_accueil")
	var acc = current_scene
	acc.montrer_plans()
	await _attendre(3)
	await _capture("02_accueil_charger")
	# 2. l'atelier
	change_scene_to_file(Partie.SCENE_ATELIER)
	await _attendre(20)
	var at = current_scene
	at.case_neutre.button_pressed = false
	at.case_poussees.button_pressed = false
	at.case_cg.button_pressed = true
	at.camera.cadrer(at.boite_vaisseau())
	at.camera.vue("trois_quarts")
	await _attendre(10)
	_mesurer_memoire("atelier")
	await _capture("03_atelier")
	# une pièce choisie (clic) : surlignée, fiche à droite
	at.choisir("piece", "Aile_haut_gauche")
	at.camera.lacet = deg_to_rad(-40.0)
	at.camera.tangage = deg_to_rad(-22.0)
	at.camera.appliquer()
	await _attendre(6)
	await _capture("04_piece_et_fiche")
	# un moteur (sans dessin à lui : flèche)
	at.choisir("piece", "moteur_central")
	at.camera.lacet = deg_to_rad(28.0)
	at.camera.tangage = deg_to_rad(-14.0)
	at.camera.distance = 17.0
	at.camera.appliquer()
	await _attendre(6)
	await _capture("05_fiche_moteur")
	# la recherche
	at.recherche.text = "tuyere"
	at.remplir_catalogue()
	at.choisir("categorie", "moteurs")
	await _attendre(6)
	await _capture("06_recherche")
	at.recherche.text = ""
	at.remplir_catalogue()
	# vue technique : fond neutre, de côté, poussées et centre de gravité
	at.deselectionner()
	at.case_neutre.button_pressed = true
	at.case_poussees.button_pressed = true
	at.camera.cadrer(at.boite_vaisseau())
	at.camera.vue("droite")
	await _attendre(6)
	await _capture("07_vue_technique_poussees")
	at.camera.vue("dessus")
	await _attendre(6)
	await _capture("08_vue_dessus")
	at.case_neutre.button_pressed = false
	at.case_poussees.button_pressed = false
	# menu de la caméra (vitesse)
	at.camera.vue("trois_quarts")
	var bouton_cam: Button = null
	for b in at.ui.find_children("*", "Button", true, false):
		if (b as Button).text.begins_with("Caméra"):
			bouton_cam = b
	if bouton_cam != null:
		at._ouvrir_menu_camera(bouton_cam)
		at.curseur_vitesse.value = 1.0
		await _attendre(6)
		await _capture("09_menu_camera")
	# 3. Lancer : le jeu, posé devant le hangar
	at.lancer_jeu()
	await _attendre(4)
	var t0 := Time.get_ticks_msec()
	while not (current_scene != null and current_scene.has_method("_poser_devant_hangar")) and Time.get_ticks_msec() - t0 < 60000:
		await process_frame
	var jeu = current_scene
	await _attendre(90)
	_mesurer_memoire("jeu")
	print("jeu : départ %s, au sol %s, vitesse %.3f m/s" % [jeu.depart, jeu.vaisseau.au_sol,
		(Vector3(jeu.vaisseau.vx, jeu.vaisseau.vy, jeu.vaisseau.vz) - jeu.vaisseau.vitesse_sol(jeu.vaisseau.px, jeu.vaisseau.py, jeu.vaisseau.pz)).length()])
	jeu.aide.visible = false   # l'aide (touche H) cache le bas de l'image
	await _attendre(2)
	await _capture("10_jeu_cockpit")
	jeu.vue_interieure = false
	jeu._appliquer_vue()
	await _attendre(10)
	await _capture("11_jeu_exterieur_tableau")
	# tour de la caméra extérieure : stick droit poussé à peine (sinon la tête revient au centre)
	jeu.hud.visible = false
	Input.action_press("regard_gauche", 0.01)
	for cible in [[0.12, 140.0, "12_jeu_exterieur_avant"], [0.25, -110.0, "13_jeu_exterieur_cote"]]:
		jeu.tete = Vector2(cible[0], deg_to_rad(cible[1]))
		await _attendre(12)
		jeu.tete = Vector2(cible[0], deg_to_rad(cible[1]))
		await _capture(cible[2])
	Input.action_release("regard_gauche")
	var f := FileAccess.open(dossier + "memoire.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(memoire, "\t"))
	f.close()
	quit()
