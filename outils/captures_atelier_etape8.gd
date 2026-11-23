extends SceneTree
## Captures d'écran de l'étape 8 de l'atelier (la vie à bord : parois sous pression, air, oxygène, fuites),
## pour montrer ce qui a été fait sans lancer le jeu à la main. Parcours : la tuile CABINE et sa page, la vue
## « Parois » en couleur (la cabine du chasseur : vert) → une soute fermée en armature sur le dos (tôles
## d'aluminium-lithium de 2 mm), pressurisée : ses parois en orange (marge ×1,7) → les mêmes tôles en 1 mm : en
## rouge, et le contrôle avant le vol qui avertit → le jeu, remis en orbite (O) : dans le vide, la soute cède
## tout de suite (le message le dit), la cabine du pilote tient → la vanne de la cabine ouverte (F4) : la
## pression baisse, l'alarme → le pilote en hypoxie (vue du cockpit, zoom sur les écrans) → la vanne
## refermée : le régulateur remplit la cabine.
## Ligne de commande (Linux, sans écran : xvfb-run) :
##   xvfb-run -s "-screen 0 1600x900x24" Godot --rendering-driver opengl3 --path . -s outils/captures_atelier_etape8.gd -- <dossier>
## Les images sont écrites dans <dossier> (par défaut user://captures_atelier_etape8/). Les vaisseaux enregistrés
## pendant le parcours vont dans user://captures_vaisseaux/ (pas avec ceux du joueur).

const Partie = preload("res://scripts/partie.gd")
const Plan = preload("res://scripts/atelier/plan.gd")
const Armature = preload("res://scripts/atelier/armature.gd")
const VieABord = preload("res://scripts/physique/vie_a_bord.gd")

var dossier := "user://captures_atelier_etape8/"


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


func _clic_tuile(at, k: int) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	(at.tableau.get_child(k) as Control).gui_input.emit(ev)


## Le point du dos du vaisseau sous (x, z) (repère du vaisseau), et la pièce qui le porte.
func _dessus(at, x: float, z: float) -> Dictionary:
	var xf: Transform3D = at.corps.global_transform
	var r: Dictionary = at._rayon_monde(xf * Vector3(x, 8.0, z), -(xf.basis.y).normalized())
	if r.is_empty():
		return {"point": Vector3(x, 1.0, z)}
	return {"point": xf.affine_inverse() * (r["position"] as Vector3), "fixe_a": String((r["collider"] as Node).get_meta("piece", ""))}


## Une soute fermée sur le dos du fuselage, derrière le cockpit : 12 poutres, 6 tôles. Renvoie les tôles.
func _soute(at) -> Array:
	var ed = at.edition
	var bas := {}
	var y_haut := 0.0
	for c in [[-1, 1.9], [1, 1.9], [-1, 3.1], [1, 3.1]]:
		var d := _dessus(at, 0.45 * float(c[0]), float(c[1]))
		bas[c] = d
		y_haut = maxf(y_haut, (d["point"] as Vector3).y + 0.75)
	var ids := {}
	var coins := [[-1, 1.9], [1, 1.9], [1, 3.1], [-1, 3.1]]
	# le bas (sur le dos), le haut, puis les montants
	for etage in ["bas", "haut"]:
		for i in 4:
			var a: Array = coins[i]
			var b: Array = coins[(i + 1) % 4]
			var ka := [etage, a]
			var kb := [etage, b]
			var bout_a: Dictionary = {"noeud": ids[ka]} if ids.has(ka) else (bas[a] if etage == "bas" else {"point": Vector3(0.45 * float(a[0]), y_haut, float(a[1]))})
			var bout_b: Dictionary = {"noeud": ids[kb]} if ids.has(kb) else (bas[b] if etage == "bas" else {"point": Vector3(0.45 * float(b[0]), y_haut, float(b[1]))})
			var r: Dictionary = ed.tracer_poutre(bout_a, bout_b, {}, false)
			if r["erreur"] != "":
				print("  poutre %s → %s : %s" % [ka, kb, r["erreur"]])
				continue
			ids[ka] = String(r["debut"])
			ids[kb] = String(r["fin"])
	for c in coins:
		var r: Dictionary = ed.tracer_poutre({"noeud": ids[["bas", c]]}, {"noeud": ids[["haut", c]]}, {}, false)
		if r["erreur"] != "":
			print("  montant %s : %s" % [c, r["erreur"]])
	print("  soute : %d tôles posées" % ed.remplir_tout({"matiere": "aluminium_lithium", "epaisseur_m": 0.002}, false))
	var vols: Array = VieABord.volumes_armature(ed.donnees)
	for v in vols:
		print("  volume : fermé %s, %.3f m³, %d tôles" % [v["ferme"], float(v["volume_m3"]), (v["panneaux"] as Array).size()])
	if not vols.is_empty():
		ed.pressuriser(vols[0]["panneaux"], true)
		return vols[0]["panneaux"]
	return []


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
	at.case_cg.button_pressed = false
	var cockpit := AABB(Vector3(-1.6, -0.8, -3.2), Vector3(3.2, 2.6, 5.0))
	var dos := AABB(Vector3(-1.6, -0.4, -2.2), Vector3(3.2, 2.8, 6.4))
	# 1. la tuile CABINE et sa page ; « Parois » : la verrière, la baignoire et le cadre en vert
	_vue(at, 125.0, -22.0, cockpit, 1.15)
	_clic_tuile(at, 8)
	await _attendre(8)
	await _physique(6)
	_propre(at)
	await _capture("01_tuile_cabine_page_parois_vertes")
	# 2. une soute fermée sur le dos, pressurisée : tôles de 2 mm, en orange (×1,7 : moins que ×2)
	await _physique(6)
	var toles := _soute(at)
	await _attendre(6)
	await _physique(8)
	_clic_tuile(at, 8)
	await _attendre(6)
	_vue(at, 145.0, -28.0, dos, 0.8)
	await _attendre(6)
	_propre(at)
	await _capture("02_soute_pressurisee_toles_2mm_orange")
	print("cabine : %s" % [at.analyse.tuile_cabine()])
	# 3. les mêmes tôles en 1 mm : rouges ; le contrôle avant le vol avertit
	at.edition.regler_armature(toles, {"epaisseur_m": 0.001})
	await _attendre(6)
	await _physique(8)
	_clic_tuile(at, 8)
	await _attendre(6)
	_propre(at)
	await _capture("03_toles_1mm_rouges_elles_cassent")
	at.ouvrir_fenetre_controle()
	await _attendre(6)
	_propre(at)
	await _capture("04_controle_avant_le_vol_cabine")
	at.fermer_fenetre_controle()
	for el in at.controle.elements:
		if String(el["categorie"]) == "Cabine":
			print("  %s · %s : %s" % [el["niveau"], el["titre"], el["texte"]])
	# 4. le jeu : Lancer pose le vaisseau devant le hangar (l'air du dehors y est à 73 kPa : la soute tient) ;
	#    O : remis en orbite, dans le vide : la soute cède tout de suite, la cabine du pilote tient
	at.deselectionner()
	at.lancer_jeu(true)
	await _attendre(4)
	var t0 := Time.get_ticks_msec()
	while not (current_scene != null and current_scene.has_method("_poser_devant_hangar")) and Time.get_ticks_msec() - t0 < 60000:
		await process_frame
	var jeu = current_scene
	jeu.aide.visible = false
	await _attendre(10)
	print("jeu (hangar) : dehors %.1f kPa, cabine %.1f kPa, soute %s" % [jeu.vaisseau.vie.p_dehors / 1000.0, jeu.vaisseau.vie.pression_cabine() / 1000.0, _cassees(jeu)])
	jeu.clics["remettre_orbite"] = true
	await _attendre(2)
	jeu.vue_interieure = false
	jeu._appliquer_vue()
	jeu.tete = Vector2(0.3, deg_to_rad(-150.0))
	await _attendre(3)
	jeu.tete = Vector2(0.3, deg_to_rad(-150.0))
	print("jeu (orbite) : dehors %.1f kPa, cabine %.1f kPa, soute %s" % [jeu.vaisseau.vie.p_dehors / 1000.0, jeu.vaisseau.vie.pression_cabine() / 1000.0, _cassees(jeu)])
	await _capture("05_jeu_en_orbite_la_soute_cede_la_cabine_tient")
	# 5. la vanne de la cabine ouverte (F4) : l'air part, l'alarme ; puis l'écran du cockpit (zoom : B)
	jeu.clics["vanne_cabine"] = true
	t0 = Time.get_ticks_msec()
	while jeu.vaisseau.vie.pression_cabine() > 60000.0 and Time.get_ticks_msec() - t0 < 240000:
		jeu.tete = Vector2(0.3, deg_to_rad(-150.0))
		await process_frame
	print("jeu : vanne ouverte %s, cabine %.1f kPa, oxygène %.1f kPa" % [jeu.vaisseau.vie.vanne_ouverte, jeu.vaisseau.vie.pression_cabine() / 1000.0, jeu.vaisseau.vie.ppo2_cabine() / 1000.0])
	await _capture("06_jeu_vanne_ouverte_la_pression_baisse")
	# 6. l'hypoxie : le pilote n'a plus que quelques secondes ; vue du cockpit, zoom sur les écrans
	jeu.vue_interieure = true
	jeu._appliquer_vue()
	Input.action_press("zoom")
	t0 = Time.get_ticks_msec()
	while jeu.vaisseau.vie.temps_conscience > 15.0 and Time.get_ticks_msec() - t0 < 240000:
		jeu.tete = Vector2(-0.62, 0.0)
		await process_frame
	jeu.tete = Vector2(-0.62, 0.0)
	await _attendre(2)
	print("jeu : hypoxie, conscience %.1f s, cabine %.1f kPa" % [jeu.vaisseau.vie.temps_conscience, jeu.vaisseau.vie.pression_cabine() / 1000.0])
	await _capture("07_jeu_cockpit_hypoxie_ecran")
	Input.action_release("zoom")
	# 7. la vanne refermée : le régulateur remplit la cabine (temps ×10 pour ne pas attendre 45 s)
	jeu.clics["vanne_cabine"] = true
	await _attendre(2)
	jeu.vue_interieure = false
	jeu._appliquer_vue()
	jeu.acc_temps = 10
	t0 = Time.get_ticks_msec()
	while jeu.vaisseau.vie.pression_cabine() < 100000.0 and Time.get_ticks_msec() - t0 < 240000:
		jeu.tete = Vector2(0.3, deg_to_rad(-150.0))
		await process_frame
	jeu.acc_temps = 1
	await _attendre(4)
	jeu.tete = Vector2(0.3, deg_to_rad(-150.0))
	print("jeu : vanne refermée, cabine %.1f kPa, réserves %.1f + %.1f kg, pilote conscient %s" % [jeu.vaisseau.vie.pression_cabine() / 1000.0,
		jeu.vaisseau.vie.reserve_o2, jeu.vaisseau.vie.reserve_n2, not jeu.vaisseau.vie.inconscient()])
	await _capture("08_jeu_vanne_refermee_cabine_remplie")
	quit()


func _cassees(jeu) -> Array:
	return jeu.vaisseau.vie.comps.map(func(c): return "%s : %d parois cassées" % [c["nom"], (c["parois"] as Array).filter(func(w): return w["casse"]).size()])
