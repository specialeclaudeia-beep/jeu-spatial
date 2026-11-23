extends SceneTree
## Captures d'écran de l'étape 6 de l'atelier (l'armature : poutres, connecteurs, panneaux), pour montrer
## ce qui a été fait sans lancer le jeu à la main. Parcours (symétrie allumée) : le catalogue « Armature » et
## l'outil de traçage → une cage sur le dos du fuselage, derrière le cockpit (deux arceaux posés sur les flancs,
## reliés en long ; une poutre coupe les deux traverses du haut : connecteurs en T) → une zone qui s'allume en
## vert → le toit et les flancs remplis de tôle → la fiche d'un connecteur en T et d'une poutre → une antenne
## tracée dans le vide, puis déplacée (G) → la tuile MASSE et la catégorie Armature → le jeu, vu de dehors.
## Ligne de commande (Linux, sans écran : xvfb-run) :
##   xvfb-run -s "-screen 0 1600x900x24" Godot --rendering-driver opengl3 --path . -s outils/captures_atelier_etape6.gd -- <dossier>
## Les images sont écrites dans <dossier> (par défaut user://captures_atelier_etape6/). Les vaisseaux enregistrés
## pendant le parcours vont dans user://captures_vaisseaux/ (pas avec ceux du joueur).

const Partie = preload("res://scripts/partie.gd")
const Plan = preload("res://scripts/atelier/plan.gd")
const Armature = preload("res://scripts/atelier/armature.gd")

var dossier := "user://captures_atelier_etape6/"


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


## Un clic de l'outil en cours avec un rayon (repère du vaisseau) : d'où il part, dans quelle direction.
func _clic(at, p: Vector3, dir: Vector3) -> void:
	var xf: Transform3D = at.corps.global_transform
	var d: Vector3 = (xf.basis * dir).normalized()
	at.calculer_trace_rayon(xf * p - d * 25.0, d)
	print("  clic %s : %s" % [p, at.trace.get("texte", "")])
	at.valider_trace()
	await _attendre(2)


## La souris posée sur un point du vaisseau (repère du vaisseau) : l'outil suit, la bulle le dit.
func _survol(at, p: Vector3) -> void:
	var pt: Vector2 = at.camera.unproject_position(at.corps.global_transform * p)
	Input.warp_mouse(pt)
	at._souris = pt
	at._demande_survol = pt
	await _physique(4)
	await _attendre(3)


func _proposition(at, modele: String) -> void:
	var it: TreeItem = at.arbre.get_root()
	while it != null:
		var m = it.get_metadata(0)
		if m is Dictionary and String(m["genre"]) == "modele_armature" and Armature.PROPOSITIONS[int(m["id"])][2] == modele:
			it.select(0)
			at.arbre.scroll_to_item(it)
			return
		it = it.get_next_in_tree()


func _clic_tuile(at, k: int) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	(at.tableau.get_child(k) as Control).gui_input.emit(ev)


func _connecteur_pres(at, p: Vector3) -> String:
	var id := ""
	var d := INF
	for e in at.edition.armature(Armature.CONNECTEUR):
		var l: float = Armature.position(e).distance_to(p)
		if l < d:
			d = l
			id = String(e["id"])
	return id


func _monde(at, id: String) -> Vector3:
	return at._monde_noeud(at.analyse.armature[id])


## Un clic de l'outil sur un connecteur déjà là (le rayon tombe d'en haut sur lui, ou vient de côté).
func _clic_noeud(at, id: String, dir := Vector3.DOWN) -> void:
	var w := _monde(at, id)
	var d: Vector3 = (at.corps.global_transform.basis * dir).normalized()
	at.calculer_trace_rayon(w - d * 25.0, d)
	print("  clic sur %s : %s" % [id, at.trace.get("texte", "")])
	at.valider_trace()
	await _attendre(2)


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
	var dos := AABB(Vector3(-1.6, -0.2, 0.4), Vector3(3.2, 2.4, 4.6))   # le dos du fuselage, derrière le cockpit
	var haut := 1.7
	# 1. le catalogue « Armature » : tracer des poutres (fiche de l'outil, ses réglages), la souris sur le flanc
	_proposition(at, Armature.POUTRE)
	await _attendre(4)
	_vue(at, 62.0, -14.0, dos, 1.5)
	await _attendre(6)
	await _clic(at, Vector3(3.0, 0.75, 1.6), Vector3.LEFT)       # A1 : sur le flanc droit du fuselage
	var pa1: Vector3 = at.trace["depart"]["point"]   # le premier clic ne fait que le départ
	await _survol(at, Vector3(pa1.x, haut, 1.6))
	await _capture("01_outil_poutres_fantome_dans_le_vide")
	# 2. premier arceau : A1 → B1 (dans le vide) → B1' (le jumeau de B1, de l'autre côté : poutre sur l'axe)
	await _clic(at, Vector3(3.0, haut, 1.6), Vector3.LEFT)
	var b1 := _connecteur_pres(at, Vector3(pa1.x, haut, 1.6))
	var a1 := _connecteur_pres(at, pa1)
	var b1j := String(at.analyse.armature[b1].get("symetrique", ""))
	await _clic_noeud(at, b1j)
	at.lacher_trace()
	# deuxième arceau, 2 m plus loin
	await _clic(at, Vector3(3.0, 0.75, 3.6), Vector3.LEFT)       # A2
	var pa2: Vector3 = at.trace["depart"]["point"]
	await _clic(at, Vector3(3.0, haut, 3.6), Vector3.LEFT)       # B2
	var a2 := _connecteur_pres(at, pa2)
	var b2 := _connecteur_pres(at, Vector3(pa2.x, haut, 3.6))
	var b2j := String(at.analyse.armature[b2].get("symetrique", ""))
	await _clic_noeud(at, b2j)
	at.lacher_trace()
	# en long : B1 → B2 et A1 → A2 (leurs jumelles se font aussi)
	await _clic_noeud(at, b1)
	await _clic_noeud(at, b2)
	at.lacher_trace()
	await _clic_noeud(at, a1, Vector3.LEFT)
	await _clic_noeud(at, a2, Vector3.LEFT)
	at.lacher_trace()
	# 3. une poutre au milieu du toit, qui coupe les deux traverses : deux connecteurs en T
	var xf: Transform3D = at.corps.global_transform
	var bas: Vector3 = -(xf.basis.y).normalized()
	at.calculer_trace_rayon(xf * Vector3(0.0, haut + 25.0, 1.6), bas)
	print("  T : ", at.trace.get("texte", ""))
	at.valider_trace()
	await _attendre(2)
	_vue(at, 150.0, -32.0, dos, 1.3)
	await _attendre(4)
	await _survol(at, Vector3(0.0, haut, 3.6))
	await _capture("02_couper_une_poutre_connecteur_en_T")
	at.calculer_trace_rayon(xf * Vector3(0.0, haut + 25.0, 3.6), bas)
	print("  T : ", at.trace.get("texte", ""))
	at.valider_trace()
	await _attendre(2)
	at.finir_trace()
	await _attendre(4)
	await _physique(8)
	_vue(at, 140.0, -24.0, dos, 1.5)
	await _attendre(6)
	_propre(at)
	await _capture("03_cage_tracee_symetrie")
	# 4. remplir : la zone sous la souris s'allume en vert ; le toit (deux moitiés) et les flancs
	_proposition(at, Armature.PANNEAU)
	await _attendre(4)
	_vue(at, 150.0, -32.0, dos, 1.3)
	await _attendre(4)
	await _survol(at, Vector3(0.45, haut, 2.6))
	await _capture("04_remplir_zone_verte")
	at.calculer_trace_rayon(xf * Vector3(0.45, haut + 25.0, 2.6), bas)
	print("  remplir le toit : ", at.trace.get("texte", ""))
	at.valider_trace()
	await _attendre(2)
	await _clic(at, Vector3(3.0, (0.75 + haut) * 0.5, 2.6), Vector3.LEFT)   # le flanc droit (et le gauche)
	at.finir_trace()
	await _attendre(4)
	await _physique(8)
	var panneaux: Array = at.edition.armature(Armature.PANNEAU)
	if not panneaux.is_empty():
		at.choisir("ajout", String(panneaux[0]["id"]))
	_vue(at, 140.0, -24.0, dos, 1.5)
	await _attendre(6)
	_propre(at)
	await _capture("05_toit_et_flancs_remplis_fiche_panneau")
	# 5. la fiche d'un connecteur en T, puis celle d'une poutre (réglages, « toutes les poutres »)
	var g := Armature.graphe(at.edition.donnees)
	var t_id := ""
	for c in g["connecteurs"]:
		if String(Armature.genre_connecteur(g, c)["nom"]).contains("en T"):
			t_id = c
	if t_id != "":
		at.choisir("ajout", t_id)
	await _attendre(6)
	_propre(at)
	await _capture("06_fiche_connecteur_en_T")
	at.choisir("ajout", String(at.edition.armature(Armature.POUTRE)[0]["id"]))
	await _attendre(6)
	_propre(at)
	await _capture("07_fiche_poutre_reglages")
	# 6. une antenne dans le vide, de B2 vers l'arrière et le haut ; puis G : son bout suit la souris
	at.deselectionner()
	_proposition(at, Armature.POUTRE)
	await _attendre(4)
	var pb2: Vector3 = Armature.position(at.analyse.armature[b2])
	await _clic_noeud(at, b2)
	await _clic(at, Vector3(3.0, pb2.y + 0.6, pb2.z + 1.3), Vector3.LEFT)
	at.finir_trace()
	await _attendre(4)
	var e_id := _connecteur_pres(at, Vector3(pb2.x, pb2.y + 0.6, pb2.z + 1.3))
	at.choisir("ajout", e_id)
	at.deplacer_selection()
	_vue(at, 70.0, -12.0, dos, 1.6)
	await _attendre(6)
	await _survol(at, Vector3(pb2.x, pb2.y + 1.1, pb2.z + 0.9))
	await _capture("08_deplacer_connecteur_G")
	at.valider_trace()
	at.deselectionner()
	await _attendre(4)
	await _physique(8)
	# 7. la tuile MASSE (avec l'armature) et la catégorie Armature
	_clic_tuile(at, 0)
	_vue(at, 145.0, -22.0, null, 1.0)
	await _attendre(6)
	_propre(at)
	await _capture("09_tuile_masse_armature")
	at.choisir("categorie", "armature")
	await _attendre(6)
	_propre(at)
	await _capture("10_categorie_armature")
	print("atelier : %d éléments d'armature, %d flottent ; contrôle : %s" % [at.analyse.armature.size(), at.nb_flottantes, at.controle.tuile()])
	for el in at.controle.elements:
		if String(el["niveau"]) != "ok":
			print("  %s · %s : %s" % [el["niveau"], el["titre"], el["texte"]])
	# 8. le jeu : la cage sur le dos, vue de dehors
	at.deselectionner()
	at.lancer_jeu(true)
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
	Input.action_press("zoom")
	for cible in [[0.35, 160.0, "11_jeu_exterieur_arriere_dessus"], [0.15, -100.0, "12_jeu_exterieur_cote"]]:
		jeu.tete = Vector2(cible[0], deg_to_rad(cible[1]))
		await _attendre(30)
		jeu.tete = Vector2(cible[0], deg_to_rad(cible[1]))
		await _capture(cible[2])
	Input.action_release("zoom")
	Input.action_release("regard_gauche")
	quit()
