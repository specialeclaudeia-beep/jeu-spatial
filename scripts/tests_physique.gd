extends Control
## Tests automatiques de la physique (touche F1 dans le jeu, Échap pour revenir).
## Chaque test vérifie une loi physique sur le vrai code du vaisseau.

const VaisseauPhysique = preload("res://scripts/physique/vaisseau_physique.gd")
const Commandes = preload("res://scripts/commandes.gd")
const Jeu = preload("res://scripts/jeu.gd")
const LumiereJeu = preload("res://scripts/lumiere_jeu.gd")
const Objets = preload("res://scripts/lumiere/objets.gd")
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

	# 2. Poussée centrée : accélère tout droit, sans tourner
	v = _nouveau(false)
	v.moteurs[4]["consigne"] = 1.0
	for i in 1200:
		v.pas(1.0 / 120.0)
	var vit: float = v.vitesse()
	var f2: float = v.moteurs[4]["poussee_max"]
	var att2: float = f2 / v.masse * 10.0
	_resultat(absf(vit - att2) < 0.002 * att2 and v.omega.length() < 1e-9,
		"Poussée du moteur central",
		"%.0f kN sur %.0f t pendant 10 s : %.3f m/s (attendu %.0f), rotation %.9f rad/s (attendu 0)." % [f2 / 1000.0, v.masse / 1000.0, vit, att2, v.omega.length()])

	# 3. Poussée décentrée : le moteur haut droit fait aussi tourner (couple = position × force)
	v = _nouveau(false)
	v.moteurs[1]["consigne"] = 1.0
	for i in 24:
		v.pas(1.0 / 120.0)
	# couple = position × force : bras de levier = hauteur et largeur du moteur, pendant 0,2 s
	var f3: float = v.moteurs[1]["poussee_max"]
	var pos3: Vector3 = v.moteurs[1]["position"]
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
	var ok25: bool = c_gaz.length() < 1.0 and -f_gaz.z > 0.99 * v.poussee_avant_max \
		and absf(c_roulis.z - v.couple_max.z) < 0.01 * v.couple_max.z and f_roulis.length() < 1.0 and v.couple_max.z > 60000.0
	_resultat(ok25, "Ailes repliées : poussée et roulis",
		"Plein gaz : %.0f kN, couple parasite %.3f N·m (attendu 0). Roulis : %.0f N·m (ailes ouvertes : environ 70 800), force restante %.3f N (attendu 0)." % [-f_gaz.z / 1000.0, c_gaz.length(), c_roulis.z, f_roulis.length()])

	# 26. Train d'atterrissage : posé sur les roues (1,6 m sous le centre), sinon sur le ventre
	v = _nouveau(true)
	v.sortir_train(true)
	v.train = 1.0       # train déjà sorti avant de toucher le sol
	v.px = R + 3.0
	for i in 600:
		v.pas(1.0 / 120.0)
	var h_train: float = v.distance_centre() - R
	var v2 = _nouveau(true)
	v2.px = R + 3.0
	for i in 600:
		v2.pas(1.0 / 120.0)
	var h_ventre: float = v2.distance_centre() - R
	# posé sur le ventre, on demande le train : le sol l'empêche de sortir
	v2.sortir_train(true)
	for i in 480:
		v2.pas(1.0 / 120.0)
	var ok26: bool = v.train == 1.0 and v.au_sol and not v.ecrase and absf(h_train - v.HAUTEUR_TRAIN) < 1e-6 \
		and v2.au_sol and absf(h_ventre - v2.HAUTEUR_VENTRE) < 1e-6 and v2.train == 0.0
	_resultat(ok26, "Train d'atterrissage",
		"Lâché à 3 m : train sorti, le centre reste à %.3f m du sol (roues, attendu 1,6) ; train rentré, %.3f m (ventre, attendu 1,0). Écrasé : %s. Posé sur le ventre, le train reste bloqué : %s." % [h_train, h_ventre, "oui" if v.ecrase else "non", "oui" if v2.train == 0.0 else "NON"])


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

	# 28. Le sol de la physique suit le relief : posé sur une montagne de 1 234 m
	var v = _nouveau(true)
	v.relief = func(_x: float, _y: float, _z: float) -> float: return 1234.0
	v.placer_en_orbite(0.0)
	v.px = R + 1234.0 + v.hauteur_contact() + 0.3
	v.py = 0.0
	v.pz = 0.0
	v.vx = 0.0
	v.vy = 0.0
	v.vz = 0.0
	for i in 600:
		v.pas(1.0 / 120.0)
	var hauteur: float = v.distance_centre() - R - 1234.0
	var ok28: bool = v.au_sol and not v.ecrase and absf(hauteur - v.hauteur_contact()) < 0.01 and absf(v.altitude() - v.hauteur_contact()) < 0.01
	_resultat(ok28, "Lumière : le vaisseau se pose sur le relief dessiné",
		"Sol à 1 234 m : posé %s, centre à %.3f m au-dessus du sol (roues : %.3f m), altitude affichée %.3f m." % [
			"oui" if v.au_sol else "NON", hauteur, v.hauteur_contact(), v.altitude()])

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
