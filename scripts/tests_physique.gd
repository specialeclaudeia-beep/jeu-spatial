extends Control
## Tests automatiques de la physique (touche F1 dans le jeu, Échap pour revenir).
## Chaque test vérifie une loi physique sur le vrai code du vaisseau.

const VaisseauPhysique = preload("res://scripts/physique/vaisseau_physique.gd")
const Commandes = preload("res://scripts/commandes.gd")
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
	# couple = position × force : bras de levier 0,9 m en hauteur et 2,8 m en largeur, pendant 0,2 s
	var f3: float = v.moteurs[1]["poussee_max"]
	var attendu_x: float = -0.9 * f3 * 0.2 / v.inertie.x
	var attendu_y: float = 2.8 * f3 * 0.2 / v.inertie.y
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
	_resultat(absf(v.omega.z - att7) < 0.03 * att7 and v.vitesse() < 1e-6, "Propulseurs d'orientation (roulis)",
		"2 s de roulis : %.3f rad/s (attendu %.3f), vitesse %.9f m/s (attendu 0 : les forces s'annulent)." % [v.omega.z, att7, v.vitesse()])

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

	_tests_commandes()

	var duree := (Time.get_ticks_msec() - debut) / 1000.0
	var couleur := "#5fe08a" if reussis == total else "#ffcc55"
	texte.append_text("[b][color=%s]%d / %d tests réussis[/color][/b]  (%.1f s de calcul)\n" % [couleur, reussis, total, duree])
	print("Tests de physique : %d / %d réussis" % [reussis, total])


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
	c.assigner("lacet_gauche", "manette", "b:%d" % JOY_BUTTON_LEFT_SHOULDER)   # L1 servait à « Temps moins rapide »
	var ok_sauve: bool = c.sauvegarder(chemin)
	var c2 = Commandes.new()
	var ok_charge: bool = c2.charger(chemin)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(chemin))
	var identiques: bool = JSON.stringify(c.liaisons) == JSON.stringify(c2.liaisons)
	var ok18: bool = ok_sauve and ok_charge and identiques and perdu == "Plus de poussée" \
		and c2.liaisons["gaz_plus"]["clavier"] == "" and c2.liaisons["temps_moins"]["manette"] == "" \
		and c2.liaisons["lacet_gauche"]["manette"] == "b:%d" % JOY_BUTTON_LEFT_SHOULDER
	_resultat(ok18, "Commandes : changement et sauvegarde",
		"Z donné au tangage (retiré de « %s »), L1 donné au lacet. Sauvegarde %s, relecture %s, réglages identiques : %s." % [
			perdu, "réussie" if ok_sauve else "RATÉE", "réussie" if ok_charge else "RATÉE", "oui" if identiques else "NON"])

	# on remet les commandes du joueur (celles de sa sauvegarde) pour le retour au jeu
	c = Commandes.new()
	c.charger()
	c.appliquer()
