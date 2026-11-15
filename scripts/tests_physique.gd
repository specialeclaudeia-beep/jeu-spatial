extends Control
## Tests automatiques de la physique (touche F1 dans le jeu, Échap pour revenir).
## Chaque test vérifie une loi physique sur le vrai code du vaisseau.

const VaisseauPhysique = preload("res://scripts/physique/vaisseau_physique.gd")
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
	if e is InputEventKey and e.is_pressed() and (e as InputEventKey).keycode == KEY_ESCAPE:
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


func _lancer() -> void:
	texte.text = "[b]Tests de physique[/b]   (Échap pour revenir au jeu)\n\n"
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
	_resultat(absf(vit - 40.0) < 0.05 and v.omega.length() < 1e-9,
		"Poussée du moteur central",
		"40 kN sur 10 t pendant 10 s : %.3f m/s (attendu 40), rotation %.9f rad/s (attendu 0)." % [vit, v.omega.length()])

	# 3. Poussée décentrée : le moteur haut droit fait aussi tourner (couple = position × force)
	v = _nouveau(false)
	v.moteurs[1]["consigne"] = 1.0
	for i in 120:
		v.pas(1.0 / 120.0)
	var attendu_x := -36000.0 / 133000.0
	var attendu_y := 112000.0 / 160000.0
	var w: Vector3 = v.omega
	var ok3 := absf(w.x - attendu_x) < 0.05 * absf(attendu_x) and absf(w.y - attendu_y) < 0.05 * attendu_y and absf(v.vitesse() - 4.0) < 0.2
	_resultat(ok3, "Poussée décentrée = rotation",
		"Moteur haut droit seul pendant 1 s : tangage %.3f rad/s (≈ %.3f), lacet %.3f rad/s (≈ %.3f), vitesse %.2f m/s (≈ 4). Le nez descend et part à gauche, comme prévu." % [w.x, attendu_x, w.y, attendu_y, v.vitesse()])

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
	var att7 := 1500.0 * 11.0 * 2.0 / 33000.0
	_resultat(absf(v.omega.z - att7) < 0.03 * att7 and v.vitesse() < 1e-9, "Propulseurs d'orientation (roulis)",
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

	var duree := (Time.get_ticks_msec() - debut) / 1000.0
	var couleur := "#5fe08a" if reussis == total else "#ffcc55"
	texte.append_text("[b][color=%s]%d / %d tests réussis[/color][/b]  (%.1f s de calcul)\n" % [couleur, reussis, total, duree])
	print("Tests de physique : %d / %d réussis" % [reussis, total])
