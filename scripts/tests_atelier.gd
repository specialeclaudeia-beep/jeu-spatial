extends Node
## Tests de l'atelier, étape 1 : le PLAN du vaisseau (scripts/atelier/plan.gd), son catalogue de pièces
## (scripts/atelier/catalogue.gd), et la physique construite à partir du plan.
## Étape 2 : l'écran de l'atelier (tableau ingénieur, catalogue, fiches, caméra, choix d'une pièce dans la
## vue 3D), le départ posé au sol devant le hangar, et le passage accueil / atelier / jeu.
## Ligne de commande :
##   Godot_console.exe --headless --path . res://scenes/tests_atelier.tscn
## Les valeurs « d'avant » viennent du code d'avant l'atelier (vaisseau écrit en dur), gardées dans
## outils/plan/ancien_code_v27.json : le vaisseau construit par le plan doit faire la même chose.

const Plan = preload("res://scripts/atelier/plan.gd")
const Catalogue = preload("res://scripts/atelier/catalogue.gd")
const VaisseauPhysique = preload("res://scripts/physique/vaisseau_physique.gd")
const Aerodynamique = preload("res://scripts/physique/aerodynamique.gd")
const ANCIEN := "res://outils/plan/ancien_code_v27.json"
const Analyse = preload("res://scripts/atelier/analyse.gd")
const CameraAtelier = preload("res://scripts/atelier/camera_atelier.gd")
const Partie = preload("res://scripts/partie.gd")
const Atmosphere = preload("res://scripts/physique/atmosphere.gd")
const SCENE_ATELIER := "res://scenes/atelier.tscn"
## Mêmes valeurs que scripts/jeu.gd (le test ne charge pas le jeu, trop lourd)
const RAYON_PLANETE := 600000.0
const GRAVITE_SURFACE := 9.81
const DUREE_JOUR := 7200.0
const LIEU_HANGAR := Vector3(0.3635219, 0.5054473, 0.7825438)
const VERS_SOLEIL := Vector3(1.0, 0.25, 0.2)

## Rôles des 22 petits propulseurs dans l'ancien code (écrits à la main) : [axe, signe]
const ROLES_ANCIENS := {
	"nez bas": [0, 1], "queue haut": [0, 1], "nez haut": [0, -1], "queue bas": [0, -1],
	"nez droit": [1, 1], "queue gauche": [1, 1], "nez gauche": [1, -1], "queue droit": [1, -1],
	"bout aile haut droit": [2, 1], "bout aile bas gauche": [2, 1], "bout aile haut gauche": [2, -1],
	"bout aile bas droit": [2, -1],
}

var reussis := 0
var rates := 0
var ancien := {}


func _ready() -> void:
	var f := FileAccess.open(ANCIEN, FileAccess.READ)
	if f != null:
		var d = JSON.parse_string(f.get_as_text())
		if d is Dictionary:
			ancien = d
	_tests_plan()
	_tests_ensembles()
	_tests_erreurs()
	_tests_vaisseau()
	_tests_pose_au_sol()
	_tests_analyse()
	_tests_camera()
	_tests_partie()
	await _tests_ecran_atelier()
	print("=== Atelier : %d / %d réussis ===" % [reussis, reussis + rates])
	get_tree().quit(0 if rates == 0 else 1)


func _resultat(ok: bool, nom: String, detail: String) -> void:
	if ok:
		reussis += 1
		print("[OK] %s : %s" % [nom, detail])
	else:
		rates += 1
		print("[ÉCHEC] %s : %s" % [nom, detail])


static func _v(a) -> Vector3:
	return Vector3(float(a[0]), float(a[1]), float(a[2]))


# =====================================================================
# 1. LE PLAN DU CHASSEUR
# =====================================================================
func _tests_plan() -> void:
	var p = Plan.new()
	var lu: bool = p.charger(Plan.PLAN_PAR_DEFAUT)
	var compte := {}
	for q in p.pieces:
		compte[q["type"]] = int(compte.get(q["type"], 0)) + 1
	var ok: bool = lu and p.valide() and p.pieces.size() == 128 and compte.get("moteur", 0) == 7 and compte.get("propulseur", 0) == 22 \
		and compte.get("roue", 0) == 3 and compte.get("contact_coque", 0) == 6 and compte.get("surface_air", 0) == 14 \
		and p.articulations.size() == 7
	_resultat(ok, "Le plan du chasseur se lit",
		"%d pièces (%s), %d pièces mobiles, erreurs : %s." % [p.pieces.size(), str(compte), p.articulations.size(),
			"aucune" if p.erreurs.is_empty() else "; ".join(p.erreurs)])

	# masse, centre de gravité, inertie : recalculés à la main (Huygens, en double précision) et comparés
	var mp: Dictionary = p.proprietes_masse()
	var m := 0.0
	var sx := 0.0
	var sy := 0.0
	var sz := 0.0
	for q in p.pieces:
		var mi := float(q.get("masse_kg", 0.0))
		if q["type"] in ["structure", "masse"]:
			m += mi
			var c := _v(q["centre"])
			sx += mi * c.x
			sy += mi * c.y
			sz += mi * c.z
	var g := Vector3(sx / m, sy / m, sz / m)
	var izz := 0.0
	for q in p.pieces:
		if q["type"] in ["structure", "masse"]:
			var c := _v(q["centre"]) - g
			var propre: Array = q.get("inertie_propre", [0, 0, 0, 0, 0, 0])
			izz += float(propre[2]) + float(q["masse_kg"]) * (c.x * c.x + c.y * c.y)
	var ib: Basis = mp["inertie"]
	var sym := absf(ib.x.y - ib.y.x) < 1e-6 and absf(ib.x.z - ib.z.x) < 1e-6 and absf(ib.y.z - ib.z.y) < 1e-6
	# tenseur « défini positif » (toute rotation coûte de l'énergie) : mineurs principaux positifs
	var d1 := ib.x.x
	var d2 := ib.x.x * ib.y.y - ib.x.y * ib.x.y
	var d3 := ib.determinant()
	var cg: Vector3 = mp["centre"]
	ok = absf(float(mp["masse"]) - m) < 1e-6 and (cg - g).length() < 1e-5 and absf(ib.z.z - izz) < 0.05 * 1.0 \
		and absf(float(mp["masse"]) - 8534.6) < 0.5 and absf(cg.z - 1.4367) < 0.001 and absf(cg.x) < 0.001 \
		and sym and d1 > 0.0 and d2 > 0.0 and d3 > 0.0 and absf(ib.x.x - 68711.0) < 100.0 and absf(ib.y.y - 83462.0) < 100.0 \
		and absf(ib.z.z - 21141.0) < 100.0 and absf(ib.x.y) < 50.0 and absf(ib.x.z) < 50.0 and absf(ib.y.z) < 50.0
	_resultat(ok, "Masse, centre de gravité et inertie calculés à partir des pièces",
		"%.1f kg (refait à la main : %.1f), centre de gravité (%.4f ; %.4f ; %.4f) m, inertie tangage %.0f, lacet %.0f, roulis %.0f kg·m² (roulis refait à la main : %.0f), croisés %.1f / %.1f / %.1f, symétrique : %s." % [
			float(mp["masse"]), m, cg.x, cg.y, cg.z, ib.x.x, ib.y.y, ib.z.z, izz, ib.x.y, ib.x.z, ib.y.z, "oui" if sym else "non"])

	# masse par matière (pour la fiche de chaque pièce, plus tard dans l'atelier)
	var pm: Dictionary = mp["masse_par_matiere"]
	var somme := 0.0
	for k in pm:
		somme += float(pm[k])
	ok = absf(somme - float(mp["masse"])) < 1e-6 and pm.has("composite_carbone") and absf(float(pm["composite_carbone"]) - 1480.7) < 1.0
	_resultat(ok, "Masse par matière", str(pm))

	# poutre et plaque : formules connues (barre pleine m·L²/12, plaque m·(a²+b²)/12)
	var poutre := {"type": "poutre", "matiere": "titane", "position": [0, 0, 0], "longueur_m": 2.0, "largeur_m": 0.1,
		"hauteur_m": 0.1}
	var mpo: Dictionary = Catalogue.masse_piece(poutre)
	var m_att := 4430.0 * 2.0 * 0.01
	var i_att := m_att / 12.0 * (0.01 + 4.0)
	var poutre_y := poutre.duplicate()
	poutre_y["rotation_deg"] = [0.0, 90.0, 0.0]   # couchée le long de X
	var mpy: Dictionary = Catalogue.masse_piece(poutre_y)
	var plaque := {"type": "plaque", "matiere": "aluminium", "position": [1, 2, 3], "longueur_m": 2.0, "largeur_m": 1.0,
		"epaisseur_m": 0.01}
	var mpl: Dictionary = Catalogue.masse_piece(plaque)
	var m_pl := 2700.0 * 0.02
	ok = absf(float(mpo["masse"]) - m_att) < 1e-9 and absf(float(mpo["inertie"][0]) - i_att) < 1e-6 \
		and absf(float(mpo["inertie"][2]) - m_att / 6.0 * 0.01) < 1e-6 \
		and absf(float(mpy["inertie"][1]) - i_att) < 1e-3 and absf(float(mpy["inertie"][2]) - i_att) < 1e-3 \
		and absf(float(mpl["masse"]) - m_pl) < 1e-9 and absf(float(mpl["inertie"][1]) - m_pl / 12.0 * 5.0) < 1e-6 \
		and (mpl["centre"] as Vector3) == Vector3(1, 2, 3)
	_resultat(ok, "Poutre et plaque : masse et inertie",
		"Poutre de titane 2 m × 10 cm × 10 cm : %.1f kg (attendu %.1f), inertie de travers %.3f kg·m² (attendu %.3f), couchée sur X : %.3f / %.3f. Plaque d'aluminium 2 m × 1 m × 1 cm : %.1f kg, %.3f kg·m² (attendu %.3f)." % [
			float(mpo["masse"]), m_att, float(mpo["inertie"][0]), i_att, float(mpy["inertie"][1]), float(mpy["inertie"][2]),
			float(mpl["masse"]), float(mpl["inertie"][1]), m_pl / 12.0 * 5.0])

	# sauvegarde et relecture : même plan, mêmes masses
	var chemin := "user://essai_plan_atelier.json"
	var err: Error = p.sauver(chemin)
	var p2 = Plan.new()
	var relu: bool = p2.charger(chemin)
	var mp2: Dictionary = p2.proprietes_masse()
	ok = err == OK and relu and p2.pieces.size() == p.pieces.size() and absf(float(mp2["masse"]) - float(mp["masse"])) < 1e-9 \
		and (mp2["centre"] as Vector3).is_equal_approx(mp["centre"]) and (mp2["inertie"] as Basis).is_equal_approx(mp["inertie"])
	_resultat(ok, "Sauvegarde et relecture du plan", "Écrit puis relu : %d pièces, %.1f kg." % [p2.pieces.size(), float(mp2["masse"])])
	DirAccess.remove_absolute(ProjectSettings.globalize_path(chemin))


# =====================================================================
# 2. LES SOUS-ENSEMBLES (une aile avec ses pièces, réutilisable)
# =====================================================================
func _aile_essai() -> Dictionary:
	# une petite « aile » : une plaque de carbone, un réacteur (masse), un propulseur au bout
	return {"pieces": [
		{"id": "panneau", "type": "plaque", "matiere": "composite_carbone", "position": [2.0, 0.0, 0.0],
			"longueur_m": 2.0, "largeur_m": 3.0, "epaisseur_m": 0.02},
		{"id": "reacteur", "type": "masse", "masse_kg": 300.0, "centre": [1.0, 0.0, 1.0]},
		{"id": "rcs", "type": "propulseur", "point": [3.5, 0.0, 0.0], "direction": [0.0, 1.0, 0.0], "poussee_n": 6000.0},
	]}


func _tests_ensembles() -> void:
	var aile := _aile_essai()
	var d := {"format": "plan-vaisseau", "version": 1, "nom": "essai", "commandes": {}, "pieces": [
		{"id": "corps", "type": "masse", "masse_kg": 1000.0, "centre": [0.0, 0.0, 0.0]},
		{"id": "aile_d", "type": "ensemble", "position": [0.5, 0.0, 0.0], "rotation_deg": [0.0, 0.0, 30.0],
			"pieces": aile["pieces"]},
		{"id": "aile_g", "type": "ensemble", "position": [-0.5, 0.0, 0.0], "rotation_deg": [0.0, 0.0, -30.0],
			"miroir_x": true, "pieces": aile["pieces"]},
	]}
	var p = Plan.new()
	var lu: bool = p.lire_dictionnaire(d)
	var par_id := {}
	for q in p.pieces:
		par_id[q["id"]] = q
	var rot := Catalogue.rotation([0.0, 0.0, 30.0])
	var att_rcs_d: Vector3 = Vector3(0.5, 0, 0) + rot * Vector3(3.5, 0, 0)
	var att_dir_d: Vector3 = rot * Vector3(0, 1, 0)
	var rcs_d: Dictionary = par_id.get("aile_d/rcs", {})
	var rcs_g: Dictionary = par_id.get("aile_g/rcs", {})
	var ok: bool = lu and p.pieces.size() == 7 and not rcs_d.is_empty() and not rcs_g.is_empty() \
		and (rcs_d["point"] as Vector3).is_equal_approx(att_rcs_d) and (rcs_d["direction"] as Vector3).is_equal_approx(att_dir_d) \
		and (rcs_g["point"] as Vector3).is_equal_approx(Vector3(-att_rcs_d.x, att_rcs_d.y, att_rcs_d.z)) \
		and (rcs_g["direction"] as Vector3).is_equal_approx(Vector3(-att_dir_d.x, att_dir_d.y, att_dir_d.z))
	_resultat(ok, "Sous-ensemble placé, tourné et retourné en miroir",
		"Aile droite (tournée de 30°) : propulseur en %s (attendu %s) ; aile gauche (miroir) : %s. Ids : %s." % [
			str(rcs_d.get("point", "?")), str(att_rcs_d), str(rcs_g.get("point", "?")), ", ".join(par_id.keys())])

	# masse : les deux ailes en miroir gardent le centre de gravité sur l'axe, et l'inertie est la même
	# que celle calculée pièce par pièce, sans sous-ensemble
	var mp: Dictionary = p.proprietes_masse()
	var plat := {"format": "plan-vaisseau", "version": 1, "commandes": {}, "pieces": [d["pieces"][0]]}
	for q in p.pieces:
		if q["id"] != "corps" and float(q["masse_calculee"]["masse"]) > 0.0:
			var mc: Dictionary = q["masse_calculee"]
			plat["pieces"].append({"id": q["id"], "type": "structure", "masse_kg": mc["masse"], "centre": [mc["centre"].x,
				mc["centre"].y, mc["centre"].z], "inertie_propre": mc["inertie"]})
	var p_plat = Plan.new()
	p_plat.lire_dictionnaire(plat)
	var mq: Dictionary = p_plat.proprietes_masse()
	var ib: Basis = mp["inertie"]
	ok = absf((mp["centre"] as Vector3).x) < 1e-5 and absf(ib.x.y) < 1e-3 and (ib.x - (mq["inertie"] as Basis).x).length() < 1e-3 \
		and absf(float(mp["masse"]) - (1000.0 + 2.0 * (300.0 + 1600.0 * 0.12))) < 1e-6
	_resultat(ok, "Sous-ensembles : masse et inertie",
		"%.1f kg, centre de gravité x = %.6f m (attendu 0 : ailes en miroir), produit croisé xy %.4f kg·m² (attendu 0)." % [
			float(mp["masse"]), (mp["centre"] as Vector3).x, ib.x.y])

	# un sous-ensemble sauvé seul (salle à part) puis réutilisé dans un autre plan, deux fois
	var chemin := "user://essai_aile_atelier.json"
	var fa := FileAccess.open(chemin, FileAccess.WRITE)
	fa.store_string(JSON.stringify({"format": "plan-vaisseau", "version": 1, "nom": "aile d'essai", "commandes": {},
		"pieces": aile["pieces"]}))
	fa.close()
	var d2 := {"format": "plan-vaisseau", "version": 1, "commandes": {}, "pieces": [
		{"id": "corps", "type": "masse", "masse_kg": 1000.0, "centre": [0.0, 0.0, 0.0]},
		{"id": "aile_d", "type": "ensemble", "plan": chemin, "position": [0.5, 0.0, 0.0], "rotation_deg": [0.0, 0.0, 30.0]},
		{"id": "aile_g", "type": "ensemble", "plan": chemin, "position": [-0.5, 0.0, 0.0], "rotation_deg": [0.0, 0.0, -30.0],
			"miroir_x": true},
	]}
	var p2 = Plan.new()
	var lu2: bool = p2.lire_dictionnaire(d2)
	var mp2: Dictionary = p2.proprietes_masse()
	ok = lu2 and p2.pieces.size() == 7 and absf(float(mp2["masse"]) - float(mp["masse"])) < 1e-9 \
		and (mp2["inertie"] as Basis).is_equal_approx(mp["inertie"])
	_resultat(ok, "Sous-ensemble sauvé à part et réutilisé",
		"Aile lue dans son propre fichier, posée deux fois : %d pièces, %.1f kg (comme le plan écrit d'un bloc : %.1f kg)." % [
			p2.pieces.size(), float(mp2["masse"]), float(mp["masse"])])
	DirAccess.remove_absolute(ProjectSettings.globalize_path(chemin))


# =====================================================================
# 3. ERREURS LISIBLES
# =====================================================================
func _tests_erreurs() -> void:
	var cas := [
		[{"format": "image"}, "pas un plan de vaisseau"],
		[{"format": "plan-vaisseau", "version": 9}, "plus récent"],
		[{"format": "plan-vaisseau", "version": 1, "commandes": {}, "pieces": [{"id": "x", "type": "fusee"}]}, "type « fusee » inconnu"],
		[{"format": "plan-vaisseau", "version": 1, "commandes": {}, "pieces": [{"id": "x", "type": "moteur", "point": [0, 0, 0]}]},
			"réglage « direction » manquant"],
		[{"format": "plan-vaisseau", "version": 1, "commandes": {}, "pieces": [{"id": "x", "type": "poutre", "matiere": "bois",
			"position": [0, 0, 0], "longueur_m": 1, "largeur_m": 1, "hauteur_m": 1}]}, "matière « bois » inconnue"],
		[{"format": "plan-vaisseau", "version": 1, "commandes": {}, "pieces": [{"id": "x", "type": "masse", "masse_kg": 1,
			"centre": [0, 0, 0], "articulation": "charniere_fantome"}]}, "articulation « charniere_fantome » introuvable"],
		[{"format": "plan-vaisseau", "version": 1, "commandes": {}, "pieces": [{"id": "x", "type": "masse", "masse_kg": 1,
			"centre": [0, 0, 0]}, {"id": "x", "type": "masse", "masse_kg": 1, "centre": [0, 0, 0]}]}, "en double"],
	]
	var trouves := 0
	var details := PackedStringArray()
	for c in cas:
		var p = Plan.new()
		var lu: bool = p.lire_dictionnaire(c[0])
		var texte := "; ".join(p.erreurs)
		if not lu and texte.contains(String(c[1])):
			trouves += 1
		else:
			details.append("« %s » attendu, reçu « %s »" % [c[1], texte])
	_resultat(trouves == cas.size(), "Erreurs du plan expliquées en français",
		"%d / %d plans faux reconnus avec la bonne explication. %s" % [trouves, cas.size(), " ".join(details)])


# =====================================================================
# 4. LE VAISSEAU CONSTRUIT PAR LE PLAN FAIT COMME AVANT
# =====================================================================
func _tests_vaisseau() -> void:
	if ancien.is_empty():
		_resultat(false, "Valeurs de l'ancien code", "fichier %s illisible" % ANCIEN)
		return
	# a. positions, directions et poussées des 29 propulseurs, ailes ouvertes, à moitié, repliées, et pendant
	#    toute la séquence du vol vertical (moteurs de levage qui sortent, tuyère qui tourne)
	var ecart_pos := 0.0
	var ecart_dir := 0.0
	var ecart_p := 0.0
	var ecart_angle := 0.0
	var noms_ok := true
	for cfg in ancien["configurations"]:
		var v = VaisseauPhysique.new()
		v.ailes = float(cfg["ailes"])
		v.vertical = float(cfg["vertical"])
		v._placer_propulseurs()
		var tous: Array = v.moteurs + v.rcs
		var props: Array = cfg["propulseurs"]
		if tous.size() != props.size():
			noms_ok = false
			continue
		for i in props.size():
			var a: Dictionary = props[i]
			var t: Dictionary = tous[i]
			noms_ok = noms_ok and String(t["nom"]) == String(a["nom"]) and String(t["aile"]) == String(a["aile"])
			ecart_pos = maxf(ecart_pos, ((t["position"] as Vector3) - _v(a["position"])).length())
			ecart_dir = maxf(ecart_dir, ((t["direction"] as Vector3) - _v(a["direction"])).length())
			ecart_p = maxf(ecart_p, absf(float(t["poussee_max"]) - float(a["poussee_max"])))
		ecart_angle = maxf(ecart_angle, absf(v.angle_tuyere() - float(cfg["angle_tuyere"])))
		ecart_angle = maxf(ecart_angle, absf(v.sortie_levage() - float(cfg["sortie_levage"])))
		ecart_dir = maxf(ecart_dir, (v.direction_poussee() - _v(cfg["direction_poussee"])).length())
	for a in ancien["angles_ailes"]:
		var v = VaisseauPhysique.new()
		v.ailes = float(a)
		for nom in ancien["angles_ailes"][a]:
			ecart_angle = maxf(ecart_angle, absf(v.angle_aile(nom) - float(ancien["angles_ailes"][a][nom])))
	var ok := noms_ok and ecart_pos < 1e-5 and ecart_dir < 1e-5 and ecart_p < 1e-6 and ecart_angle < 1e-6
	_resultat(ok, "Moteurs et propulseurs placés comme avant",
		"7 configurations (ailes ouvertes, à moitié, repliées ; vol vertical à 20, 40, 70, 100 %%) : plus grand écart de position %.7f m, de direction %.7f, de poussée %.3f N, d'angle %.7f (attendu : rien). Noms et ailes : %s." % [
			ecart_pos, ecart_dir, ecart_p, ecart_angle, "identiques" if noms_ok else "DIFFÉRENTS"])

	# b. rôles des petits propulseurs trouvés par le calcul du couple = ceux écrits à la main avant
	var v = VaisseauPhysique.new()
	var differents := PackedStringArray()
	var effets := PackedStringArray()
	var buse_max := 0.0
	var rotation_min := INF
	for t in v.rcs:
		var att: Array = ROLES_ANCIENS.get(String(t["nom"]), [-1, 0])
		if int(t["axe"]) != int(att[0]) or int(t["signe"]) != int(att[1]):
			differents.append("%s (%d, %d au lieu de %d, %d)" % [t["nom"], t["axe"], t["signe"], att[0], att[1]])
		if int(t["axe"]) < 0:
			buse_max = maxf(buse_max, float(t["effet_rotation"]))
		else:
			rotation_min = minf(rotation_min, float(t["effet_rotation"]))
	_resultat(differents.is_empty(), "Rôle des petits propulseurs trouvé par le calcul",
		"22 propulseurs : %s. Effet de rotation des propulseurs qui tournent : %.2f au moins ; des buses : %.2f au plus (seuil %.1f)." % [
			"tous comme avant (12 qui tournent, 10 buses)" if differents.is_empty() else "DIFFÉRENTS : " + ", ".join(differents),
			rotation_min, buse_max, VaisseauPhysique.SEUIL_ROTATION])

	# c. rotation maximale et poussées maximales : comme avant (la rotation maximale vient de paires qui ne
	#    poussent pas : elle ne dépend pas du centre de gravité, qui a bougé de 6 mm avec le nouveau calcul)
	var cm := _v(ancien["configurations"][0]["couple_max"])
	var e_cm: float = (v.couple_max - cm).length() / cm.length()
	var pv_ancien := float(ancien["poussee_verticale_max"])
	ok = e_cm < 1e-4 and absf(v.poussee_avant_max - float(ancien["poussee_avant_max"])) < 1.0 \
		and absf(v.poussee_verticale_max / pv_ancien - 1.0) < 0.02
	_resultat(ok, "Rotation et poussée maximales comme avant",
		"Rotation maximale %.0f / %.0f / %.0f N·m (avant %.0f / %.0f / %.0f). Poussée vers l'avant %.0f kN (avant %.0f), en vol vertical %.1f kN (avant %.1f : le centre de gravité recalculé a bougé de 6 mm)." % [
			v.couple_max.x, v.couple_max.y, v.couple_max.z, cm.x, cm.y, cm.z, v.poussee_avant_max / 1000.0,
			float(ancien["poussee_avant_max"]) / 1000.0, v.poussee_verticale_max / 1000.0, pv_ancien / 1000.0])

	# d. train et coque : roues, amortisseurs, hauteurs, empattement, braquage
	var sol: Dictionary = ancien["sol"]
	var e_sol := 0.0
	for k in 3:
		e_sol = maxf(e_sol, ((v.roues[k] as Vector3) - _v(sol["roues"][k])).length())
		e_sol = maxf(e_sol, absf(float(v.course_train[k]) - float(sol["course"][k])))
		e_sol = maxf(e_sol, absf(float(v.raideur_train[k]) - float(sol["raideur"][k])) / 1e5)
		e_sol = maxf(e_sol, absf(float(v.amorti_train[k]) - float(sol["amorti"][k])) / 1e5)
	for k in 6:
		e_sol = maxf(e_sol, ((v.coque_points[k] as Vector3) - _v(sol["coque"][k])).length())
	e_sol = maxf(e_sol, absf(v.hauteur_train - float(sol["hauteur_train"])))
	e_sol = maxf(e_sol, absf(v.hauteur_ventre - float(sol["hauteur_ventre"])))
	e_sol = maxf(e_sol, absf(v.empattement - float(sol["empattement"])))
	e_sol = maxf(e_sol, absf(v.braquage_max - float(sol["braquage_max"])))
	e_sol = maxf(e_sol, absf(v.vitesse_braquage - float(sol["vitesse_braquage"])))
	_resultat(e_sol < 1e-5 and v.roue_orientable == 0 and v.prise_points == 9, "Train et coque comme avant",
		"3 roues, 6 points de coque : plus grand écart %.7f. Hauteur train %.2f m, ventre %.2f m, empattement %.2f m (calculés à partir des pièces), roue orientable n° %d." % [
			e_sol, v.hauteur_train, v.hauteur_ventre, v.empattement, v.roue_orientable])

	# e. l'air : mêmes plaques, mêmes forces (sans rotation, la force ne dépend pas du centre de gravité)
	var aero = Aerodynamique.new()
	var e_f := 0.0
	var e_pt := 0.0
	var e_prise := 0.0
	for c in ancien["aero"]:
		var r: Array = aero.forces(_v(c["vent"]), Vector3.ZERO, 0.5, 300.0, float(c["ailes"]), float(c["train"]))
		var f_a := _v(c["force"])
		e_f = maxf(e_f, ((r[0] as Vector3) - f_a).length() / f_a.length())
		for k in (c["points"] as Array).size():
			e_pt = maxf(e_pt, (aero.prise_point[k] - _v(c["points"][k])).length())
			e_pt = maxf(e_pt, absf(aero.prise_surface[k] - float(c["surfaces"][k])))
			e_pt = maxf(e_pt, absf(aero.prise_corde[k] - float(c["cordes"][k])))
			e_pt = maxf(e_pt, absf(aero.prise_alpha[k] - float(c["alpha"][k])))
		for g in (c["prise_f"] as Array).size():
			e_prise = maxf(e_prise, (aero.prise_f[g] - _v(c["prise_f"][g])).length() / maxf(f_a.length(), 1.0))
	ok = e_f < 1e-5 and e_pt < 1e-5 and e_prise < 1e-5 and aero.prise_surfaces == 9 and aero.prise_plaques == 14
	_resultat(ok, "Air : mêmes plaques et mêmes forces",
		"6 vents (ailes ouvertes, à moitié, au quart, repliées ; train sorti) : écart de force %.8f (relatif), de plaque %.8f, par surface %.8f. %d surfaces, %d plaques." % [
			e_f, e_pt, e_prise, aero.prise_surfaces, aero.prise_plaques])

	# f. un autre plan donne un autre vaisseau : sans les 4 moteurs d'aile, plus léger de 1 520 kg (réacteurs)
	var d: Dictionary = (Plan.par_defaut().donnees as Dictionary).duplicate(true)
	var garde := []
	for q in d["pieces"]:
		if not (String(q["id"]).begins_with("moteur_haut") or String(q["id"]).begins_with("moteur_bas")
				or String(q["id"]).begins_with("Masse_reacteur_aile")):
			garde.append(q)
	d["pieces"] = garde
	var p2 = Plan.new()
	p2.lire_dictionnaire(d)
	var w = VaisseauPhysique.new(p2)
	ok = p2.valide() and w.moteurs.size() == 3 and absf(w.masse - (v.masse - 1520.0)) < 0.01 \
		and absf(w.poussee_avant_max - 200000.0) < 1.0 and w.centre_gravite.z > v.centre_gravite.z - 0.5
	_resultat(ok, "Un autre plan donne un autre vaisseau",
		"Plan sans les 4 moteurs d'aile : %d moteurs, %.1f kg (au lieu de %.1f), poussée vers l'avant %.0f kN (au lieu de %.0f), centre de gravité à %.3f m (au lieu de %.3f)." % [
			w.moteurs.size(), w.masse, v.masse, w.poussee_avant_max / 1000.0, v.poussee_avant_max / 1000.0,
			w.centre_gravite.z, v.centre_gravite.z])

	# g. la rotation suit l'inertie complète : moment cinétique conservé sans couple, même en tournant
	#    autour d'un axe quelconque (le vaisseau « vacille », l'énergie et le moment cinétique restent)
	v = VaisseauPhysique.new()
	v.gradient_gravite = false
	v.omega = Vector3(0.3, -0.2, 0.5)
	var l0: Vector3 = v.moment_cinetique_monde()
	var e0: float = 0.5 * v.omega.dot(v.tenseur_inertie * v.omega)
	for i in 1200:
		v._tourner(Vector3.ZERO, 1.0 / 120.0)
	var l1: Vector3 = v.moment_cinetique_monde()
	var e1: float = 0.5 * v.omega.dot(v.tenseur_inertie * v.omega)
	ok = (l1 - l0).length() < 1e-4 * l0.length() and absf(e1 - e0) < 1e-3 * e0
	_resultat(ok, "Rotation avec l'inertie complète",
		"10 s de rotation libre : moment cinétique %.1f → %.1f kg·m²/s (écart relatif %.8f), énergie %.1f → %.1f J." % [
			l0.length(), l1.length(), (l1 - l0).length() / l0.length(), e0, e1])


# =====================================================================
# ÉTAPE 2 — A. POSÉ AU SOL (atelier et départ « devant le hangar »)
# =====================================================================
## Un vaisseau sur la planète du jeu (sol lisse si relief est vide).
static func _vaisseau_planete(relief := Callable(), tourne := false):
	var v = VaisseauPhysique.new()
	v.gm = GRAVITE_SURFACE * RAYON_PLANETE * RAYON_PLANETE
	v.rayon_planete = RAYON_PLANETE
	v.relief = relief
	if tourne:
		v.omega_planete = TAU / DUREE_JOUR
		v.atmosphere = Atmosphere.new(RAYON_PLANETE, v.omega_planete)
	return v


## Position du centre de gravité dans le repère de la planète (qui tourne), en 64 bits.
static func _pos_planete(v) -> PackedFloat64Array:
	return v._vers_planete_64(v.px, v.py, v.pz)


## Vitesse par rapport au sol (m/s).
static func _vitesse_par_sol(v) -> float:
	return (Vector3(v.vx, v.vy, v.vz) - v.vitesse_sol(v.px, v.py, v.pz)).length()


## Laisse le vaisseau au repos pendant « secondes » ; renvoie le déplacement par rapport au sol (m).
static func _attendre_au_sol(v, secondes: float) -> float:
	var p0 := _pos_planete(v)
	for i in roundi(secondes * 240.0):
		v.commander(0.0, 0.0, 0.0, 0.0)
		v.pas(1.0 / 240.0)
	var p1 := _pos_planete(v)
	return sqrt(pow(p1[0] - p0[0], 2) + pow(p1[1] - p0[1], 2) + pow(p1[2] - p0[2], 2))


## Plus petit écart entre le bas d'une roue (amortisseur écrasé) et le sol (m) : ≈ 0 quand il est posé.
static func _ecart_roues_sol(v) -> float:
	var b := Basis(v.orientation)
	var e := INF
	for k in v.roues.size():
		var bas: Vector3 = (v.roues[k] as Vector3) + Vector3(0.0, v.compression_roues[k], 0.0)
		var d: Vector3 = b * (bas - v.centre_gravite)
		# en 64 bits (un Vector3 à 600 km ne voit que des pas de 6 cm)
		var qx: float = v.px + d.x
		var qy: float = v.py + d.y
		var qz: float = v.pz + d.z
		e = minf(e, sqrt(qx * qx + qy * qy + qz * qz) - (v.rayon_planete + v.hauteur_sol(qx, qy, qz)))
	return e


func _verifier_pose(v, nom: String, endroit: String) -> void:
	var vit := _vitesse_par_sol(v)
	var e := _ecart_roues_sol(v)
	var impact: float = v.vitesse_impact   # le calage n'est pas un atterrissage : 0
	var comp_ok := true
	for k in v.roues.size():
		comp_ok = comp_ok and v.compression_roues[k] > 0.005 and v.compression_roues[k] < float(v.course_train[k])
	var derive := _attendre_au_sol(v, 5.0)
	var ok: bool = v.au_sol and not v.ecrase and vit < 0.01 and absf(e) < 0.03 and comp_ok and derive < 0.05 \
		and v.train == 1.0 and v.ailes == 0.0 and impact == 0.0
	_resultat(ok, nom, "%s : posé %s, écrasé %s, vitesse %.4f m/s par rapport au sol, roues à %.1f mm du sol, amortisseurs écrasés de %s cm, train sorti, ailes repliées, pas d'« impact » (%.1f) ; 5 s plus tard il a bougé de %.1f mm." % [
		endroit, v.au_sol, v.ecrase, vit, e * 1000.0, ", ".join(Array(v.compression_roues).map(func(x): return "%.1f" % (x * 100.0))),
		impact, derive * 1000.0])


func _tests_pose_au_sol() -> void:
	# a. sol lisse (comme dans le hangar de l'atelier)
	var v = _vaisseau_planete()
	v.poser_au_sol(Vector3.UP, Vector3.FORWARD, 2.0)
	_verifier_pose(v, "Posé au sol : sol lisse", "Pôle de la planète, sol plat")
	# b. sol bosselé et en pente (3°), planète qui tourne, avec l'air
	var bosses := func(x: float, y: float, z: float) -> float:
		var r := sqrt(x * x + y * y + z * z)
		var u := Vector3(x, y, z) / r
		return 0.35 * sin(u.x * 9000.0) * cos(u.z * 7000.0) + u.z * RAYON_PLANETE * tan(deg_to_rad(3.0))
	v = _vaisseau_planete(bosses, true)
	v.poser_au_sol(Vector3(0.2, 1.0, 0.1), Vector3(1.0, 0.0, -0.3), 2.0)
	_verifier_pose(v, "Posé au sol : bosses et pente", "Sol bosselé (±35 cm) en pente de 3°, planète qui tourne")
	# c. le vrai endroit du hangar, sur le vrai relief de la planète (partie C++ de la lumière)
	if not ClassDB.class_exists("ArbreLumiere"):
		_resultat(false, "Départ devant le hangar", "partie C++ de la planète absente : relief introuvable")
		return
	var arbre = ClassDB.instantiate("ArbreLumiere")
	arbre.configurer(RAYON_PLANETE, 7, 1024)   # même planète que le jeu (lumiere_jeu.gd : GRAINE 7)
	var relief := func(x: float, y: float, z: float) -> float: return arbre.hauteur_sol(PackedFloat64Array([x, y, z]))
	v = _vaisseau_planete(relief, true)
	v.poser_au_sol(LIEU_HANGAR, -VERS_SOLEIL.normalized(), 2.0)
	var haut := Vector3(v.px, v.py, v.pz).normalized()
	var n: Vector3 = v.normale_sol(v.px, v.py, v.pz)
	var pente := rad_to_deg(haut.angle_to(n))
	var soleil := 90.0 - rad_to_deg(haut.angle_to(VERS_SOLEIL.normalized()))
	var altitude: float = Vector3(v.px, v.py, v.pz).length() - RAYON_PLANETE
	var nez: Vector3 = -(Basis(v.orientation).z)
	var dos_au_soleil := nez.dot(VERS_SOLEIL.normalized()) < 0.0
	_resultat(pente < 4.0 and soleil > 20.0 and dos_au_soleil, "Départ devant le hangar : l'endroit",
		"Pente %.1f° sous le vaisseau, altitude %.0f m, Soleil à %.0f° au-dessus de l'horizon (de jour), nez à l'opposé du Soleil : %s." % [
			pente, altitude, soleil, dos_au_soleil])
	_verifier_pose(v, "Départ devant le hangar : posé", "Vrai relief de la planète")


# =====================================================================
# ÉTAPE 2 — B. TABLEAU INGÉNIEUR, CATALOGUE, RECHERCHE, FICHES
# =====================================================================
func _tests_analyse() -> void:
	var a = Analyse.new()
	var v = VaisseauPhysique.new()
	var t: Dictionary = a.tableau()
	var ok: bool = absf(float(t["masse"]) - v.masse) < 0.001 and absf(float(t["masse"]) - 8534.6) < 0.1 \
		and absf(float(t["poussee_avant"]) - 1.0e6) < 1.0 and int(t["moteurs_principaux"]) == 5 \
		and absf(float(t["poussee_verticale"]) - v.poussee_verticale_max) < 0.001 \
		and float(t["poussee_verticale"]) > 200000.0 and float(t["poussee_verticale"]) < 220000.0 \
		and bool(t["peut_decoller"]) and absf(float(t["poussee_poids"]) - 1.0e6 / (v.masse * 9.81)) < 1e-6
	_resultat(ok, "Tableau ingénieur = physique du jeu",
		"masse %.1f kg, poussée vers l'avant %.0f kN (5 moteurs), décollage vertical %.1f kN (× %.2f le poids), poussée / poids %.2f." % [
			t["masse"], float(t["poussee_avant"]) / 1000.0, float(t["poussee_verticale"]) / 1000.0, t["rapport_vertical"], t["poussee_poids"]])
	var tu: Array = a.tuiles()
	ok = tu.size() == 7 and String(tu[0][1]) == "8 534,6 kg" and String(tu[1][1]) == "1 000 kN"
	_resultat(ok, "Tuiles du tableau", " | ".join(tu.map(func(x): return "%s : %s" % [x[0], x[1]])))
	# couple : la poussée des 5 moteurs passe presque par le centre de gravité, les propulseurs compensent
	var c: Vector3 = t["couple_moteurs"]
	ok = float(t["decalage_poussee"]) < 0.05 and bool(t["couple_compense"])
	_resultat(ok, "Couple des moteurs", "%.0f N·m : poussée à %.1f cm du centre de gravité, compensée par les propulseurs : %s." % [
		c.length(), float(t["decalage_poussee"]) * 100.0, t["couple_compense"]])
	# chaque pièce dans une seule catégorie, et les bonnes au bon endroit
	var pc: Dictionary = a.pieces_par_categorie()
	var total := 0
	var vus := {}
	var doublon := false
	for k in pc:
		total += (pc[k] as Array).size()
		for i in pc[k]:
			doublon = doublon or vus.has(i)
			vus[i] = true
	ok = total == a.plan.pieces.size() and not doublon and (pc["moteurs"] as Array).has("moteur_central") \
		and (pc["propulseurs"] as Array).filter(func(i): return a.piece(i)["type"] == "propulseur").size() == v.rcs.size() and (pc["ailes"] as Array).has("Aile_haut_gauche") \
		and (pc["train"] as Array).has("Roue_avant") and (pc["cockpit"] as Array).has("Verriere")
	_resultat(ok, "Catégories du catalogue", " · ".join(Analyse.CATEGORIES.map(func(x): return "%s %d" % [x[1], (pc[x[0]] as Array).size()])))
	# recherche : sans accents, plusieurs mots, rien trouvé
	var trouve := func(r: String) -> Array: return a.plan.pieces.filter(func(p): return a.correspond(p["id"], r)).map(func(p): return p["id"])
	var r1: Array = trouve.call("tuyere")
	var r2: Array = trouve.call("Tuyère")
	var r3: Array = trouve.call("aile haut gauche")
	var r4: Array = trouve.call("zzzz")
	var r5: Array = trouve.call("titane")
	ok = r1.size() > 0 and r1 == r2 and r3.has("Aile_haut_gauche") and not r3.has("Aile_bas_droit") and r4.is_empty() and r5.size() > 0
	_resultat(ok, "Recherche dans le catalogue", "« tuyere » %d pièces (= « Tuyère »), « aile haut gauche » %d, « titane » %d, « zzzz » %d." % [
		r1.size(), r3.size(), r5.size(), r4.size()])
	# fiches
	var f: Dictionary = a.fiche_piece("moteur_central")
	var texte := " ".join(f["lignes"].map(func(l): return "%s=%s" % [l[0], l[1]]))
	ok = String(f["titre"]) == "Poussée du moteur central" and texte.contains("200") and texte.contains("Poussée")
	_resultat(ok, "Fiche d'un moteur", "%s — %s" % [f["titre"], texte.left(160)])
	var rcs_id := String(v.rcs[0]["id"])
	f = a.fiche_piece(rcs_id)
	texte = " ".join(f["lignes"].map(func(l): return "%s=%s" % [l[0], l[1]]))
	ok = texte.contains("Rôle") and Analyse.role_propulseur(v.rcs[0]) != ""
	_resultat(ok, "Fiche d'un propulseur (rôle calculé)", "%s — rôle : %s" % [f["titre"], Analyse.role_propulseur(v.rcs[0])])
	f = a.fiche_piece("Fuselage")
	texte = " ".join(f["lignes"].map(func(l): return "%s=%s" % [l[0], l[1]]))
	ok = texte.contains("kg") and texte.contains("%")
	_resultat(ok, "Fiche d'une pièce de structure", "%s — %s" % [f["titre"], texte.left(160)])
	ok = Analyse.nombre(8534.6, 1) == "8 534,6" and Analyse.nombre(-0.5, 2) in ["−0,50", "-0,50"]
	_resultat(ok, "Nombres à la française", "%s ; %s ; %s" % [Analyse.nombre(8534.6, 1), Analyse.nombre(1.0e6), Analyse.nombre(-0.5, 2)])


# =====================================================================
# ÉTAPE 2 — C. CAMÉRA DE L'ATELIER
# =====================================================================
func _tests_camera() -> void:
	var c = CameraAtelier.new()
	add_child(c)
	c.cible = Vector3(0, 1.5, 0)
	c.distance = 20.0
	c.vue("face")
	var face: Vector3 = c.global_position
	c.vue("droite")
	var droite: Vector3 = c.global_position
	c.vue("dessus")
	var dessus: Vector3 = c.global_position
	# devant = −Z (le nez) ; vue de droite : caméra du côté +X ; dessus : au-dessus
	var ok: bool = face.z < -19.0 and absf(face.x) < 0.01 and droite.x > 19.0 and dessus.y > 21.0
	_resultat(ok, "Caméra : vues toutes faites", "face %s, droite %s, dessus %s" % [face.round(), droite.round(), dessus.round()])
	# jamais sous le sol, même en tirant vers le haut
	c.vue("trois_quarts")
	c.tourner(0.0, -5000.0)
	var bas: float = c.global_position.y
	c.vitesse = 4.0
	var d0: float = c.distance
	c.zoomer(1.0)
	var d1: float = c.distance
	c.vitesse = 0.25
	c.zoomer(1.0)
	var d2: float = c.distance
	ok = bas >= c.sol_min - 0.001 and d1 < d0 and absf(d0 / d1 - pow(1.12, 4.0)) < 1e-3 and absf(d1 / d2 - pow(1.12, 0.25)) < 1e-3
	_resultat(ok, "Caméra : sol et vitesse", "plus bas : %.2f m (limite %.2f) ; un cran de molette à ×4 : %.1f → %.1f m, à ×0,25 : → %.2f m" % [
		bas, c.sol_min, d0, d1, d2])
	# cadrer une boîte : tout est dans le champ
	c.vitesse = 1.0
	var boite := AABB(Vector3(-5, 0, -8), Vector3(10, 4, 16))
	c.cadrer(boite)
	var dedans := true
	for i in 8:
		var coin := boite.get_endpoint(i)
		var vers: Vector3 = (coin - c.global_position).normalized()
		dedans = dedans and rad_to_deg(vers.angle_to(c.direction())) < c.fov * 0.5 + 0.5
	_resultat(dedans, "Caméra : cadrer", "boîte de 10 × 4 × 16 m vue en entier à %.1f m" % c.distance)
	c.queue_free()


# =====================================================================
# ÉTAPE 2 — D. PASSAGE ENTRE LES ÉCRANS
# =====================================================================
## Scripts chargés par un script (preload / load de .gd), de proche en proche.
static func _scripts_charges(chemin: String, vus: Dictionary) -> void:
	if vus.has(chemin) or not FileAccess.file_exists(chemin):
		return
	vus[chemin] = true
	var texte := FileAccess.get_file_as_string(chemin)
	var re := RegEx.new()
	re.compile("(?:preload|load)\\(\"(res://[^\"]+\\.gd)\"\\)")
	for m in re.search_all(texte):
		_scripts_charges(m.get_string(1), vus)


func _tests_partie() -> void:
	var avant = Engine.get_meta("partie") if Engine.has_meta("partie") else null
	Partie.choisir_depart(Partie.DEPART_HANGAR)
	var ok := Partie.depart() == Partie.DEPART_HANGAR
	Partie.choisir_depart("")
	ok = ok and Partie.depart() == ""
	var plans: Array = Partie.plans_disponibles()
	var v27 := plans.filter(func(p): return p["chemin"] == Plan.PLAN_PAR_DEFAUT)
	ok = ok and v27.size() == 1 and String(v27[0]["nom"]) == "Chasseur v27"
	_resultat(ok, "Accueil / atelier / jeu : ce qui passe d'un écran à l'autre", "départ gardé, %d plan(s) de vaisseau trouvé(s) : %s" % [
		plans.size(), ", ".join(plans.map(func(p): return p["nom"]))])
	if avant != null:
		Engine.set_meta("partie", avant)
	# l'atelier et l'accueil ne chargent rien du jeu (planète, lumière, son) : la mémoire reste libre
	var lourds := ["res://scripts/jeu.gd", "res://scripts/lumiere_jeu.gd", "res://scripts/son/moteur_audio.gd", "res://scripts/droide.gd"]
	for depart in ["res://scripts/atelier/atelier.gd", "res://scripts/accueil.gd"]:
		var vus := {}
		_scripts_charges(depart, vus)
		var pris := lourds.filter(func(x): return vus.has(x))
		_resultat(pris.is_empty(), "%s ne charge pas le jeu" % depart.get_file(), "%d scripts chargés, dont du jeu : %s" % [
			vus.size(), "aucun" if pris.is_empty() else ", ".join(pris)])
	var scene := String(ProjectSettings.get_setting("application/run/main_scene", ""))
	_resultat(scene == Partie.SCENE_ACCUEIL, "Le jeu s'ouvre sur l'accueil", "scène de départ : %s" % scene)


# =====================================================================
# ÉTAPE 2 — E. L'ÉCRAN DE L'ATELIER
# =====================================================================
func _tests_ecran_atelier() -> void:
	var at = (load(SCENE_ATELIER) as PackedScene).instantiate()
	add_child(at)
	await get_tree().process_frame
	await get_tree().physics_frame
	await get_tree().physics_frame
	# le vaisseau est posé sur le sol du hangar (y = 0), sur ses roues
	var h: float = at.hauteur_roues()
	var boite: AABB = at.boite_vaisseau()
	var ok: bool = absf(h) < 0.02 and at.vaisseau_pose.au_sol and boite.position.y > -0.05
	_resultat(ok, "Atelier : vaisseau posé dans le hangar", "roues à %.1f mm du sol, point le plus bas du dessin à %.2f m, %d pièces dessinées sur %d" % [
		h * 1000.0, boite.position.y, at.maillages.size(), at.plan.pieces.size()])
	# toutes les pièces de structure ont leur dessin (on peut les choisir dans la vue 3D)
	var sans: Array = at.plan.pieces.filter(func(p): return p["type"] == "structure" and not at.maillages.has(p["id"]))
	_resultat(sans.is_empty(), "Atelier : chaque pièce de structure a son dessin", "sans dessin : %s" % (
		"aucune" if sans.is_empty() else ", ".join(sans.map(func(p): return p["id"]))))
	# clic dans la vue 3D : la pièce sous la souris
	at.camera.vue("face")
	at.camera.cadrer(boite)
	await get_tree().process_frame
	await get_tree().physics_frame
	var fus: MeshInstance3D = at.maillages["Fuselage"][0]
	var centre: Vector3 = (fus.global_transform * fus.get_aabb()).get_center()
	var pos_ecran: Vector2 = at.camera.unproject_position(centre)
	var sous: String = at.piece_sous(pos_ecran)
	var a_cote: String = at.piece_sous(Vector2(2, 2))
	_resultat(sous != "" and a_cote == "", "Atelier : clic sur une pièce", "au centre du fuselage (%s) : « %s » ; dans un coin de l'écran : « %s »" % [
		pos_ecran.round(), sous, a_cote])
	# choisir une pièce : fiche ouverte, pièce surlignée, sélectionnée dans la liste
	at.choisir("piece", "Fuselage")
	await get_tree().process_frame
	var surlignee: bool = fus.material_overlay != null
	var item = at.arbre.get_selected()
	ok = at.fiche.visible and String(at.fiche_titre.text) == "Fuselage" and surlignee and item != null \
		and String(item.get_metadata(0)["id"]) == "Fuselage"
	_resultat(ok, "Atelier : fiche d'une pièce", "fiche « %s » (%d lignes), surlignée : %s, choisie dans la liste : %s" % [
		at.fiche_titre.text, roundi(at.fiche_grille.get_child_count() * 0.5), surlignee, item != null])
	# une pièce sans dessin (moteur) : flèche dans la vue
	at.choisir("piece", "moteur_central")
	await get_tree().process_frame
	_resultat(at._repere_selection.get_child_count() == 1, "Atelier : pièce sans dessin montrée par une flèche",
		"%d repère(s) pour le moteur central" % at._repere_selection.get_child_count())
	# une catégorie entière
	at.choisir("categorie", "propulseurs")
	await get_tree().process_frame
	_resultat(at._repere_selection.get_child_count() == at.vaisseau_pose.rcs.size(), "Atelier : choisir une catégorie",
		"%d flèches pour %d petits propulseurs" % [at._repere_selection.get_child_count(), at.vaisseau_pose.rcs.size()])
	at.deselectionner()
	_resultat(not at.fiche.visible and fus.material_overlay == null, "Atelier : Échap / rien choisir", "fiche fermée, plus rien de surligné")
	# recherche : la liste ne garde que ce qui correspond
	at.recherche.text = "tuyere"
	at.remplir_catalogue()
	var feuilles := []
	_feuilles(at.arbre.get_root(), feuilles)
	var pieces_trouvees := feuilles.filter(func(m): return m["genre"] == "piece")
	ok = pieces_trouvees.size() > 0 and pieces_trouvees.all(func(m): return String(m["id"]).to_lower().contains("tuyere"))
	_resultat(ok, "Atelier : recherche dans la liste", "« tuyere » : %d pièces dans la liste" % pieces_trouvees.size())
	at.recherche.text = ""
	at.remplir_catalogue()
	# fond neutre, centre de gravité, flèches de poussée
	at.case_neutre.button_pressed = true
	at.case_poussees.button_pressed = true
	ok = not at.hangar.decor.visible and at._fleches_poussee.visible and at._fleches_poussee.get_child_count() == 6
	at.case_neutre.button_pressed = false
	at.case_poussees.button_pressed = false
	_resultat(ok and at.hangar.decor.visible, "Atelier : fond neutre et flèches de poussée", "5 moteurs + la résultante : %d flèches" % at._fleches_poussee.get_child_count())
	at.queue_free()
	await get_tree().process_frame


func _feuilles(it: TreeItem, sortie: Array) -> void:
	if it == null:
		return
	var m = it.get_metadata(0)
	if m is Dictionary and it.get_child_count() == 0:
		sortie.append(m)
	var e := it.get_first_child()
	while e != null:
		_feuilles(e, sortie)
		e = e.get_next()
