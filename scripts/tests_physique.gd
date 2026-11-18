extends Control
## Tests automatiques de la physique (touche F1 dans le jeu, Échap pour revenir).
## Chaque test vérifie une loi physique sur le vrai code du vaisseau.

const VaisseauPhysique = preload("res://scripts/physique/vaisseau_physique.gd")
const Commandes = preload("res://scripts/commandes.gd")
const Jeu = preload("res://scripts/jeu.gd")
const LumiereJeu = preload("res://scripts/lumiere_jeu.gd")
const Objets = preload("res://scripts/lumiere/objets.gd")
const Reflets = preload("res://scripts/lumiere/reflets.gd")
const PiloteAuto = preload("res://scripts/physique/pilote_auto.gd")
const R := 600000.0
const GM := 9.81 * 600000.0 * 600000.0

var texte: RichTextLabel
var reussis := 0
var total := 0


func _ready() -> void:
	var fond := ColorRect.new()
	fond.color = Color(0.03, 0.04, 0.07)
	fond.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(fond)
	texte = RichTextLabel.new()
	texte.bbcode_enabled = true
	texte.set_anchors_preset(Control.PRESET_FULL_RECT)
	texte.offset_left = 30
	texte.offset_top = 20
	texte.offset_right = -30
	texte.offset_bottom = -20
	texte.add_theme_font_size_override("normal_font_size", 17)
	texte.add_theme_font_size_override("bold_font_size", 18)
	add_child(texte)
	texte.text = "[b]Tests de physique[/b]\n\nCalcul en cours…"
	await get_tree().process_frame
	await get_tree().process_frame
	_lancer()


func _unhandled_input(e: InputEvent) -> void:
	var echap: bool = e is InputEventKey and e.is_pressed() and (e as InputEventKey).keycode == KEY_ESCAPE
	var manette: bool = e is InputEventJoypadButton and e.is_pressed() and (e as InputEventJoypadButton).button_index in [JOY_BUTTON_B, JOY_BUTTON_START]
	if echap or manette:   # Échap, ou Rond / Options sur la manette
		get_tree().change_scene_to_file("res://scenes/jeu.tscn")


func _nouveau(avec_planete: bool):
	var v = VaisseauPhysique.new()
	v.reactivite_moteurs = 1e-6   # poussée instantanée pour des tests nets
	if avec_planete:
		v.gm = GM
		v.rayon_planete = R
	return v


func _resultat(ok: bool, titre: String, detail: String) -> void:
	total += 1
	if ok:
		reussis += 1
	var etiquette := "[color=#5fe08a][OK][/color]" if ok else "[color=#ff6b6b][ÉCHEC][/color]"
	texte.append_text("%s [b]%s[/b]\n      %s\n\n" % [etiquette, titre, detail])
	print("%s %s : %s" % ["[OK]" if ok else "[ÉCHEC]", titre, detail])   # aussi dans la console


func _lancer() -> void:
	texte.text = "[b]Tests de physique[/b]   (Échap, ou Rond sur la manette, pour revenir au jeu)\n\n"
	var debut := Time.get_ticks_msec()

	# 1. Inertie : dans le vide, sans moteur, la vitesse ne change pas
	var v = _nouveau(false)
	v.vx = 100.0
	for i in 12000:
		v.pas(1.0 / 120.0)
	_resultat(absf(v.vx - 100.0) < 1e-9 and absf(v.px - 10000.0) < 1e-6,
		"Inertie dans le vide",
		"Après 100 s sans moteur : vitesse %.9f m/s (attendu 100), distance %.6f m (attendu 10 000)." % [v.vx, v.px])

	# 2. Moteur central seul : il pousse dans l'axe, mais le centre de gravité réel est 2 cm plus haut
	#    que cet axe : il fait donc tourner très lentement (couple = bras de levier × force).
	v = _nouveau(false)
	v.moteurs[4]["consigne"] = 1.0
	v.moteurs[4]["actuel"] = 1.0
	for i in 120:
		v.pas(1.0 / 120.0)
	var vit: float = v.vitesse()
	var f2: float = v.moteurs[4]["poussee_max"]
	var att2: float = f2 / v.masse * 1.0
	var c2: Vector3 = ((v.moteurs[4]["position"] as Vector3) - v.CENTRE_GRAVITE).cross(Vector3(0, 0, -f2))
	var att2w: float = c2.x / v.inertie.x * 1.0
	_resultat(absf(vit - att2) < 0.002 * att2 and absf(v.omega.x - att2w) < 0.02 * absf(att2w) and absf(v.omega.y) < 1e-9,
		"Poussée du moteur central",
		"%.0f kN sur %.2f t pendant 1 s : %.3f m/s (attendu %.3f). Tangage %.5f rad/s (attendu %.5f : centre de gravité 2 cm au-dessus du moteur), lacet %.9f (attendu 0)." % [f2 / 1000.0, v.masse / 1000.0, vit, att2, v.omega.x, att2w, v.omega.y])

	# 3. Poussée décentrée : le moteur haut droit fait aussi tourner (couple = position × force)
	v = _nouveau(false)
	v.moteurs[1]["consigne"] = 1.0
	for i in 24:
		v.pas(1.0 / 120.0)
	# couple = position × force : bras de levier = hauteur et largeur du moteur, pendant 0,2 s
	var f3: float = v.moteurs[1]["poussee_max"]
	var pos3: Vector3 = (v.moteurs[1]["position"] as Vector3) - v.CENTRE_GRAVITE   # bras de levier vu du centre de gravité
	var attendu_x: float = -pos3.y * f3 * 0.2 / v.inertie.x
	var attendu_y: float = pos3.x * f3 * 0.2 / v.inertie.y
	var att3v: float = f3 / v.masse * 0.2
	var w: Vector3 = v.omega
	var ok3: bool = absf(w.x - attendu_x) < 0.05 * absf(attendu_x) and absf(w.y - attendu_y) < 0.05 * attendu_y and absf(v.vitesse() - att3v) < 0.05 * att3v
	_resultat(ok3, "Poussée décentrée = rotation",
		"Moteur haut droit seul pendant 0,2 s : tangage %.3f rad/s (≈ %.3f), lacet %.3f rad/s (≈ %.3f), vitesse %.2f m/s (≈ %.2f). Le nez descend et part à gauche, comme prévu." % [w.x, attendu_x, w.y, attendu_y, v.vitesse(), att3v])

	# 4. Orbite circulaire stable pendant 3 tours
	v = _nouveau(true)
	v.placer_en_orbite(100000.0)
	var r0: float = v.distance_centre()
	var e0: float = v.energie_specifique()
	var periode := TAU * sqrt(r0 * r0 * r0 / GM)
	var rmin := INF
	var rmax := 0.0
	var n4 := int(round(3.0 * periode / 0.1))
	for i in n4:
		v.pas(0.1)
		var r: float = v.distance_centre()
		rmin = minf(rmin, r)
		rmax = maxf(rmax, r)
	var ecart := (rmax - rmin) / r0
	var derive := absf((v.energie_specifique() - e0) / e0)
	_resultat(ecart < 1e-4 and derive < 1e-6, "Orbite stable sans moteur",
		"3 tours (%.0f s) : l'altitude varie de %.2f m, l'énergie dérive de %.8f %%." % [3.0 * periode, rmax - rmin, derive * 100.0])

	# 5. Précision : en divisant le pas de temps par 2, l'erreur est divisée par ~4
	var erreurs := []
	for dt in [1.0, 0.5, 0.25]:
		v = _nouveau(true)
		v.placer_en_orbite(100000.0)
		var n5 := int(round(periode / dt))
		for i in n5:
			v.pas(dt)
		var t: float = n5 * dt
		var wo := sqrt(GM / (r0 * r0 * r0))
		var ex := r0 * cos(wo * t)
		var ez := -r0 * sin(wo * t)
		erreurs.append(sqrt((v.px - ex) * (v.px - ex) + v.py * v.py + (v.pz - ez) * (v.pz - ez)))
	var ok5: bool = erreurs[1] < erreurs[0] / 3.0 and erreurs[2] < erreurs[1] / 3.0
	_resultat(ok5, "Précision du calcul",
		"Écart après 1 tour : %.2f m (pas 1 s), %.2f m (0,5 s), %.2f m (0,25 s). En jeu le pas est de 1/120 s." % [erreurs[0], erreurs[1], erreurs[2]])

	# 6. Rotation libre : le moment cinétique est conservé
	v = _nouveau(false)
	v.omega = Vector3(0.1, 0.2, 0.05)
	var l0: Vector3 = v.moment_cinetique_monde()
	for i in 7200:
		v.pas(1.0 / 120.0)
	var l1: Vector3 = v.moment_cinetique_monde()
	var d6 := (l1 - l0).length() / l0.length()
	_resultat(d6 < 0.01, "Rotation libre (moment cinétique conservé)",
		"Vaisseau qui tourne sur lui-même pendant 60 s sans aucune force : écart %.3f %%." % (d6 * 100.0))

	# 7. Propulseurs de roulis : rotation pure, sans déplacement
	v = _nouveau(false)
	v.commander(0.0, 0.0, 0.0, 1.0)
	for i in 240:
		v.pas(1.0 / 120.0)
	var att7: float = v.couple_max.z * 2.0 / v.inertie.z
	_resultat(absf(v.omega.z - att7) < 0.03 * att7 and v.vitesse() < 1e-3, "Propulseurs d'orientation (roulis)",
		"2 s de roulis : %.3f rad/s (attendu %.3f), vitesse %.6f m/s (attendu ≈ 0 : les forces s'annulent, à moins de 6 N près)." % [v.omega.z, att7, v.vitesse()])

	# 8. Chute libre près du sol
	v = _nouveau(true)
	v.px = R + 100.0
	for i in 240:
		v.pas(1.0 / 120.0)
	var chute: float = R + 100.0 - v.distance_centre()
	var g_loc := GM / ((R + 100.0) * (R + 100.0))
	var att8 := 0.5 * g_loc * 4.0
	_resultat(absf(chute - att8) < 0.01 * att8, "Chute libre",
		"Lâché à 100 m sans vitesse : chute de %.2f m en 2 s (attendu %.2f m)." % [chute, att8])

	# 9. Instruments d'orbite
	v = _nouveau(true)
	v.placer_en_orbite(100000.0)
	var o: Dictionary = v.orbite()
	_resultat(absf(o["peri"] - 100000.0) < 1.0 and absf(o["apo"] - 100000.0) < 1.0, "Calcul de l'orbite",
		"Orbite circulaire à 100 km : périapside %.1f m, apoapside %.1f m." % [o["peri"], o["apo"]])

	# 10. Plusieurs astres : la gravité est la somme exacte des attractions
	v = _nouveau(true)
	var gm_lune := GM * 0.0123
	var xl := 3.0e6
	v.ajouter_astre("lune", gm_lune, xl, 0.0, 0.0)
	var xs := R + 500000.0
	var g10: Array = v.gravite(xs, 0.0, 0.0)
	var att10 := -GM / (xs * xs) + gm_lune / ((xl - xs) * (xl - xs))
	var ok10a: bool = absf(float(g10[0]) - att10) < 1e-12 * absf(att10) and absf(float(g10[1])) < 1e-15 and absf(float(g10[2])) < 1e-15
	# entre deux astres identiques, au milieu, les attractions s'annulent : le vaisseau ne bouge pas
	var v10 = _nouveau(false)
	v10.gradient_gravite = false
	v10.ajouter_astre("A", GM, -2.0e6, 0.0, 0.0)
	v10.ajouter_astre("B", GM, 2.0e6, 0.0, 0.0)
	for i in 12000:
		v10.pas(1.0 / 120.0)
	var ok10b: bool = v10.vitesse() < 1e-9 and v10.distance_centre() < 1e-6
	_resultat(ok10a and ok10b, "Gravité de plusieurs astres",
		"Planète + lune : %.6f m/s² (attendu %.6f). Au milieu de deux astres identiques pendant 100 s : vitesse %.9f m/s (attendu 0)." % [float(g10[0]), att10, v10.vitesse()])

	# 11. Gradient de gravité : couple nul nez vers la planète, valeur exacte à 45°
	v = _nouveau(true)
	var r11 := R + 100000.0
	v.px = r11
	# nez (-Z) vers la planète (-X monde), axe de tangage (X du vaisseau) = Y monde
	var base_nadir := Basis(Vector3(0, 1, 0), Vector3(0, 0, 1), Vector3(1, 0, 0))
	v.orientation = Quaternion(base_nadir)
	var c_aligne: Vector3 = v.couple_gravite()
	v.orientation = Quaternion(base_nadir) * Quaternion(Vector3.RIGHT, PI / 4.0)
	var c45: Vector3 = v.couple_gravite()
	var att11: float = 3.0 * GM / (r11 * r11 * r11) * (v.inertie.y - v.inertie.z) * 0.5
	var ok11: bool = c_aligne.length() < 1e-6 * att11 and absf(absf(c45.x) - att11) < 1e-4 * att11 and absf(c45.y) < 1e-4 * att11 and absf(c45.z) < 1e-4 * att11
	_resultat(ok11, "Gradient de gravité (valeur du couple)",
		"Nez vers la planète : %.9f N·m (attendu 0). Penché de 45° : %.4f N·m (attendu %.4f), soit environ 8 000 fois moins que les propulseurs de tangage." % [c_aligne.length(), absf(c45.x), att11])

	# 12. Balancement en orbite : penché de 5°, le vaisseau oscille autour de la direction de la planète
	v = _nouveau(true)
	v.placer_en_orbite(100000.0)
	var n12 := sqrt(GM / (r11 * r11 * r11))              # vitesse de rotation de l'orbite (rad/s)
	var theta0 := deg_to_rad(5.0)
	v.orientation = Quaternion(base_nadir) * Quaternion(Vector3.RIGHT, theta0)
	v.omega = Vector3(n12, 0, 0)                           # il tourne avec l'orbite, comme un satellite
	var w_lib: float = n12 * sqrt(3.0 * (v.inertie.y - v.inertie.z) / v.inertie.x)
	var t_lib: float = TAU / w_lib                               # durée d'un aller-retour prévue
	var angle_min := INF
	var n12_pas: int = int(round(t_lib / 0.1))
	for i in n12_pas:
		v.pas(0.1)
		var nez: Vector3 = Basis(v.orientation) * Vector3(0, 0, -1)
		var vers_planete := Vector3(-v.px, -v.py, -v.pz).normalized()
		angle_min = minf(angle_min, acos(clampf(nez.dot(vers_planete), -1.0, 1.0)))
	var nez_f: Vector3 = Basis(v.orientation) * Vector3(0, 0, -1)
	var angle_f: float = acos(clampf(nez_f.dot(Vector3(-v.px, -v.py, -v.pz).normalized()), -1.0, 1.0))
	var ok12: bool = angle_min < 0.1 * theta0 and absf(angle_f - theta0) < 0.15 * theta0
	_resultat(ok12, "Balancement dû à la gravité",
		"Penché de 5° en orbite, sans moteur : passe à %.2f° de la planète puis revient à %.2f° après %.0f s (aller-retour prévu : %.0f s, soit %.0f min)." % [rad_to_deg(angle_min), rad_to_deg(angle_f), n12_pas * 0.1, t_lib, t_lib / 60.0])

	# 13. Calcul automatique : tangage pur, moteurs coupés
	v = _nouveau(false)
	v.commander(0.0, 1.0, 0.0, 0.0)
	for m in v.moteurs:
		m["actuel"] = m["consigne"]   # on regarde la consigne, sans attendre le temps de réponse
	var e13: Array = v.effet_propulseurs()
	var f13: Vector3 = e13[0]
	var c13: Vector3 = e13[1]
	var ok13: bool = absf(c13.x - v.couple_max.x) < 0.01 * v.couple_max.x and absf(c13.y) < 0.01 * v.couple_max.x and absf(c13.z) < 0.01 * v.couple_max.x and f13.length() < 0.001 * v.POUSSEE_RCS
	_resultat(ok13, "Calcul automatique : tangage seul",
		"Couple %.0f N·m (demandé %.0f), couples parasites %.1f et %.1f N·m, force restante %.3f N (attendu 0 : rotation sans déplacement)." % [c13.x, v.couple_max.x, c13.y, c13.z, f13.length()])

	# 14. Calcul automatique : virage moteurs allumés, les moteurs d'un côté poussent plus fort
	v = _nouveau(false)
	v.commander(0.5, 0.0, 1.0, 0.0)
	for m in v.moteurs:
		m["actuel"] = m["consigne"]
	var e14: Array = v.effet_propulseurs()
	var f14: Vector3 = e14[0]
	var c14: Vector3 = e14[1]
	var droite: float = (float(v.moteurs[1]["actuel"]) + float(v.moteurs[3]["actuel"])) * 0.5
	var gauche: float = (float(v.moteurs[0]["actuel"]) + float(v.moteurs[2]["actuel"])) * 0.5
	var att14: float = 0.5 * v.poussee_avant_max
	var ok14: bool = absf(c14.y - v.couple_max.y) < 0.02 * v.couple_max.y and absf(-f14.z - att14) < 0.02 * att14 and droite > gauche + 0.02 and absf(c14.x) < 0.02 * v.couple_max.y and absf(c14.z) < 0.02 * v.couple_max.y
	_resultat(ok14, "Calcul automatique : virage à mi-gaz",
		"Lacet %.0f N·m (demandé %.0f), poussée %.0f kN (demandée %.0f kN). Moteurs de droite à %.0f %%, de gauche à %.0f %% : c'est la différence de poussée qui fait tourner." % [c14.y, v.couple_max.y, -f14.z / 1000.0, att14 / 1000.0, droite * 100.0, gauche * 100.0])

	# 15. Calcul automatique : plein gaz + virage, et légèreté du calcul
	v = _nouveau(false)
	var t0 := Time.get_ticks_usec()
	for i in 1000:
		v.commander(1.0, 0.0, 1.0, 0.0)
	var us := float(Time.get_ticks_usec() - t0) / 1000.0
	for m in v.moteurs:
		m["actuel"] = m["consigne"]
	var e15: Array = v.effet_propulseurs()
	var f15: Vector3 = e15[0]
	var c15: Vector3 = e15[1]
	var ok15: bool = absf(c15.y - v.couple_max.y) < 0.02 * v.couple_max.y and -f15.z > 0.97 * v.poussee_avant_max
	_resultat(ok15, "Calcul automatique : plein gaz + virage",
		"Lacet %.0f N·m (demandé %.0f), poussée %.0f kN sur %.0f kN possibles. Calcul : %.0f microsecondes par image (léger)." % [c15.y, v.couple_max.y, -f15.z / 1000.0, v.poussee_avant_max / 1000.0, us])

	_tests_position_valide()
	_tests_commandes()
	_tests_modele_v12()
	_tests_lumiere()
	_test_cockpit()
	_test_vol_vertical()
	_tests_pilote_auto()
	_tests_v25()

	var duree := (Time.get_ticks_msec() - debut) / 1000.0
	var couleur := "#5fe08a" if reussis == total else "#ffcc55"
	texte.append_text("[b][color=%s]%d / %d tests réussis[/color][/b]  (%.1f s de calcul)\n" % [couleur, reussis, total, duree])
	print("Tests de physique : %d / %d réussis" % [reussis, total])


# =====================================================================
# TESTS : LA POSITION RESTE VALIDE (bug « is_finite »)
# =====================================================================
## Avant la correction, la rotation s'emballait en tournant vite ou en temps accéléré : les nombres
## devenaient infinis, puis la position du vaisseau devenait invalide (erreurs « is_finite »).
func _valide(v) -> bool:
	return is_finite(v.px) and is_finite(v.py) and is_finite(v.pz) and is_finite(v.vx) \
		and is_finite(v.omega.length()) and is_finite(v.orientation.length())


## Une image du jeu, comme dans jeu.gd : un ordre, puis plusieurs pas en temps accéléré.
func _image(v, acc: int, ordre: Vector3, stabilisateur: bool) -> void:
	var o := ordre
	if stabilisateur:
		var s: Vector3 = v.ordres_stabilisateur(acc / 120.0)
		if o.x == 0.0: o.x = s.x
		if o.y == 0.0: o.y = s.y
		if o.z == 0.0: o.z = s.z
	v.commander(0.0, o.x, o.y, o.z)
	var n: int = mini(acc, 25)
	for i in n:
		v.pas(acc / 120.0 / n)


func _tests_position_valide() -> void:
	# 16. Rotation libre en temps ×1000 : le moment cinétique et l'énergie de rotation se conservent
	var v = _nouveau(false)
	v.omega = Vector3(0.02, 1.0, 0.02)   # rotation autour de l'axe « instable » (celui du milieu)
	var l0: float = v.moment_cinetique_monde().length()
	var e0: float = _energie_rotation(v)
	var valide := true
	for i in 6000:   # 2 000 s par pas de 1/3 s
		v.pas(1.0 / 3.0)
		if not _valide(v):
			valide = false
			break
	var l1: float = v.moment_cinetique_monde().length()
	var e1: float = _energie_rotation(v)
	_resultat(valide and absf(l1 - l0) < 1e-3 * l0 and absf(e1 - e0) < 0.02 * e0,
		"Rotation libre en temps ×1000",
		"Après 2 000 s sans moteur : moment cinétique %.0f (au départ %.0f), énergie de rotation %.0f J (au départ %.0f J). Avant la correction : nombres infinis." % [l1, l0, e1, e0])

	# 17. Roulis + tangage tenus en temps ×10 : on tourne très vite, mais tout reste valide
	v = _nouveau(true)
	v.placer_en_orbite(100000.0)
	var en0: float = v.energie_specifique()
	valide = true
	for i in 1200:   # 10 s réelles = 100 s de jeu
		_image(v, 10, Vector3(1, 0, 1), false)
		if not _valide(v):
			valide = false
			break
	var en1: float = v.energie_specifique()
	_resultat(valide and absf(en1 - en0) < 1e-4 * absf(en0),
		"Tourner sans s'arrêter, temps ×10",
		"Roulis et tangage tenus 100 s : rotation %.0f rad/s (rien ne la freine, c'est normal), position valide, orbite presque inchangée (énergie %.1f J/kg, au départ %.1f). Avant la correction : position invalide après 1 s." % [v.omega.length(), en1, en0])

	# 18. Stabilisateur en temps ×1000 : il arrête la rotation au lieu de l'emballer
	v = _nouveau(true)
	v.placer_en_orbite(100000.0)
	v.omega = Vector3(0.1, -0.2, 0.3)
	valide = true
	for i in 600:
		_image(v, 1000, Vector3.ZERO, true)
		if not _valide(v):
			valide = false
			break
	_resultat(valide and v.omega.length() < 1e-3,
		"Stabilisateur en temps ×1000",
		"Rotation de départ 0,37 rad/s ; après 5 s réelles : %.6f rad/s (attendu ≈ 0), position valide." % v.omega.length())


# =====================================================================
# TESTS DU MODÈLE 3D : PROPULSEURS, AILES, TRAIN
# =====================================================================
func _tests_modele_v12() -> void:
	# 23. Les propulseurs de la physique sont exactement là où le modèle 3D les dessine
	#     (fichier positions_tuyeres_godot.json exporté de Blender, ailes ouvertes)
	var v = _nouveau(false)
	var f := FileAccess.open("res://modeles/vaisseau/positions_tuyeres_godot.json", FileAccess.READ)
	var modele = JSON.parse_string(f.get_as_text()) if f != null else null
	var ecart_max := INF
	var manquants := PackedStringArray()
	if modele is Dictionary:
		ecart_max = 0.0
		for t in v.moteurs + v.rcs:
			var cle: String = ("moteur " if v.moteurs.has(t) else "rcs ") + String(t["nom"])
			if String(t["nom"]).begins_with("levage") or (not v.moteurs.has(t) and int(t["axe"]) < 0):
				continue   # buses encastrées : comparées au modèle dans le test « Buses encastrées »
			if String(t["nom"]).begins_with("levage"):
				continue   # moteurs de levage : rentrés au départ, comparés sortis dans le test du vol vertical
			if not modele.has(cle):
				manquants.append(cle)
				continue
			var p: Array = modele[cle]
			ecart_max = maxf(ecart_max, ((t["position"] as Vector3) - Vector3(p[0], p[1], p[2])).length())
	_resultat(ecart_max < 0.005 and manquants.is_empty(), "Propulseurs alignés sur le modèle 3D",
		"17 propulseurs comparés au modèle : plus grand écart %.4f m (attendu < 5 mm). Absents du modèle : %s." % [ecart_max, ", ".join(manquants) if manquants.size() else "aucun"])

	# 24. Les ailes se replient à vitesse constante, et les propulseurs des ailes suivent
	v = _nouveau(false)
	v.ouvrir_ailes(false)
	for i in 120:
		v.pas(1.0 / 120.0)
	var a1: float = v.ailes
	for i in 240:
		v.pas(1.0 / 120.0)
	var hauteur_moteurs := 0.0
	for k in 4:
		hauteur_moteurs = maxf(hauteur_moteurs, absf((v.moteurs[k]["position"] as Vector3).y))
	var bout: Vector3 = v.rcs[8]["position"]
	var att24: float = 1.0 - 1.0 / v.DUREE_AILES
	var ok24: bool = absf(a1 - att24) < 0.01 and v.ailes == 0.0 and hauteur_moteurs < 1e-6 and absf(bout.x - 5.95) < 0.005 and absf(bout.y - 0.24) < 0.005
	_resultat(ok24, "Ailes qui se replient",
		"Ouverture après 1 s : %.2f (attendu %.2f), après 3 s : %.2f (attendu 0). Ailes repliées : moteurs d'aile à %.6f m de hauteur (attendu 0), bout d'aile en (%.2f ; %.2f)." % [a1, att24, v.ailes, hauteur_moteurs, bout.x, bout.y])

	# 25. Ailes repliées : plein gaz tout droit sans tourner, et le roulis marche encore (sans déplacement)
	v.commander(1.0, 0.0, 0.0, 0.0)
	for m in v.moteurs:
		m["actuel"] = m["consigne"]
	var e25: Array = v.effet_propulseurs()
	var c_gaz: Vector3 = e25[1]
	var f_gaz: Vector3 = e25[0]
	v.commander(0.0, 0.0, 0.0, 1.0)
	for m in v.moteurs:
		m["actuel"] = m["consigne"]
	var e25b: Array = v.effet_propulseurs()
	var c_roulis: Vector3 = e25b[1]
	var f_roulis: Vector3 = e25b[0]
	var ok25: bool = c_gaz.length() < 1e-3 * v.couple_max.x and -f_gaz.z > 0.99 * v.poussee_avant_max \
		and absf(c_roulis.z - v.couple_max.z) < 0.01 * v.couple_max.z and f_roulis.length() < 1.0 and v.couple_max.z > 60000.0
	_resultat(ok25, "Ailes repliées : poussée et roulis",
		"Plein gaz : %.0f kN, couple parasite %.3f N·m (attendu 0). Roulis : %.0f N·m (ailes ouvertes : environ 70 800), force restante %.3f N (attendu 0)." % [-f_gaz.z / 1000.0, c_gaz.length(), c_roulis.z, f_roulis.length()])

	# 26. Train d'atterrissage à ressorts : posé sur les roues (jambes un peu écrasées), sinon sur le ventre
	v = _nouveau(true)
	v.orientation = Quaternion(Vector3(0, 0, 1), -PI / 2)   # le haut du vaisseau vers l'extérieur de la planète (+X)
	v.sortir_train(true)
	v.train = 1.0       # train déjà sorti avant de toucher le sol
	v.px = R + 1.7
	for i in 120 * 10:
		v.pas(1.0 / 120.0)
	var h_train: float = v.distance_centre() - R
	var g_posé: float = v.acceleration_ressentie.length() / VaisseauPhysique.G0
	var v2 = _nouveau(true)
	v2.orientation = v.orientation
	v2.px = R + 1.05
	for i in 120 * 10:
		v2.pas(1.0 / 120.0)
	var h_ventre: float = v2.distance_centre() - R
	# posé sur le ventre, on demande le train : le sol l'empêche de sortir
	v2.sortir_train(true)
	for i in 480:
		v2.pas(1.0 / 120.0)
	var ok26: bool = v.train == 1.0 and v.au_sol and not v.ecrase and h_train > 1.5 and h_train < 1.58 and absf(g_posé - 1.0) < 0.02 \
		and v2.au_sol and not v2.ecrase and absf(h_ventre - 1.0) < 0.02 and v2.train == 0.0 and v.vitesse() < 0.01
	_resultat(ok26, "Train d'atterrissage (ressorts)",
		"Lâché de 10 cm : train sorti, le centre se pose à %.3f m du sol (roues à 1,6 m, amortisseurs écrasés par le poids), %.2f g ressentis ; train rentré, %.3f m (ventre, attendu 1,0). Écrasé : %s. Posé sur le ventre, le train reste bloqué : %s." % [h_train, g_posé, h_ventre, "oui" if v.ecrase or v2.ecrase else "non", "oui" if v2.train == 0.0 else "NON"])


# =====================================================================
# TEST DU COCKPIT FONCTIONNEL
# =====================================================================
func _test_cockpit() -> void:
	# 27. Chaque commande du cockpit est branchée, et les pièces suivent les commandes
	const Cockpit = preload("res://scripts/cockpit.gd")
	var modele: Node3D = (load("res://modeles/vaisseau/cockpit.glb") as PackedScene).instantiate()
	add_child(modele)   # dans l'arbre, pour pouvoir viser les pièces
	var c = Cockpit.new(modele)
	var connues := {}
	for a in Commandes.ACTIONS:
		connues[a[0]] = true
	var inconnues := PackedStringArray()
	for action in c.boutons.keys() + c.interrupteurs.keys():
		if not connues.has(action):
			inconnues.append(action)
	# gaz à fond, manche tiré et poussé à gauche, train demandé, stabilisateur actif
	c.mettre_a_jour({"gaz": 1.0, "tangage": 1.0, "lacet": 1.0, "roulis": 0.0, "train": 1.0, "ailes": 1.0, "stabilisateur": true}, 1.0)
	var levier_deg: float = rad_to_deg(c.levier_gaz.rotation.x)
	var levier_ok: bool = absf(levier_deg - 30.0) < 0.01
	var manche_ok: bool = absf(rad_to_deg(c.manche.rotation.x) - 15.0) < 0.01 and absf(rad_to_deg(c.manche.rotation.y) - 10.0) < 0.01
	var voyants_gaz := 0
	for k in 8:
		if c.voyant_allume("gaz", (k + 1) / 8.0):
			voyants_gaz += 1
	var interr_ok: bool = absf(c.interrupteurs["train"]["angle"] - c.interrupteurs["train"]["on"]) < 0.01 and c.voyant_allume("train") and c.voyant_allume("stabilisateur")
	# gaz à moitié : 4 voyants sur 8 ; bouton « vue » enfoncé de 4 mm puis relâché
	c.mettre_a_jour({"gaz": 0.5}, 0.01)
	var voyants_moitie := 0
	for k in 8:
		if c.voyant_allume("gaz", (k + 1) / 8.0):
			voyants_moitie += 1
	c.appuyer("vue")
	c.mettre_a_jour({"gaz": 0.5}, 0.01)
	var b: Dictionary = c.boutons["vue"]
	var enfonce: float = ((b["noeud"] as Node3D).position - (b["repos"] as Vector3)).length()
	c.mettre_a_jour({"gaz": 0.5}, 0.5)
	var relache: float = ((b["noeud"] as Node3D).position - (b["repos"] as Vector3)).length()
	# clic de souris : un rayon qui descend sur le bouton « vue » le trouve
	var cible: Vector3 = (b["noeud"] as Node3D).global_position
	var vise: String = c.action_sous_rayon(cible + Vector3(0, 0.3, 0), Vector3.DOWN)
	modele.queue_free()
	var ok27: bool = inconnues.is_empty() and c.boutons.size() >= 12 and c.interrupteurs.size() == 4 and c.pedales.size() == 2 		and levier_ok and manche_ok and voyants_gaz == 8 and voyants_moitie == 4 and interr_ok 		and absf(enfonce - 0.004) < 1e-4 and relache < 1e-6 and vise == "vue"
	_resultat(ok27, "Cockpit fonctionnel",
		"%d boutons, %d interrupteurs, %d pédales ; actions inconnues : %s. Gaz à fond : levier à %.0f°, %d voyants sur 8 ; à moitié : %d. Bouton « vue » enfoncé de %.1f mm puis relâché, trouvé au clic : %s." % [
			c.boutons.size(), c.interrupteurs.size(), c.pedales.size(), ", ".join(inconnues) if inconnues.size() else "aucune",
			levier_deg, voyants_gaz, voyants_moitie, enfonce * 1000.0, vise if vise != "" else "RIEN"])


# =====================================================================
# TEST DU VOL VERTICAL (modèle v17)
# =====================================================================
func _test_vol_vertical() -> void:
	# 28. Passage en vol vertical : les moteurs de levage sortent, la tuyère tourne vers le bas,
	#     et les gaz donnent une poussée vers le haut, équilibrée entre l'avant et l'arrière
	var f := FileAccess.open("res://modeles/vaisseau/positions_tuyeres_godot.json", FileAccess.READ)
	var modele: Dictionary = JSON.parse_string(f.get_as_text())
	var v = _nouveau(false)
	var f_avant: float = v.poussee_avant_max
	v.passer_vol_vertical(true)
	for i in 4.2 * 120:
		v.commander(0.0, 0.0, 0.0, 0.0)
		v.pas(1.0 / 120.0)
	var ecart := 0.0
	for paire in [[4, "moteur central oriente vers le bas"], [5, "moteur levage gauche (sorti)"], [6, "moteur levage droit (sorti)"]]:
		var p: Array = modele[paire[1]]
		ecart = maxf(ecart, ((v.moteurs[paire[0]]["position"] as Vector3) - Vector3(p[0], p[1], p[2])).length())
	var f_max: float = v.poussee_avant_max
	var poids: float = v.masse * 9.81
	v.commander(poids / f_max, 0.0, 0.0, 0.0)
	for m in v.moteurs:
		m["actuel"] = m["consigne"]
	var e: Array = v.effet_propulseurs()
	var force: Vector3 = e[0]
	var couple: Vector3 = e[1]
	var ok_a: bool = v.vertical == 1.0 and absf(v.angle_tuyere() - 90.0) < 1e-6 and ecart < 0.005 		and f_max > 1.1 * poids and f_max < 3.0 * poids and absf(force.y - poids) < 0.01 * poids 		and absf(force.z) < 0.01 * poids and couple.length() < 0.01 * v.couple_max.x
	# 29. Vol stationnaire à 50 m du sol pendant 10 s : on ne monte pas, on ne tombe pas, on ne bascule pas
	var w = _nouveau(true)
	w.px = R + 100000.0
	w.passer_vol_vertical(true)
	for i in 4.2 * 120:
		w.pas(1.0 / 120.0)       # loin du sol, le temps que la séquence se termine
	w.px = R + 50.0
	w.py = 0.0
	w.pz = 0.0
	w.vx = 0.0
	w.vy = 0.0
	w.vz = 0.0
	# le haut du vaisseau (+Y) vers le ciel (+X monde)
	w.orientation = Quaternion(Basis(Vector3(0, -1, 0), Vector3(1, 0, 0), Vector3(0, 0, 1)))
	w.omega = Vector3.ZERO
	var g_loc := GM / ((R + 50.0) * (R + 50.0))
	for i in 1200:
		w.commander(w.masse * g_loc / w.poussee_avant_max, 0.0, 0.0, 0.0)
		w.pas(1.0 / 120.0)
	var haut: Vector3 = Basis(w.orientation) * Vector3.UP
	var bascule := rad_to_deg(acos(clampf(haut.x, -1.0, 1.0)))
	var derive: float = w.distance_centre() - (R + 50.0)
	var ok_b: bool = absf(derive) < 1.0 and bascule < 1.0 and not w.au_sol
	_resultat(ok_a and ok_b, "Vol vertical",
		"Tuyère à %.0f°, sorties à %.4f m du modèle. Poussée vers le haut sans basculer : %.0f kN au plus (vers l'avant : %.0f kN), pour un poids de %.0f kN. Au poids exact : %.1f kN vers le haut, couple %.0f N·m. Vol stationnaire 10 s à 50 m : %+.2f m d'altitude, penché de %.2f°." % [
			v.angle_tuyere(), ecart, f_max / 1000.0, f_avant / 1000.0, poids / 1000.0, force.y / 1000.0, couple.length(), derive, bascule])


func _energie_rotation(v) -> float:
	var w: Vector3 = v.omega
	return 0.5 * (v.inertie.x * w.x * w.x + v.inertie.y * w.y * w.y + v.inertie.z * w.z * w.z)


# =====================================================================
# TESTS DES COMMANDES (clavier et manette)
# =====================================================================
func _mouvement(axe: int, valeur: float) -> InputEventJoypadMotion:
	var m := InputEventJoypadMotion.new()
	m.axis = axe as JoyAxis
	m.axis_value = valeur
	return m


func _tests_commandes() -> void:
	# 16. Disposition par défaut : chaque action a une commande, aucun bouton ne sert deux fois,
	#     et chaque liaison se relit à l'identique
	var c = Commandes.new()
	var vus := {}
	var doublons := PackedStringArray()
	var illisibles := PackedStringArray()
	var sans_rien := PackedStringArray()
	var n_manette := 0
	for nom in c.liaisons:
		var l: Dictionary = c.liaisons[nom]
		if l["clavier"] == "" and l["manette"] == "":
			sans_rien.append(nom)
		if l["manette"] != "":
			n_manette += 1
		for genre in ["clavier", "manette"]:
			var code: String = l[genre]
			if code == "":
				continue
			if vus.has(genre + code):
				doublons.append(Commandes.nom_lisible(code))
			vus[genre + code] = true
			var e := Commandes.evenement_depuis_code(code)
			if e == null or Commandes.code_depuis_evenement(e) != code:
				illisibles.append(code)
	_resultat(doublons.is_empty() and illisibles.is_empty() and sans_rien.is_empty(),
		"Commandes : disposition par défaut",
		"%d actions, %d avec la manette. Doublons : %s. Liaisons illisibles : %s. Actions sans commande : %s." % [
			c.liaisons.size(), n_manette, ", ".join(doublons) if doublons.size() else "aucun",
			", ".join(illisibles) if illisibles.size() else "aucune", ", ".join(sans_rien) if sans_rien.size() else "aucune"])

	# 17. Sticks analogiques : stick à mi-course utile = la moitié de la rotation maximale,
	#     au repos = rien, à fond = le maximum. Et la gâchette R2 à moitié = poussée qui monte 2 fois moins vite.
	c.appliquer()
	var z: float = Commandes.ZONE_MORTE
	var mi := -(z + (1.0 - z) * 0.5)          # stick gauche poussé vers le haut, à mi-course utile
	var s_mi: float = _mouvement(JOY_AXIS_LEFT_Y, mi).get_action_strength("tangage_haut")
	var s_fond: float = _mouvement(JOY_AXIS_LEFT_Y, -1.0).get_action_strength("tangage_haut")
	var s_repos: float = _mouvement(JOY_AXIS_LEFT_Y, -0.05).get_action_strength("tangage_haut")
	var s_autre: float = _mouvement(JOY_AXIS_LEFT_Y, mi).get_action_strength("tangage_bas")
	var s_r2: float = _mouvement(JOY_AXIS_TRIGGER_RIGHT, z + (1.0 - z) * 0.5).get_action_strength("gaz_plus")
	var v = _nouveau(false)
	v.commander(0.0, s_mi, 0.0, 0.0)
	var c_mi: float = v.effet_propulseurs()[1].x
	v.commander(0.0, s_fond, 0.0, 0.0)
	var c_fond: float = v.effet_propulseurs()[1].x
	var ok17: bool = absf(s_mi - 0.5) < 0.001 and absf(s_fond - 1.0) < 0.001 and s_repos == 0.0 and s_autre == 0.0 \
		and absf(s_r2 - 0.5) < 0.001 and absf(c_mi - 0.5 * c_fond) < 0.02 * c_fond
	_resultat(ok17, "Commandes : sticks analogiques",
		"Stick à mi-course : ordre %.2f, couple de tangage %.0f N·m (à fond : %.0f N·m, soit %.0f %%). Au repos (5 %%) : %.2f. Côté opposé : %.2f. R2 à moitié : %.2f." % [
			s_mi, c_mi, c_fond, 100.0 * c_mi / c_fond, s_repos, s_autre, s_r2])

	# 18. Changer une commande, sauvegarder, recharger
	var chemin := "user://essai_commandes.cfg"
	c = Commandes.new()
	var perdu: String = c.assigner("tangage_haut", "clavier", "l:%d" % KEY_Z)   # Z servait à « Plus de poussée »
	c.assigner("lacet_gauche", "manette", "b:%d" % JOY_BUTTON_DPAD_LEFT)   # servait à « Temps moins rapide »
	var ok_sauve: bool = c.sauvegarder(chemin)
	var c2 = Commandes.new()
	var ok_charge: bool = c2.charger(chemin)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(chemin))
	var identiques: bool = JSON.stringify(c.liaisons) == JSON.stringify(c2.liaisons)
	var ok18: bool = ok_sauve and ok_charge and identiques and perdu == "Plus de poussée" \
		and c2.liaisons["gaz_plus"]["clavier"] == "" and c2.liaisons["temps_moins"]["manette"] == "" \
		and c2.liaisons["lacet_gauche"]["manette"] == "b:%d" % JOY_BUTTON_DPAD_LEFT
	_resultat(ok18, "Commandes : changement et sauvegarde",
		"Z donné au tangage (retiré de « %s »), croix directionnelle gauche donnée au lacet. Sauvegarde %s, relecture %s, réglages identiques : %s." % [
			perdu, "réussie" if ok_sauve else "RATÉE", "réussie" if ok_charge else "RATÉE", "oui" if identiques else "NON"])

	# 19. Une sauvegarde de l'ancienne disposition (sans numéro de version) est ignorée,
	#     pour ne pas garder le lacet sur le stick droit qui sert maintenant à tourner la tête
	var ancien := ConfigFile.new()
	ancien.set_value("lacet_gauche", "manette", "a:2:-1")
	ancien.save(chemin)
	var c3 = Commandes.new()
	var charge_ancien: bool = c3.charger(chemin)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(chemin))
	var ok19: bool = not charge_ancien and c3.liaisons["lacet_gauche"]["manette"] == "b:%d" % JOY_BUTTON_LEFT_SHOULDER \
		and c3.liaisons["regard_gauche"]["manette"] == "a:%d:-1" % JOY_AXIS_RIGHT_X \
		and c3.liaisons["roulis_gauche"]["manette"] == "a:%d:-1" % JOY_AXIS_LEFT_X
	_resultat(ok19, "Commandes : nouvelle disposition manette",
		"Stick gauche : tangage + roulis. L1 / R1 : lacet (%s). Stick droit : la tête (%s). Ancienne sauvegarde ignorée : %s." % [
			Commandes.nom_lisible(c3.liaisons["lacet_gauche"]["manette"]), Commandes.nom_lisible(c3.liaisons["regard_gauche"]["manette"]),
			"oui" if not charge_ancien else "NON"])

	# on remet les commandes du joueur (celles de sa sauvegarde) pour le retour au jeu
	c = Commandes.new()
	c.charger()
	c.appliquer()


# =====================================================================
# TESTS : LE SYSTÈME DE LUMIÈRE DANS LE JEU (étape 8)
# =====================================================================
func _tests_lumiere() -> void:
	# 27. Le système de lumière du jeu est une copie exacte de celui du labo
	var labo := "res://labo-lumiere/scripts/lumiere/"
	var differents := PackedStringArray()
	var nb := 0
	var d := DirAccess.open(labo)
	if d != null:
		for f in _fichiers(labo, ""):
			nb += 1
			if FileAccess.get_md5(labo + f) != FileAccess.get_md5("res://scripts/lumiere/" + f):
				differents.append(f)
		for f in _fichiers("res://scripts/lumiere/", ""):
			if not FileAccess.file_exists(labo + f):
				differents.append(f + " (en trop)")
	_resultat(differents.is_empty(), "Lumière : copie exacte du labo",
		("%d fichiers de labo-lumiere/scripts/lumiere identiques dans scripts/lumiere." % nb) if d != null and differents.is_empty()
		else ("Labo absent : rien à comparer." if d == null else "Différents : %s" % ", ".join(differents)))

	# 28. Le sol de la physique suit le relief : posé sur une montagne de 1 234 m.
	# Même posé (même orientation, mêmes ressorts) sur un sol lisse puis sur la montagne : même hauteur.
	var hauteurs := []
	var v
	for montagne in [0.0, 1234.0]:
		v = _nouveau(true)
		var m: float = montagne
		v.relief = func(_x: float, _y: float, _z: float) -> float: return m
		v.orientation = Quaternion(Vector3(0, 0, 1), -PI / 2)   # ventre vers le sol (+X ici)
		v.sortir_train(true)
		v.train = 1.0
		v.px = R + m + 1.61   # juste au-dessus du contact des roues
		for i in 600:
			v.pas(1.0 / 120.0)
		hauteurs.append(v.distance_centre() - R - m)
	var hauteur: float = hauteurs[1]
	var ok28: bool = v.au_sol and not v.ecrase and absf(hauteur - float(hauteurs[0])) < 0.01 and absf(v.altitude() - hauteur) < 0.01 \
		and hauteur > 1.5
	_resultat(ok28, "Lumière : le vaisseau se pose sur le relief dessiné",
		"Sol à 1 234 m : posé %s, centre à %.3f m au-dessus du sol (sol lisse : %.3f m), altitude affichée %.3f m." % [
			"oui" if v.au_sol else "NON", hauteur, float(hauteurs[0]), v.altitude()])

	# 29. La tête bouge avec les G : 3 g de poussée vers l'avant → la tête recule de 4,5 cm, sans trop osciller
	var cible: Vector3 = Jeu.cible_tete_g(Vector3(0.0, 0.0, -3.0 * VaisseauPhysique.G0))
	var pos := Vector3.ZERO
	var vit := Vector3.ZERO
	var depasse := 0.0
	for i in 360:
		var r: Array = Jeu.pas_tete_g(pos, vit, cible, 1.0 / 120.0)
		pos = r[0]
		vit = r[1]
		depasse = maxf(depasse, pos.z - cible.z)
	var max10: Vector3 = Jeu.cible_tete_g(Vector3(0.0, 0.0, -10.0 * VaisseauPhysique.G0))
	var ok29: bool = absf(cible.z - 0.045) < 1e-6 and pos.distance_to(cible) < 0.002 and depasse < 0.2 * cible.z and absf(max10.length() - 0.08) < 1e-6
	_resultat(ok29, "Lumière : la tête suit les forces G",
		"3 g vers l'avant : la tête recule de %.1f cm (au bout de 3 s : %.1f cm, dépassement %.1f mm). À 10 g : %.0f cm au plus." % [
			cible.z * 100.0, pos.z * 100.0, depasse * 1000.0, max10.length() * 100.0])

	# 30-32 : le système complet (partie C++ nécessaire)
	if not ClassDB.class_exists("ArbreLumiere"):
		_resultat(false, "Lumière : partie C++", "La partie C++ (ArbreLumiere) n'est pas chargée.")
		return
	var scene := Node3D.new()
	add_child(scene)
	var cam := Camera3D.new()
	scene.add_child(cam)
	var l = LumiereJeu.new()
	scene.add_child(l)
	var pret: bool = l.preparer(cam, R)
	var s: Vector3 = Vector3(1.0, 0.25, 0.2).normalized()
	var jour := PackedFloat64Array([s.x * (R + 100000.0), s.y * (R + 100000.0), s.z * (R + 100000.0)])
	l.mettre_a_jour(1.0 / 60.0, jour, Vector3.ZERO, Basis.IDENTITY, Vector3.ZERO)
	var e_jour: float = l.eclairement_vaisseau
	var nuit := PackedFloat64Array([-jour[0], -jour[1], -jour[2]])
	l.mettre_a_jour(1.0 / 60.0, nuit, Vector3.ZERO, Basis.IDENTITY, Vector3.ZERO)
	var e_nuit: float = l.eclairement_vaisseau
	var lampe_nuit: bool = l.lampe_cockpit
	var ok30: bool = pret and absf(e_jour - 126573.0) < 0.01 * 126573.0 and e_nuit == 0.0 and lampe_nuit
	_resultat(ok30, "Lumière : le vrai Soleil sur le vaisseau",
		"Côté jour, à 100 km : %d lux (attendu ≈ 126 600). Côté nuit : %d lux, la lampe du cockpit s'allume seule : %s." % [
			roundi(e_jour), roundi(e_nuit), "oui" if lampe_nuit else "NON"])

	# 31. L'œil à 2 m du vrai sol (relief compris), calculé en 64 bits
	var g := Vector3(0.3, 0.8, -0.52).normalized()
	var h: float = l.hauteur_sol(g.x, g.y, g.z)
	var gx := float(g.x)
	var gy := float(g.y)
	var gz := float(g.z)
	var k: float = (R + h + 2.0) / sqrt(gx * gx + gy * gy + gz * gz)   # en 64 bits (g est en 32 bits)
	var sol := PackedFloat64Array([gx * k, gy * k, gz * k])
	l.mettre_a_jour(1.0 / 60.0, sol, Vector3.ZERO, Basis.IDENTITY, Vector3.ZERO)
	var ok31: bool = absf(l.altitude_oeil - 2.0) < 0.001
	_resultat(ok31, "Lumière : altitude de l'œil au-dessus du relief",
		"Relief ici : %.1f m. Œil placé à 2 m du sol : altitude calculée %.4f m." % [h, l.altitude_oeil])

	# 32. Les matières du vaisseau passent au système, et le posemètre voit le cockpit
	var pilote := Node3D.new()
	scene.add_child(pilote)
	var ext: Node3D = (load("res://modeles/vaisseau/vaisseau_exterieur.glb") as PackedScene).instantiate()
	var cpt: Node3D = (load("res://modeles/vaisseau/cockpit.glb") as PackedScene).instantiate()
	pilote.add_child(ext)
	pilote.add_child(cpt)
	var o = Objets.new()
	o.convertir(ext, pilote)
	o.convertir(cpt, pilote)
	var mauvais := 0
	var vitres := 0
	for mi in pilote.find_children("*", "MeshInstance3D", true, false):
		for i in (mi as MeshInstance3D).mesh.get_surface_count():
			var m := (mi as MeshInstance3D).get_surface_override_material(i) as ShaderMaterial
			if m == null or not m.shader.resource_path.begins_with("res://scripts/lumiere/"):
				mauvais += 1
			elif m.shader.resource_path.ends_with("vitre.gdshader"):
				vitres += 1
	var oeil_p := Vector3(0.0, 0.58, 0.38)
	var marqueur := cpt.find_child("Oeil_pilote", true, false) as Node3D
	if marqueur:
		oeil_p = marqueur.position
	var tableau: Dictionary = o.toucher(oeil_p, Vector3(0.0, -0.5, -1.0).normalized())
	var ciel: Dictionary = o.toucher(oeil_p, Vector3(0.0, 1.0, -0.3).normalized())
	var dessous: Dictionary = o.toucher(oeil_p, Vector3.DOWN)
	var ok32: bool = mauvais == 0 and vitres >= 1 and o.nb_faces > 1000 and not tableau.is_empty() and ciel.is_empty() and not dessous.is_empty()
	_resultat(ok32, "Lumière : vaisseau et cockpit dans le système",
		"%d matières à remplacer oubliées, %d vitre(s), %d faces pour le posemètre. Regard vers le tableau de bord : %s ; vers le ciel (à travers la verrière) : %s ; Soleil sous le vaisseau caché par la coque : %s." % [
			mauvais, vitres, o.nb_faces, "touché" if not tableau.is_empty() else "RIEN",
			"libre" if ciel.is_empty() else "BLOQUÉ", "oui" if not dessous.is_empty() else "NON"])

	# 33. Étape 9 : la sonde du cockpit (reflets), remplie par rayons en quelques images, et la visière
	var rf = Reflets.new()
	rf.preparer()
	var t_sonde := Time.get_ticks_usec()
	var n_cases: int = Reflets.LARGEUR_COCKPIT * Reflets.HAUTEUR_COCKPIT
	var n_images := ceili(float(n_cases) / Reflets.RAYONS_PAR_IMAGE)
	for i in n_images:
		rf.mettre_a_jour_cockpit(o, oeil_p, Vector3(0.3, 0.9, -0.3).normalized(), 126600.0, 50.0)
	var ms_sonde := (Time.get_ticks_usec() - t_sonde) / 1000.0 / n_images
	var touches := 0
	for kc in n_cases:
		if rf.image_cockpit.get_pixel(kc % Reflets.LARGEUR_COCKPIT, kc / Reflets.LARGEUR_COCKPIT).a > 0.5:
			touches += 1
	var part_touche := float(touches) / n_cases
	var l_ck: float = rf.luminance_cockpit()
	l.visiere = 1
	l.mettre_a_jour(1.0 / 60.0, jour, Vector3.ZERO, Basis.IDENTITY, Vector3.ZERO)
	var voile_claire: float = l.reflet_visiere.y
	l.visiere = 2
	l.mettre_a_jour(1.0 / 60.0, jour, Vector3.ZERO, Basis.IDENTITY, Vector3.ZERO)
	var voile_or: Vector3 = l.reflet_visiere
	l.visiere = 0
	l.mettre_a_jour(1.0 / 60.0, jour, Vector3.ZERO, Basis.IDENTITY, Vector3.ZERO)
	var voile_sans: float = l.reflet_visiere.length()
	var ok33: bool = rf.cases_faites == n_cases and part_touche > 0.2 and part_touche < 0.95 and l_ck > 1.0 \
		and voile_claire > 0.0 and voile_sans == 0.0 and voile_or.x > voile_or.z and ms_sonde < 4.0
	_resultat(ok33, "Lumière : reflets (sonde du cockpit et visière)",
		"Sonde remplie en %d images (%.2f ms par image) : %d %% des directions touchent le cockpit, le reste passe par la verrière ; luminance moyenne %.0f cd/m². Voile de la visière au Soleil : claire %.0f cd/m², solaire (or) %.0f rouge / %.0f bleu, sans casque %.0f." % [
			n_images, ms_sonde, roundi(part_touche * 100.0), l_ck, voile_claire, voile_or.x, voile_or.z, voile_sans])
	o.liberer()
	scene.queue_free()


## Liste des fichiers d'un dossier et de ses sous-dossiers (chemins relatifs).
func _fichiers(base: String, sous: String) -> PackedStringArray:
	var res := PackedStringArray()
	var d := DirAccess.open(base + sous)
	if d == null:
		return res
	for f in d.get_files():
		res.append(sous + f)
	for sd in d.get_directories():
		res.append_array(_fichiers(base, sous + sd + "/"))
	return res
# TESTS : ORDINATEUR DE BORD (pilote automatique, étape 1)
# =====================================================================
## Une image du jeu avec le pilote auto : il calcule ses ordres, le vaisseau les exécute.
func _image_pilote(v, p, acc: int) -> void:
	# comme dans le jeu : le pilote limite l'accélération du temps quand c'est dangereux, et calcule
	# ses ordres par petits morceaux de temps (au plus periode_controle), même en temps accéléré
	var a: int = mini(acc, p.limite_temps(v))
	var duree: float = a / 120.0
	var n: int = maxi(1, ceili(duree / p.periode_controle(v)))
	for i in n:
		p.calculer(v, duree / n)
		v.commander(p.gaz, p.ordres.x, p.ordres.y, p.ordres.z, p.force_cote)
		v.pas(duree / n)


func _ecart_angle(a: Quaternion, b: Quaternion) -> float:
	return rad_to_deg(a.angle_to(b))


func _tests_pilote_auto() -> void:
	# 27. Commande « pousser de côté » : les petits propulseurs donnent la force sans tourner
	var v = _nouveau(false)
	v.commander(0.0, 0.0, 0.0, 0.0, Vector3(8000.0, 20000.0, 0.0))
	var e: Array = v.effet_propulseurs()
	var f: Vector3 = e[0]
	var c: Vector3 = e[1]
	var ok: bool = absf(f.x - 8000.0) < 400.0 and absf(f.y - 20000.0) < 1000.0 and c.length() < 0.05 * v.couple_max.x
	_resultat(ok, "Commande de côté (pour le pilote auto)",
		"Demandé 8 kN à droite et 20 kN vers le haut : obtenu %.1f kN et %.1f kN, rotation parasite %.0f N·m (%.1f %% du maximum, le pilote auto la corrige)." % [f.x / 1000.0, f.y / 1000.0, c.length(), 100.0 * c.length() / v.couple_max.x])

	# 28. Garder le cap : le vaisseau tourne vite dans tous les sens, le pilote revient à la
	#     direction gardée et s'y arrête, rien qu'avec les propulseurs
	v = _nouveau(false)
	var p = PiloteAuto.new()
	p.activer(PiloteAuto.CAP, v)
	var garde: Quaternion = v.orientation
	v.omega = Vector3(0.3, -0.25, 0.6)
	for i in 120 * 60:
		_image_pilote(v, p, 1)
	var ecart: float = _ecart_angle(v.orientation, garde)
	_resultat(ecart < 0.2 and v.omega.length() < 1e-3,
		"Pilote auto : garder le cap",
		"Lancé en rotation à %.0f°/s : après 60 s, écart %.3f° avec le cap gardé, rotation %.4f°/s." % [rad_to_deg(Vector3(0.3, -0.25, 0.6).length()), ecart, rad_to_deg(v.omega.length())])

	# 29. Garder le cap en orbite pendant 20 minutes (le gradient de gravité tire dessus),
	#     en temps accéléré x10
	v = _nouveau(true)
	v.placer_en_orbite(100000.0)
	p = PiloteAuto.new()
	p.activer(PiloteAuto.CAP, v)
	garde = v.orientation
	var pire := 0.0
	for i in 12 * 60 * 20:
		_image_pilote(v, p, 10)
		pire = maxf(pire, _ecart_angle(v.orientation, garde))
	_resultat(pire < 0.5 and _valide(v), "Pilote auto : garder le cap en orbite (x10)",
		"20 min en orbite à 100 km : plus grand écart %.3f° (attendu < 0,5°)." % pire)

	# 30. S'arrêter dans le vide : vitesse et orientation au hasard au départ
	var hasard := RandomNumberGenerator.new()
	hasard.seed = 7
	var pire_v := 0.0
	var pire_t := 0.0
	var pire_g := 0.0
	for essai in 5:
		v = _nouveau(false)
		v.vx = hasard.randf_range(-300.0, 300.0)
		v.vy = hasard.randf_range(-300.0, 300.0)
		v.vz = hasard.randf_range(-300.0, 300.0)
		v.orientation = Quaternion(Vector3(hasard.randf(), hasard.randf(), hasard.randf()).normalized(), hasard.randf_range(0.0, TAU))
		p = PiloteAuto.new()
		p.activer(PiloteAuto.ARRET, v)
		var t := 0.0
		while t < 300.0 and not p.arrete:
			_image_pilote(v, p, 1)
			t += 1.0 / 120.0
			pire_g = maxf(pire_g, v.acceleration_ressentie.length() / VaisseauPhysique.G0)
		pire_v = maxf(pire_v, v.vitesse())
		pire_t = maxf(pire_t, t)
	_resultat(pire_v < 0.11 and pire_g < 3.05, "Pilote auto : s'arrêter dans le vide",
		"5 départs au hasard (jusqu'à 520 m/s) : arrêté en %.0f s au plus, vitesse restante %.3f m/s, au plus %.2f g ressentis (limite 3 g)." % [pire_t, pire_v, pire_g])

	# 31. S'arrêter près de la planète : le vaisseau finit en vol stationnaire, sans tomber
	v = _nouveau(true)
	v.px = 0.0
	v.py = R + 5000.0
	v.pz = 0.0
	v.vx = 150.0
	v.vy = -60.0
	p = PiloteAuto.new()
	p.activer(PiloteAuto.ARRET, v)
	var alt_min := INF
	for i in 120 * 180:
		_image_pilote(v, p, 1)
		alt_min = minf(alt_min, v.altitude())
	var alt_fin: float = v.altitude()
	for i in 120 * 20:
		_image_pilote(v, p, 1)
	var derive: float = absf(v.altitude() - alt_fin)
	_resultat(v.vitesse() < 0.1 and alt_min > 3000.0 and derive < 1.0 and not v.au_sol,
		"Pilote auto : s'arrêter près de la planète",
		"Parti à 5 km d'altitude à 160 m/s : plus bas %.0f m, puis immobile (%.3f m/s, %.2f m de dérive en 20 s) sur ses moteurs." % [alt_min, v.vitesse(), derive])

	# 32. S'arrêter en vol vertical : le vaisseau finit immobile, à plat (ventre vers le sol)
	v = _nouveau(false)
	v.passer_vol_vertical(true)
	for i in 120 * 5:          # loin de tout, le temps que la séquence de vol vertical se termine
		v.pas(1.0 / 120.0)
	v.gm = GM
	v.rayon_planete = R
	v.px = 0.0
	v.py = R + 2000.0
	v.pz = 0.0
	v.vx = 40.0
	v.vy = -20.0
	v.vz = 0.0
	p = PiloteAuto.new()
	p.activer(PiloteAuto.ARRET, v)
	alt_min = INF
	for i in 120 * 120:
		_image_pilote(v, p, 1)
		alt_min = minf(alt_min, v.altitude())
	var haut_vaisseau: Vector3 = Basis(v.orientation).y
	var vertical_local := Vector3(v.px, v.py, v.pz).normalized()
	var inclinaison := rad_to_deg(haut_vaisseau.angle_to(vertical_local))
	_resultat(v.vitesse() < 0.1 and inclinaison < 3.0 and alt_min > 1000.0 and not v.au_sol,
		"Pilote auto : s'arrêter en vol vertical",
		"Parti à 2 km à 45 m/s, moteurs de levage sortis : plus bas %.0f m, puis immobile (%.3f m/s), à plat (inclinaison %.1f°)." % [alt_min, v.vitesse(), inclinaison])

	# 33. S'arrêter près du sol : il freine la descente à temps et ne touche jamais le sol
	v = _nouveau(false)
	v.passer_vol_vertical(true)
	for i in 120 * 5:
		v.pas(1.0 / 120.0)
	v.gm = GM
	v.rayon_planete = R
	v.px = 0.0
	v.py = R + 250.0
	v.pz = 0.0
	v.vx = 10.0
	v.vy = -15.0
	v.vz = 0.0
	p = PiloteAuto.new()
	p.activer(PiloteAuto.ARRET, v)
	alt_min = INF
	for i in 120 * 60:
		_image_pilote(v, p, 1)
		alt_min = minf(alt_min, v.altitude())
	_resultat(alt_min > 30.0 and not v.au_sol and v.vitesse() < 0.1,
		"Pilote auto : s'arrêter près du sol",
		"Parti à 250 m en descendant à 15 m/s (vol vertical) : plus bas %.0f m (le sol n'est jamais touché), puis immobile (%.3f m/s)." % [alt_min, v.vitesse()])

	# 33 bis. S'arrêter en vol normal, à plat (problème vu en jeu le 16/11 : le vaisseau se cabrait
	# nez en haut et touchait le sol). L'ordinateur passe lui-même en vol vertical et reste à plat.
	var cas_plat := [[500.0, 30.0, -5.0], [200.0, 10.0, 0.0], [800.0, 0.0, -40.0]]
	var bilan_plat := PackedStringArray()
	var tout_bon := true
	for cp in cas_plat:
		v = _nouveau(true)
		v.orientation = Quaternion.IDENTITY      # à plat, nez à l'horizontale
		v.omega = Vector3.ZERO
		v.px = 0.0
		v.py = R + float(cp[0])
		v.pz = 0.0
		v.vx = 0.0
		v.vy = float(cp[2])
		v.vz = -float(cp[1])
		p = PiloteAuto.new()
		p.activer(PiloteAuto.ARRET, v)
		alt_min = INF
		for i in 120 * 60:
			_image_pilote(v, p, 1)
			alt_min = minf(alt_min, v.altitude())
		var penche := rad_to_deg(Basis(v.orientation).y.angle_to(Vector3(v.px, v.py, v.pz).normalized()))
		var bon: bool = v.vitesse() < 0.1 and penche < 3.0 and v.vertical >= 1.0 and not v.au_sol and not v.ecrase
		tout_bon = tout_bon and bon
		bilan_plat.append("%.0f m à %.0f m/s : plus bas %.0f m, %.2f m/s, penché %.1f°" % [cp[0], Vector2(cp[1], cp[2]).length(), alt_min, v.vitesse(), penche])
	_resultat(tout_bon, "Pilote auto : s'arrêter à plat depuis le vol normal",
		"En vol vertical tout seul, à plat, sans toucher le sol. " + " ; ".join(bilan_plat) + ".")

	# 33 ter. Atterrissage automatique (touche L) : il s'arrête à plat, sort le train, descend et se
	# pose doucement, sans jamais piquer du nez (problème vu en jeu le 16/11 avec la touche N)
	var cas_att := [[1000.0, 40.0, -5.0], [150.0, 0.0, 0.0]]
	var bilan_att := PackedStringArray()
	var att_bon := true
	for ca in cas_att:
		v = _nouveau(true)
		v.reactivite_moteurs = 0.3
		v.orientation = Quaternion.IDENTITY
		v.px = 0.0
		v.py = R + float(ca[0])
		v.pz = 0.0
		v.vz = -float(ca[1])
		v.vy = float(ca[2])
		p = PiloteAuto.new()
		p.activer(PiloteAuto.ATTERRIR, v)
		var v_touche := 0.0
		var pique := 0.0
		for i in 120 * 200:
			var vit_avant: float = v.vitesse()
			_image_pilote(v, p, 1)
			if v.vertical > 0.0:
				pique = minf(pique, rad_to_deg(asin(clampf((-Basis(v.orientation).z).dot(Vector3(v.px, v.py, v.pz).normalized()), -1.0, 1.0))))
			if v.au_sol and v_touche == 0.0:
				v_touche = vit_avant
			if v.au_sol and v.vitesse() < 0.05:
				break
		var penche_a := rad_to_deg(Basis(v.orientation).y.angle_to(Vector3(v.px, v.py, v.pz).normalized()))
		var bon_a: bool = v.au_sol and not v.ecrase and v_touche < 2.0 and penche_a < 3.0 and pique > -3.0
		att_bon = att_bon and bon_a
		bilan_att.append("%.0f m à %.0f m/s : touché à %.2f m/s, penché %.1f°, nez au plus bas %.1f°" % [ca[0], Vector2(ca[1], ca[2]).length(), v_touche, penche_a, pique])
	_resultat(att_bon, "Pilote auto : atterrir",
		"Arrêt à plat, train sorti, posé sous 2 m/s. " + " ; ".join(bilan_att) + ".")

	# 33 quater. S'arrêter sans se retourner : à 250 m/s, à plat, le vaisseau passe en vol vertical et se
	# penche nez en haut ; il ne fait jamais demi-tour (le dessus du vaisseau ne dépasse pas 100° de la verticale)
	v = _nouveau(true)
	v.reactivite_moteurs = 0.3
	v.px = 0.0
	v.py = R + 2000.0
	v.pz = 0.0
	v.vz = -250.0
	p = PiloteAuto.new()
	p.activer(PiloteAuto.ARRET, v)
	var pire_incl := 0.0
	var t_arret := -1.0
	alt_min = INF
	for i in 120 * 80:
		_image_pilote(v, p, 1)
		var haut_q := Vector3(v.px, v.py, v.pz).normalized()
		pire_incl = maxf(pire_incl, rad_to_deg((Basis(v.orientation) * Vector3.UP).angle_to(haut_q)))
		alt_min = minf(alt_min, v.altitude())
		if t_arret < 0.0 and p.arrete and v.vitesse() < 0.1:
			t_arret = float(i) / 120.0
			break
	_resultat(t_arret > 0.0 and t_arret < 40.0 and pire_incl < 100.0 and alt_min > 1500.0 and not v.ecrase,
		"Pilote auto : s'arrêter sans se retourner",
		"2 km, 250 m/s : arrêté en %.0f s (moins de 40 s), le dessus du vaisseau penché au plus de %.0f° (jamais retourné), plus bas %.0f m." % [t_arret, pire_incl, alt_min])

	# 33 quinquies. La gravité freine la montée : le vaisseau monte à 100 m/s, le pilote ne pousse pas
	# contre la montée (la gravité s'en charge) : il monte autant que s'il tombait en chute libre (≈ 510 m)
	v = _nouveau(true)
	v.reactivite_moteurs = 0.3
	v.px = 0.0
	v.py = R + 10000.0
	v.pz = 0.0
	v.vy = 100.0
	p = PiloteAuto.new()
	p.activer(PiloteAuto.ARRET, v)
	var haut_max := v.altitude()
	var t_montee := -1.0
	for i in 120 * 25:
		_image_pilote(v, p, 1)
		haut_max = maxf(haut_max, v.altitude())
		if p.arrete and v.vitesse() < 0.1:
			t_montee = float(i) / 120.0
			break
	var monte := haut_max - 10000.0
	_resultat(monte > 440.0 and monte < 560.0 and t_montee > 0.0 and not v.ecrase,
		"Pilote auto : la gravité freine la montée",
		"Montée à 100 m/s : il est monté de %.0f m (en chute libre : 510 m, donc la poussée n'a presque pas freiné la montée), puis arrêté en %.0f s." % [monte, t_montee])

	# 33 sexies. Temps accéléré : à x100 et x1000 demandés, le pilote garde le contrôle (il limite lui-même
	# l'accélération du temps près du sol) : ni écrasé, ni perdu
	var bilan_acc := PackedStringArray()
	var acc_bon := true
	for cas_acc in [["s'arrêter", PiloteAuto.ARRET, 3000.0, 100.0, -20.0, 1000], ["atterrir", PiloteAuto.ATTERRIR, 3000.0, 60.0, -10.0, 1000], ["atterrir", PiloteAuto.ATTERRIR, 20000.0, 300.0, -20.0, 100]]:
		v = _nouveau(true)
		v.reactivite_moteurs = 0.3
		v.px = 0.0
		v.py = R + float(cas_acc[2])
		v.pz = 0.0
		v.vz = -float(cas_acc[3])
		v.vy = float(cas_acc[4])
		p = PiloteAuto.new()
		p.activer(int(cas_acc[1]), v)
		var t_acc := 0.0
		var fini := false
		var impact_acc := 0.0
		alt_min = INF
		for i in 6000:
			var a_eff: int = mini(int(cas_acc[5]), p.limite_temps(v))
			_image_pilote(v, p, int(cas_acc[5]))
			t_acc += a_eff / 120.0
			alt_min = minf(alt_min, v.altitude())
			if v.ecrase:
				break
			if int(cas_acc[1]) == PiloteAuto.ARRET and p.arrete and v.vitesse() < 0.1:
				fini = true
				break
			if int(cas_acc[1]) == PiloteAuto.ATTERRIR and v.au_sol and v.vitesse() < 0.1:
				fini = true
				impact_acc = v.vitesse_impact
				break
		var bon_acc: bool = fini and not v.ecrase and impact_acc < 2.0
		acc_bon = acc_bon and bon_acc
		bilan_acc.append("%s depuis %.0f m à x%d : %s en %.0f s de jeu (impact %.1f m/s)" % [cas_acc[0], cas_acc[2], cas_acc[5], "réussi" if bon_acc else "RATÉ", t_acc, impact_acc])
	_resultat(acc_bon, "Pilote auto : temps accéléré (x100, x1000)", " ; ".join(bilan_acc) + ".")

	# 33 septies. Urgence : le vaisseau tombe vite, trop près du sol pour le vol vertical : il utilise les
	# gros moteurs, nez en haut, puis revient à plat. Il ne s'écrase pas.
	var bilan_urg := PackedStringArray()
	var urg_bon := true
	for cas_urg in [[1000.0, 0.0, -100.0], [300.0, 20.0, -30.0], [150.0, 0.0, -10.0]]:
		v = _nouveau(true)
		v.reactivite_moteurs = 0.3
		v.px = 0.0
		v.py = R + float(cas_urg[0])
		v.pz = 0.0
		v.vz = -float(cas_urg[1])
		v.vy = float(cas_urg[2])
		p = PiloteAuto.new()
		p.activer(PiloteAuto.ARRET, v)
		alt_min = INF
		var arret_urg := false
		for i in 120 * 90:
			_image_pilote(v, p, 1)
			alt_min = minf(alt_min, v.altitude())
			if v.ecrase or v.au_sol:
				break
			if p.arrete and v.vitesse() < 0.1 and not p.urgence:
				arret_urg = true
				break
		var bon_urg: bool = arret_urg and not v.ecrase and alt_min > 30.0
		urg_bon = urg_bon and bon_urg
		bilan_urg.append("%.0f m, descend à %.0f m/s : %s, plus bas %.0f m" % [cas_urg[0], -float(cas_urg[2]), "arrêté" if bon_urg else "RATÉ", alt_min])
	_resultat(urg_bon, "Pilote auto : urgence près du sol", " ; ".join(bilan_urg) + ".")

	_tests_train_ressorts()


func _tests_train_ressorts() -> void:
	# 34. Posés à différentes vitesses : les ressorts absorbent les posés normaux, un choc trop fort casse
	var lignes := PackedStringArray()
	var attendu_ok := true
	for cas in [[1.0, true, false], [2.0, true, false], [3.0, true, false], [4.0, true, false], [5.0, true, true], [6.0, true, true], [8.0, true, true], [2.0, false, false], [5.0, false, true]]:
		var v = _nouveau(true)
		v.orientation = Quaternion(Vector3(0, 0, 1), -PI / 2)
		if cas[1]:
			v.sortir_train(true)
			v.train = 1.0
		v.px = R + (1.61 if cas[1] else 1.01)   # juste avant le contact
		v.vx = -float(cas[0])
		var acc_max := 0.0
		for i in 120 * 8:
			v.pas(1.0 / 120.0)
			acc_max = maxf(acc_max, v.acceleration_ressentie.length() / VaisseauPhysique.G0)
			if v.ecrase:
				break
		if v.ecrase != cas[2]:
			attendu_ok = false
		lignes.append("%s à %.0f m/s : %s (pic %.1f g)" % ["roues" if cas[1] else "ventre", cas[0], "écrasé" if v.ecrase else "posé", acc_max])
	_resultat(attendu_ok, "Posés plus ou moins durs",
		"; ".join(lignes) + ". Attendu : posés sur les roues jusqu'à 4 m/s (amortisseurs de 12 à 15 cm), sur le ventre jusqu'à 2 m/s, casse au-delà.")

	# 35. Temps accéléré x1000 posé au sol : le calcul est découpé, le vaisseau reste posé et calme
	var w = _nouveau(true)
	w.orientation = Quaternion(Vector3(0, 0, 1), -PI / 2)
	w.sortir_train(true)
	w.train = 1.0
	w.px = R + 1.6
	for i in 240:
		w.pas(1.0 / 120.0)
	for i in 30:
		w.pas(1000.0 / 120.0)
	var h_w: float = w.distance_centre() - R
	_resultat(_valide(w) and w.au_sol and not w.ecrase and w.vitesse() < 0.05 and h_w > 1.5 and h_w < 1.58,
		"Posé en temps accéléré x1000",
		"Après 250 s en x1000 : %.3f m du sol, vitesse %.4f m/s, écrasé : %s." % [h_w, w.vitesse(), "oui" if w.ecrase else "non"])
	_tests_pente()


## Un vaisseau posé (train sorti) sur un sol en pente : angle en degrés, sens « avant » (nez vers le
## haut de la pente) ou « cote » (pente de côté). Renvoie le vaisseau après duree s.
func _pose_sur_pente(angle_deg: float, sens: String, duree: float, omega_p := 0.0):
	var v = _nouveau(true)
	var t := tan(deg_to_rad(angle_deg))
	if sens == "avant":
		v.relief = func(x: float, _y: float, z: float) -> float: return t * R * z / x
	else:
		v.relief = func(x: float, y: float, _z: float) -> float: return t * R * y / x
	v.omega_planete = omega_p
	v.orientation = Quaternion(Vector3(0, 0, 1), -PI / 2)
	v.sortir_train(true)
	v.train = 1.0
	v.px = R + 1.75
	if omega_p != 0.0:
		v.vz = -omega_p * v.px   # posé : il tourne avec le sol
	v.set_meta("depart", Vector3(v.px, v.py, v.pz))
	for i in int(duree * 120.0):
		v.pas(1.0 / 120.0)
	return v


func _tests_pente() -> void:
	# 36. Pente de 12° nez vers le haut, 2° de côté : le frottement tient le vaisseau immobile ;
	#     le sol pousse perpendiculairement à la pente, et le total des forces du sol compense le poids.
	#     De côté, le train arrière n'a que 84 cm de large, ses ressorts sont souples, et le centre de
	#     gravité est à 1,55 m du sol : le vaisseau penche deux fois plus que la pente, et dès 3,5° de
	#     côté il se couche sur le flanc (test 37).
	var lignes := PackedStringArray()
	var ok := true
	for sens in ["avant", "cote"]:
		var v = _pose_sur_pente(12.0 if sens == "avant" else 2.0, sens, 25.0)
		var p1 := Vector3(v.px, v.py, v.pz)
		for i in 120 * 5:
			v.pas(1.0 / 120.0)
		var glisse := (Vector3(v.px, v.py, v.pz) - p1).length()
		var ressenti: float = v.acceleration_ressentie.length()
		var bon: bool = _valide(v) and v.au_sol and not v.ecrase and glisse < 0.005 and v.vitesse() < 0.002 \
			and absf(ressenti - 9.81) < 0.05
		ok = ok and bon
		lignes.append("%s : glisse %.4f m en 5 s, vitesse %.4f m/s, sol %.2f m/s² (poids 9,81)" % [
			"12° nez vers le haut" if sens == "avant" else "2° de côté", glisse, v.vitesse(), ressenti])
	_resultat(ok, "Posé sur une pente", "; ".join(lignes) + ". Attendu : immobile (frottement 0,5 > tan 12° = 0,21).")

	# 37. Trop de pente : 35° nez vers le haut (tan 35° = 0,70 > frottement 0,5), il glisse ;
	#     4° de côté, il se couche sur le flanc (sans glisser ni exploser : le calcul reste propre).
	var w = _pose_sur_pente(35.0, "avant", 6.0)
	var depart: Vector3 = w.get_meta("depart")
	var parcouru := (Vector3(w.px, w.py, w.pz) - depart).length()
	var c = _pose_sur_pente(4.0, "cote", 20.0)
	var haut_c: Vector3 = Basis(c.orientation).y
	var couche := haut_c.dot(Vector3(1, 0, 0)) < 0.5
	_resultat(_valide(w) and _valide(c) and parcouru > 3.0 and couche, "Une pente trop forte : il glisse ou se couche",
		"35° nez vers le haut : %.1f m parcourus en 6 s (il glisse). 4° de côté : penché de %.0f° (il se couche sur le flanc)." % [
			parcouru, rad_to_deg(acos(clampf(haut_c.dot(Vector3(1, 0, 0)), -1.0, 1.0)))])

	# 38. Le sol tourne avec la planète (jour de 2 h) : posé, le vaisseau tourne avec lui, sans glisser
	#     par rapport au sol. Sa vitesse dans l'espace = celle du sol (ω × r).
	var om := TAU / 7200.0
	var u = _pose_sur_pente(0.0, "avant", 20.0, om)
	var v_sol := Vector3(om * u.pz, 0.0, -om * u.px)
	var relative := (Vector3(u.vx, u.vy, u.vz) - v_sol).length()
	_resultat(_valide(u) and u.au_sol and not u.ecrase and relative < 0.01,
		"Posé sur une planète qui tourne",
		"Sol à %.1f m/s (jour de 2 h, à l'équateur) ; vaisseau à %.1f m/s dans l'espace, %.4f m/s par rapport au sol (attendu ≈ 0)." % [
			v_sol.length(), u.vitesse(), relative])


# =====================================================================
# TESTS DU MODÈLE v25 : VRAIES MASSES, BUSES ENCASTRÉES, DROÏDE
# =====================================================================
func _tests_v25() -> void:
	var v = _nouveau(false)
	# a. masse, centre de gravité et inertie = ceux calculés dans Blender (masses_godot.json)
	var f := FileAccess.open("res://modeles/vaisseau/masses_godot.json", FileAccess.READ)
	var j = JSON.parse_string(f.get_as_text()) if f != null else null
	var ok_a := false
	var det_a := "fichier masses_godot.json illisible"
	if j is Dictionary:
		var cg: Array = j["centre_gravite_godot_m"]
		var ip: Dictionary = j["inertie_principale_godot_kg_m2"]
		var e_cg: float = (v.CENTRE_GRAVITE - Vector3(cg[0], cg[1], cg[2])).length()
		var e_i: float = (v.inertie - Vector3(ip["x_tangage"], ip["y_lacet"], ip["z_roulis"])).length()
		ok_a = absf(v.masse - float(j["masse_totale_kg"])) < 1.0 and e_cg < 0.005 and e_i < 10.0
		det_a = "Masse %.1f kg (modèle %.1f), centre de gravité à %.3f m derrière l'origine (écart %.4f m), inertie écart %.1f kg·m²." % [v.masse, float(j["masse_totale_kg"]), v.CENTRE_GRAVITE.z, e_cg, e_i]
	_resultat(ok_a, "Vraies masses du modèle", det_a)

	# b. plein gaz vers l'avant : les moteurs sont alignés avec le centre de gravité, aucune rotation
	v = _nouveau(false)
	v.commander(1.0, 0.0, 0.0, 0.0)
	for i in 240:
		v.commander(1.0, 0.0, 0.0, 0.0)
		v.pas(1.0 / 120.0)
	_resultat(v.omega.length() < 1e-3, "Plein gaz autour du vrai centre de gravité",
		"2 s plein gaz : %.0f m/s, rotation %.6f rad/s (attendu ≈ 0). Accélération %.1f g (8,46 t)." % [v.vitesse(), v.omega.length(), v.poussee_avant_max / v.masse / 9.80665])

	# c. les 10 buses sont exactement là où le modèle les dessine, et poussent dans le même sens
	var scene := load("res://modeles/vaisseau/vaisseau_exterieur.glb") as PackedScene
	var ecart := INF
	var ecart_dir := INF
	var trouvees := 0
	if scene != null:
		var m := scene.instantiate()
		ecart = 0.0
		ecart_dir = 0.0
		for t in v.rcs:
			if int(t["axe"]) >= 0:
				continue
			var n := m.find_child("Point_rcs_" + String(t["nom"]).replace(" ", "_"), true, false) as Node3D
			if n == null:
				continue
			trouvees += 1
			var e = n.get_meta("extras", {})
			var d: Array = e.get("poussee_godot", [0, 0, 0]) if e is Dictionary else [0, 0, 0]
			ecart = maxf(ecart, ((t["position"] as Vector3) - n.position).length())
			ecart_dir = maxf(ecart_dir, ((t["direction"] as Vector3) - Vector3(d[0], d[1], d[2]).normalized()).length())
		var droide_ok: bool = m.find_child("Point_droide", true, false) != null and load("res://modeles/vaisseau/droide.glb") != null
		m.free()
		_resultat(trouvees == 10 and ecart < 0.005 and ecart_dir < 0.01 and droide_ok, "Buses encastrées et droïde",
			"%d buses sur 10 trouvées dans le modèle, écart de position %.4f m, de direction %.4f. Logement et modèle du droïde : %s." % [trouvees, ecart, ecart_dir, "trouvés" if droide_ok else "ABSENTS"])
	else:
		_resultat(false, "Buses encastrées et droïde", "modèle extérieur introuvable")

	# d. freiner sans se retourner : les buses du nez poussent vers l'arrière, sans faire tourner
	v = _nouveau(false)
	v.vz = -10.0   # 10 m/s vers l'avant
	var frein := Vector3(0, 0, 12000.0)
	for i in 600:
		v.commander(0.0, 0.0, 0.0, 0.0, frein)
		v.pas(1.0 / 120.0)
	var att_d: float = 10.0 - 12000.0 / v.masse * 5.0
	var ok_d: bool = absf(-v.vz - att_d) < 0.05 and v.omega.length() < 2e-3 and absf(v.vx) < 0.05 and absf(v.vy) < 0.05
	_resultat(ok_d, "Freinage par les buses du nez",
		"Freiné 5 s à 12 kN : %.3f m/s restants (attendu %.3f), rotation %.5f rad/s, dérive de côté %.3f m/s (attendu ≈ 0)." % [-v.vz, att_d, v.omega.length(), Vector2(v.vx, v.vy).length()])
