extends Node
## Tests de l'atelier, étape 1 : le PLAN du vaisseau (scripts/atelier/plan.gd), son catalogue de pièces
## (scripts/atelier/catalogue.gd), et la physique construite à partir du plan.
## Étape 2 : l'écran de l'atelier (tableau ingénieur, catalogue, fiches, caméra, choix d'une pièce dans la
## vue 3D), le départ posé au sol devant le hangar, et le passage accueil / atelier / jeu.
## Étape 3 : construire. Pièces toutes faites (scripts/atelier/pieces_toutes_faites.gd), édition du plan
## (scripts/atelier/edition.gd : poser, symétrie, régler, enlever, annuler / refaire, enregistrer), dessin
## partagé atelier / jeu (scripts/dessin_vaisseau.gd), et dans l'écran : poser à la souris, pièces qui
## flottent, « Lancer » refusé.
## Étape 4 : l'analyse ingénieur (scripts/atelier/analyse.gd : répartition des masses, poussées et couple
## axe par axe, défauts de symétrie, analyse d'une sélection et « le vaisseau sans elle »), et dans l'écran :
## plusieurs pièces à la fois (Ctrl + clic), tuiles cliquables, flèche du couple, salle à part.
## Étape 5 : le jeu dessine TOUT le plan (scripts/dessin_vaisseau.gd : pièces faites à la main, vraies vitres,
## pièces posées fusionnées par matière, compte de ce que la carte graphique dessine) et le CONTRÔLE AVANT LE
## VOL (scripts/atelier/controle_vol.gd : vitesse du PC, lumière, au sol, en vol, symétrie), et dans l'écran :
## la tuile AVANT LE VOL, sa page, la fenêtre de « Lancer » (atelier) et de « Jouer » (accueil).
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
const Edition = preload("res://scripts/atelier/edition.gd")
const Pieces = preload("res://scripts/atelier/pieces_toutes_faites.gd")
const DessinVaisseau = preload("res://scripts/dessin_vaisseau.gd")
const ModeleVaisseau = preload("res://scripts/modele_vaisseau.gd")
const AtelierScript = preload("res://scripts/atelier/atelier.gd")
const ControleVol = preload("res://scripts/atelier/controle_vol.gd")
const Objets = preload("res://scripts/lumiere/objets.gd")
const SCENE_ACCUEIL := "res://scenes/accueil.tscn"
const DOSSIER_ESSAI := "user://essais_atelier_etape3/"
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
	_tests_pieces_toutes_faites()
	_tests_edition()
	_tests_fichiers()
	_tests_dessin()
	_tests_vaisseaux_limites()
	_tests_pose_calcul()
	_tests_analyse_etape4()
	_tests_dessin_etape5()
	_tests_controle_vol()
	# l'écran de l'atelier s'ouvre sur le chasseur de départ, et ce que les tests enregistrent ne touche pas
	# aux vaisseaux ni au dernier vaisseau ouvert du joueur
	var partie_avant = Engine.get_meta("partie") if Engine.has_meta("partie") else null
	var cfg_avant := FileAccess.get_file_as_string(Partie.FICHIER) if FileAccess.file_exists(Partie.FICHIER) else ""
	Engine.set_meta("partie", {"plan": Plan.PLAN_PAR_DEFAUT, "depart": "", "plan_lu": true})
	await _tests_ecran_atelier()
	await _tests_ecran_etape3()
	await _tests_ecran_etape4()
	await _tests_ecran_etape5()
	if partie_avant != null:
		Engine.set_meta("partie", partie_avant)
	else:
		Engine.remove_meta("partie")
	if cfg_avant != "":
		var fc := FileAccess.open(Partie.FICHIER, FileAccess.WRITE)
		fc.store_string(cfg_avant)
		fc.close()
	elif FileAccess.file_exists(Partie.FICHIER):
		DirAccess.remove_absolute(Partie.FICHIER)
	_vider_dossier(DOSSIER_ESSAI)
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
	ok = tu.size() == 8 and String(tu[0][1]) == "8 534,6 kg" and String(tu[1][1]) == "1 000 kN"
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


# =====================================================================
# ÉTAPE 3 — A. LES PIÈCES TOUTES FAITES
# =====================================================================
static func _plan_de(d: Dictionary):
	var p = Plan.new()
	p.lire_dictionnaire(d.duplicate(true))
	return p


static func _ed_depart():
	var base = Plan.par_defaut()
	return Edition.new(base.donnees, base.chemin)


func _tests_pieces_toutes_faites() -> void:
	# chaque pièce du catalogue se pose : le plan reste valide, la physique gagne exactement sa masse
	var lignes := []
	var ok := true
	var m0: float = VaisseauPhysique.new().masse
	for modele in Pieces.MODELES:
		var ed = _ed_depart()
		var ids: Array = ed.ajouter(modele, {}, Transform3D(Basis.IDENTITY, Vector3(0.0, 1.0, 2.0)), "Fuselage")
		var p = ed.plan()
		var v = VaisseauPhysique.new(p)
		var attendu: float = Pieces.masse(modele, {})
		var dm: float = v.masse - m0
		var bon: bool = p.valide() and ids.size() == 1 and absf(dm - attendu) < 0.01 and attendu > 0.0 and is_finite(v.inertie.x)
		ok = ok and bon
		lignes.append("%s +%.1f kg%s" % [modele, dm, "" if bon else " (FAUX)"])
	_resultat(ok, "Pièces toutes faites : chacune se pose et pèse", ", ".join(lignes))
	# moteurs : 3 tailles et poussée réglable ; plus il pousse, plus il est gros et lourd (4,5 kg par kN)
	var tailles := []
	ok = true
	var d_avant := 0.0
	for kn in [100.0, 200.0, 400.0, 600.0]:
		var dl: Vector2 = Pieces.dimensions_ionique(kn)
		var m: float = Pieces.masse("moteur_ionique", {"poussee_kn": kn})
		ok = ok and dl.x > d_avant and absf(m - 4.5 * kn) < 0.01
		d_avant = dl.x
		tailles.append("%d kN : Ø %.2f m, %.2f m de long, %.0f kg" % [kn, dl.x, dl.y, m])
	var r: Dictionary = Pieces.reglages_complets("moteur_ionique", {"poussee_kn": 5000.0})
	ok = ok and float(r["poussee_kn"]) == 600.0 and Pieces.reglages_complets("plaque", {"matiere": "fromage"})["matiere"] == "aluminium_lithium"
	_resultat(ok, "Moteurs : 3 tailles, poussée réglable (plus gros quand il pousse plus)", "; ".join(tailles) + " ; réglage hors bornes ramené à 600 kN")
	# réservoir : eau ou air, la masse du contenu compte (pas de carburant : elle ne change jamais)
	var eau: float = Pieces.masse("reservoir", {"volume_l": 400.0, "contenu": "eau"})
	var air: float = Pieces.masse("reservoir", {"volume_l": 400.0, "contenu": "air"})
	ok = eau > 400.0 and eau < 480.0 and air > 140.0 and air < eau
	_resultat(ok, "Réservoirs d'eau et d'air", "400 L d'eau : %.0f kg ; 400 L d'air à 300 bar : %.0f kg (enveloppe comprise)" % [eau, air])
	# bloc : inertie d'un cylindre plein (formule) tournée avec la pièce
	var mp: Dictionary = Catalogue.masse_piece({"type": "bloc", "forme": "cylindre", "dimensions_m": [1.0, 2.0], "masse_kg": 100.0, "position": [0, 0, 0]})
	var i6: Array = mp["inertie"]
	var ix := 100.0 * (3.0 * 0.25 + 4.0) / 12.0
	var iz := 100.0 * 0.25 / 2.0
	ok = absf(float(i6[0]) - ix) < 1e-4 and absf(float(i6[1]) - ix) < 1e-4 and absf(float(i6[2]) - iz) < 1e-4
	var mp2: Dictionary = Catalogue.masse_piece({"type": "bloc", "forme": "cylindre", "dimensions_m": [1.0, 2.0], "masse_kg": 100.0,
		"position": [0, 0, 0], "rotation_deg": [90.0, 0.0, 0.0]})
	var j6: Array = mp2["inertie"]
	ok = ok and absf(float(j6[1]) - iz) < 1e-3 and absf(float(j6[2]) - ix) < 1e-3
	_resultat(ok, "Bloc : inertie d'un cylindre plein, tournée avec lui", "Ixx = Iyy = %.2f, Izz = %.2f kg·m² ; couché (90°) : Iyy = %.2f, Izz = %.2f" % [i6[0], i6[2], j6[1], j6[2]])


# =====================================================================
# ÉTAPE 3 — B. ÉDITION DU PLAN : poser, symétrie, régler, enlever, annuler
# =====================================================================
func _tests_edition() -> void:
	var v0 = VaisseauPhysique.new()
	# une paire de moteurs en symétrie : le centre de gravité reste au milieu, les deux poussent pareil
	var ed = _ed_depart()
	var xf := Transform3D(Basis.IDENTITY, Vector3(2.2, 0.0, 2.6))
	var ids: Array = ed.ajouter("moteur_ionique", {"poussee_kn": 200.0}, xf, "Aile_haut_droit", "aile_haut_droit", true)
	var p = ed.plan()
	var v = VaisseauPhysique.new(p)
	var e1: Dictionary = ed.element(ids[0])
	var e2: Dictionary = ed.element(ids[1]) if ids.size() > 1 else {}
	var couple := Vector3.ZERO
	var force := Vector3.ZERO
	for m in v.moteurs:
		if String(m["id"]).begins_with("moteur_ionique"):
			var f: Vector3 = (m["dir_ref"] as Vector3) * float(m["poussee_n"])
			force += f
			couple += ((m["pos_ref"] as Vector3) - v.centre_gravite).cross(f)
	var ti: Basis = v.tenseur_inertie
	var bras_max := 1e-4 * force.length() + 1.0   # 0,1 mm de bras de levier
	var ok: bool = ids.size() == 2 and String(e2.get("articulation", "")) == "aile_haut_gauche" and String(e2.get("fixe_a", "")) == "Aile_haut_gauche" \
		and String(e1.get("symetrique", "")) == ids[1] and String(e2.get("symetrique", "")) == ids[0] \
		and absf(v.centre_gravite.x - v0.centre_gravite.x) < 0.0001 and absf(couple.y) < bras_max and absf(couple.z) < bras_max and absf(v.masse - v0.masse - 1800.0) < 0.01 \
		and absf(ti.x.y) < 1.0 and absf(ti.x.z) < 1.0 and String(e1["nom"]).ends_with("droite") and String(e2["nom"]).ends_with("gauche")
	_resultat(ok, "Symétrie : deux moteurs en miroir", "%s / %s, centre de gravité x = %.3f mm (%.3f avant), couple des deux moteurs (%.0f kN) : lacet %.1f, roulis %.1f N·m ; posés sur %s et %s ; masse +%.0f kg" % [
		e1.get("nom", ""), e2.get("nom", ""), v.centre_gravite.x * 1000.0, v0.centre_gravite.x * 1000.0, force.length() / 1000.0, couple.y, couple.z, e1.get("fixe_a", ""), e2.get("fixe_a", ""), v.masse - v0.masse])
	# la jumelle est vraiment l'image en miroir (une pièce tournée : sa jumelle tourne dans l'autre sens)
	var ed2 = _ed_depart()
	var b := Basis(Vector3.UP, deg_to_rad(30.0)) * Basis(Vector3.BACK, deg_to_rad(-90.0))
	var ids2: Array = ed2.ajouter("propulseur", {}, Transform3D(b, Vector3(1.0, 0.3, -2.0)), "Fuselage", "", true)
	var p2 = ed2.plan()
	var t1: Dictionary = {}
	var t2: Dictionary = {}
	for q in p2.pieces:
		if q["id"] == ids2[0] + "/poussee":
			t1 = q
		elif q["id"] == ids2[1] + "/poussee":
			t2 = q
	var s := Vector3(-1, 1, 1)
	ok = not t1.is_empty() and not t2.is_empty() and ((t1["point"] as Vector3) * s).distance_to(t2["point"]) < 1e-4 \
		and ((t1["direction"] as Vector3) * s).distance_to(t2["direction"]) < 1e-4 and bool(ed2.element(ids2[1]).get("miroir_x", false))
	_resultat(ok, "Symétrie : la jumelle est l'image en miroir", "propulseur en %s pousse vers %s ; jumelle en %s pousse vers %s" % [
		Analyse.vecteur_txt(t1.get("point", Vector3.ZERO)), Analyse.vecteur_txt(t1.get("direction", Vector3.ZERO)),
		Analyse.vecteur_txt(t2.get("point", Vector3.ZERO)), Analyse.vecteur_txt(t2.get("direction", Vector3.ZERO))])
	# sur l'axe du vaisseau : pas de jumelle
	var ids3: Array = ed2.ajouter("boite", {}, Transform3D(Basis.IDENTITY, Vector3(0.02, 1.0, 1.0)), "Fuselage", "", true)
	_resultat(ids3.size() == 1, "Symétrie : une pièce posée au milieu n'a pas de jumelle", "%d pièce posée à 2 cm du milieu" % ids3.size())
	# régler : la jumelle suit, la masse et la poussée suivent
	ed.regler(ids[0], "poussee_kn", 400.0)
	var v2 = VaisseauPhysique.new(ed.plan())
	var r2: Dictionary = ed.element(ids[1])["reglages"]
	var pn := 0.0
	for m in v2.moteurs:
		if String(m["id"]) == ids[1] + "/poussee":
			pn = float(m["poussee_n"])
	ok = float(r2["poussee_kn"]) == 400.0 and pn == 400000.0 and absf(v2.masse - v0.masse - 3600.0) < 0.01
	_resultat(ok, "Régler une pièce : sa jumelle suit", "poussée de la jumelle %.0f kN, masse ajoutée %.0f kg (2 × 400 kN × 4,5 kg/kN)" % [pn / 1000.0, v2.masse - v0.masse])
	# déplacer : la jumelle aussi, de l'autre côté
	ed.placer(ids[0], Transform3D(Basis.IDENTITY, Vector3(2.5, -0.3, 2.0)), "Aile_bas_droit", "aile_bas_droit")
	var e2b: Dictionary = ed.element(ids[1])
	ok = Catalogue.vecteur(e2b["position"]).distance_to(Vector3(-2.5, -0.3, 2.0)) < 1e-4 and String(e2b["articulation"]) == "aile_bas_gauche"
	_resultat(ok, "Déplacer une pièce : sa jumelle suit", "jumelle en %s sur %s" % [Analyse.vecteur_txt(e2b["position"]), e2b.get("fixe_a", "")])
	# annuler tout, refaire tout : on retrouve exactement les mêmes plans
	var texte_fin := JSON.stringify(ed.donnees)
	var n := 0
	while ed.annuler():
		n += 1
	var texte_debut := JSON.stringify(ed.donnees)
	var depart := JSON.stringify(Plan.par_defaut().donnees)
	var m_debut: float = VaisseauPhysique.new(ed.plan()).masse
	var k := 0
	while ed.refaire():
		k += 1
	ok = n == 3 and k == 3 and JSON.stringify(ed.donnees) == texte_fin and absf(m_debut - v0.masse) < 1e-6 \
		and texte_debut.replace("Chasseur v27 modifié", "Chasseur v27") == depart
	_resultat(ok, "Annuler / refaire (Ctrl + Z / Ctrl + Y)", "%d annulés → vaisseau de départ (%.1f kg) ; %d refaits → le même plan qu'avant" % [n, m_debut, k])
	# enlever : une pièce part avec sa jumelle ; un module entier ; le cockpit ne s'enlève pas
	var ed3 = _ed_depart()
	var paire: Array = ed3.ajouter("propulseur", {}, Transform3D(Basis.IDENTITY, Vector3(1.0, 0.8, 0.0)), "Fuselage", "", true)
	var enleves: int = ed3.supprimer([paire[1]])
	var reste_ajouts: int = ed3.ajouts().size()
	var avant: int = ed3.plan().pieces.size()
	var n_train: int = ed3.supprimer(["module:train_avant"])
	var p3 = ed3.plan()
	var v3 = VaisseauPhysique.new(p3)
	var n_cockpit: int = ed3.supprimer(["module:cockpit", "Verriere"])
	ok = enleves == 2 and reste_ajouts == 0 and n_train == 6 and p3.valide() and p3.pieces.size() == avant - n_train \
		and v3.roues.size() == 2 and n_cockpit == 0 and not ed3.element("Verriere").is_empty()
	_resultat(ok, "Enlever : une pièce et sa jumelle, un module entier", "pièce + jumelle : %d enlevées (%d restent) ; module « train avant » : %d pièces enlevées (%d → %d), %d roues restent ; cockpit : %d (le pilote est dedans)" % [
		enleves, reste_ajouts, n_train, avant, p3.pieces.size(), v3.roues.size(), n_cockpit])
	# le vaisseau du jeu ne s'écrase jamais : le vaisseau changé prend un autre nom
	ok = String(ed3.nom()) == "Chasseur v27 modifié" and ed3.chemin == "" and ed3.modifie
	ed3.renommer("Mon chasseur")
	ok = ok and ed3.nom() == "Mon chasseur"
	_resultat(ok, "Le vaisseau du jeu reste intact", "après un changement : « Chasseur v27 modifié » (pas encore de fichier) ; renommé « %s »" % ed3.nom())


# =====================================================================
# ÉTAPE 3 — C. ENREGISTRER : plusieurs vaisseaux, chacun son nom
# =====================================================================
func _vider_dossier(dossier: String) -> void:
	var d := DirAccess.open(dossier)
	if d == null:
		return
	for f in d.get_files():
		d.remove(f)
	DirAccess.remove_absolute(dossier)


func _tests_fichiers() -> void:
	_vider_dossier(DOSSIER_ESSAI)
	var ed = _ed_depart()
	ed.ajouter("moteur_ionique", {"poussee_kn": 300.0}, Transform3D(Basis(Vector3.UP, 0.4), Vector3(2.0, -0.4, 2.2)), "Aile_bas_droit", "aile_bas_droit", true)
	ed.ajouter("reservoir", {"contenu": "air"}, Transform3D(Basis.IDENTITY, Vector3(0.0, -0.9, 1.0)), "Fuselage")
	ed.supprimer(["module:canons"])
	var err: Error = ed.enregistrer(DOSSIER_ESSAI)
	var chemin: String = ed.chemin
	var relu = Plan.new()
	var lu: bool = relu.charger(chemin)
	var v1 = VaisseauPhysique.new(ed.plan())
	var v2 = VaisseauPhysique.new(relu)
	var ed_relu = Edition.new(relu.donnees, chemin)
	var ok: bool = err == OK and lu and chemin == DOSSIER_ESSAI + "chasseur_v27_modifie.plan.json" and not ed.modifie \
		and absf(v1.masse - v2.masse) < 1e-6 and v1.centre_gravite.distance_to(v2.centre_gravite) < 1e-6 \
		and v1.inertie.distance_to(v2.inertie) < 1e-3 and v1.moteurs.size() == v2.moteurs.size() and ed_relu.ajouts().size() == 3 \
		and int(relu.donnees.get("version", 0)) == Plan.VERSION
	_resultat(ok, "Enregistrer puis relire un vaisseau", "%s : %.1f kg relus (%.1f), %d moteurs, %d pièces posées, version %d du plan" % [
		chemin.get_file(), v2.masse, v1.masse, v2.moteurs.size(), ed_relu.ajouts().size(), int(relu.donnees.get("version", 0))])
	# renommer : le fichier suit le nom (l'ancien part) ; un autre vaisseau du même nom n'est jamais écrasé
	ed.renommer("Éclair d'été")
	ed.enregistrer(DOSSIER_ESSAI)
	var renomme: String = ed.chemin
	var ancien_parti := not FileAccess.file_exists(chemin)
	var autre = _ed_depart()
	autre.renommer("Éclair d'été")
	autre.enregistrer(DOSSIER_ESSAI)
	ok = renomme == DOSSIER_ESSAI + "eclair_d_ete.plan.json" and ancien_parti and autre.chemin == DOSSIER_ESSAI + "eclair_d_ete_2.plan.json" \
		and FileAccess.file_exists(renomme)
	# copie : un nouveau fichier, l'original reste
	ed.enregistrer_copie(DOSSIER_ESSAI)
	ok = ok and ed.chemin != renomme and FileAccess.file_exists(renomme) and FileAccess.file_exists(ed.chemin) and ed.nom() == "Éclair d'été (copie)"
	_resultat(ok, "Plusieurs vaisseaux, chacun son nom", "%s → %s (l'ancien fichier est parti) ; même nom : %s ; copie : %s" % [
		chemin.get_file(), renomme.get_file(), autre.chemin.get_file(), ed.chemin.get_file()])
	# le fichier se lit à l'œil : listes de nombres sur une ligne
	var texte := FileAccess.get_file_as_string(renomme)
	ok = texte.contains("\"position\": [") and not texte.contains("[\n\t\t\t\t\t2") and texte.length() > 1000
	_resultat(ok, "Fichier du vaisseau lisible", "%d caractères, nombres groupés : %s" % [texte.length(), texte.substr(texte.find("\"position\""), 40).replace("\n", " ")])


# =====================================================================
# ÉTAPE 3 — D. LE DESSIN (le même dans l'atelier et dans le jeu)
# =====================================================================
func _tests_dessin() -> void:
	var ed = _ed_depart()
	var ids: Array = ed.ajouter("moteur_ionique", {"poussee_kn": 200.0}, Transform3D(Basis.IDENTITY, Vector3(2.6, -0.45, 2.4)), "Aile_bas_droit", "aile_bas_droit", true)
	ed.ajouter("propulseur", {}, Transform3D(Basis.IDENTITY, Vector3(0.0, 1.2, -1.0)), "Fuselage")
	ed.supprimer(["module:aile_haut_gauche", "module:rcs_nez_haut", "module:droide"])
	var p = ed.plan()
	var v = VaisseauPhysique.new(p)
	var ext: Node3D = (load("res://modeles/vaisseau/vaisseau_exterieur.glb") as PackedScene).instantiate()
	var dr: Node3D = (load("res://modeles/vaisseau/droide.glb") as PackedScene).instantiate()
	(ext.find_child("Point_droide", true, false) as Node3D).add_child(dr)
	var mv = ModeleVaisseau.new(ext, v)
	var d = DessinVaisseau.new(ext, mv, dr)
	d.construire(p, v)
	var caches: Array = d.caches.map(func(m): return String(m.name))
	var ok: bool = caches.has("Aile_haut_gauche") and caches.has("Lueur_moteur_aile_haut_gauche") and caches.has("Panache_moteur_aile_haut_gauche") \
		and caches.has("Emplacement_droide") and not dr.visible and not caches.has("Aile_haut_droit") and not caches.has("Fuselage") \
		and (caches.has("Lueur_rcs_nez_haut") or caches.has("Lueur_rcs_nez_bas"))
	_resultat(ok, "Dessin : un module enlevé disparaît (avec ses lueurs et ses jets)", "cachés : %s ; droïde caché : %s" % [", ".join(caches), not dr.visible])
	# les pièces posées : dessinées, leurs lueurs et jets reliés au bon moteur de la physique
	var par_id := {}
	for t in v.moteurs + v.rcs:
		par_id[String(t["id"])] = t
	var relies := 0
	var brillants := 0
	for id in d.lueurs_ajouts:
		for mi in d.lueurs_ajouts[id]:
			brillants += 1
			if par_id.has(String(mi.get_meta("extras", {}).get("id_physique", ""))):
				relies += 1
	ok = d.ajouts.size() == 3 and brillants == 6 and relies == 6 and (d.maillages_ajouts[ids[0]] as Array).size() >= 3
	_resultat(ok, "Dessin : pièces posées, lueurs et jets reliés à leur moteur", "%d pièces dessinées, %d lueurs et jets, %d reliés à la physique" % [d.ajouts.size(), brillants, relies])
	# un moteur posé sur une aile la suit : dessin et physique au même endroit, ailes ouvertes et repliées
	var ecarts := []
	ok = true
	for ailes in [1.0, 0.0, 0.5]:
		v.ailes = ailes
		mv.poser(v)
		var n: Node3D = d.ajouts[ids[1]]
		var dessine: Vector3 = DessinVaisseau._relatif(n, ext).origin
		var physique: Vector3 = v.transformation_articulation("aile_bas_gauche") * Catalogue.vecteur(ed.element(ids[1])["position"])
		var poussee := {}
		for m in v.moteurs:
			if m["id"] == ids[1] + "/poussee":
				poussee = m
		v._placer_propulseurs()
		var tuyere_dessin: Vector3 = DessinVaisseau._relatif(n, ext) * Vector3(0, 0, Pieces.dimensions_ionique(200.0).y * 0.5)
		var e := dessine.distance_to(physique) + tuyere_dessin.distance_to(poussee["position"])
		ok = ok and e < 1e-3
		ecarts.append("ailes %.1f : %.2f mm" % [ailes, e * 1000.0])
	_resultat(ok, "Dessin : une pièce posée sur une aile suit l'aile", ", ".join(ecarts))
	ext.free()


# =====================================================================
# ÉTAPE 3 — E. VAISSEAUX LIMITES : rien ne casse
# =====================================================================
func _tests_vaisseaux_limites() -> void:
	var ed = _ed_depart()
	var mods: Array = ed.modules().keys()
	ed.supprimer(mods.map(func(m): return "module:" + m))
	var p = ed.plan()
	var v = VaisseauPhysique.new(p)
	v.gm = GRAVITE_SURFACE * RAYON_PLANETE * RAYON_PLANETE
	v.rayon_planete = RAYON_PLANETE
	v.poser_au_sol(Vector3.UP, Vector3.FORWARD, 1.0)
	var a = Analyse.new(p)
	var t: Dictionary = a.tableau()
	var finis: bool = is_finite(v.masse) and is_finite(v.centre_gravite.length()) and is_finite(v.py) and is_finite(v.inertie.length()) \
		and is_finite(float(t["poussee_poids"])) and is_finite(v.couple_max.length())
	v.commander(1.0, 0.5, 0.5, 0.5)
	for i in 120:
		v.pas(1.0 / 120.0)
	finis = finis and is_finite(v.py) and is_finite(v.omega.length())
	var ok: bool = p.valide() and finis and v.moteurs.is_empty() and v.masse > 0.0 and a.tuiles().size() == 8
	_resultat(ok, "Vaisseau limite : rien que le cockpit", "%d pièces, %.0f kg, aucun moteur ; posé, 1 s de vol à fond : tout reste fini (%s)" % [
		p.pieces.size(), v.masse, "oui" if finis else "NON"])
	# un seul moteur, loin du centre : le tableau le dit (couple trop fort pour les propulseurs ?)
	var ed2 = _ed_depart()
	ed2.supprimer(["module:moteur_central", "module:aile_haut_gauche", "module:aile_haut_droit", "module:aile_bas_gauche", "module:aile_bas_droit"])
	ed2.ajouter("moteur_ionique", {"poussee_kn": 600.0}, Transform3D(Basis.IDENTITY, Vector3(3.0, 0.0, 2.0)), "Fuselage")
	var a2 = Analyse.new(ed2.plan())
	var t2: Dictionary = a2.tableau()
	ok = is_finite(float(t2["poussee_avant"])) and float(t2["decalage_poussee"]) > 1.0 and not bool(t2["couple_compense"]) \
		and float(t2["poussee_avant"]) < 600000.0 and float(t2["poussee_avant"]) > 0.0
	_resultat(ok, "Vaisseau limite : un seul moteur sur le côté", "poussée à %.2f m du centre de gravité ; les propulseurs compensent : %s ; poussée utilisable sans partir en vrille %.0f kN sur 600 (%d moteur principal)" % [
		float(t2["decalage_poussee"]), "oui" if bool(t2["couple_compense"]) else "non", float(t2["poussee_avant"]) / 1000.0, int(t2["moteurs_principaux"])])


# =====================================================================
# ÉTAPE 3 — F. LE CALCUL DE LA POSE (grille, orientation, contact)
# =====================================================================
func _tests_pose_calcul() -> void:
	# repère aligné sur la surface : l'axe d'attache suit la normale, les autres restent droits
	var ok := true
	var lignes := []
	for n in [Vector3.UP, Vector3.DOWN, Vector3.RIGHT, Vector3.LEFT, Vector3(0.6, 0.8, 0.0), Vector3(0.0, 0.6, -0.8)]:
		for axe in 3:
			var b: Basis = AtelierScript.base_alignee(axe, n)
			var orth: bool = absf(b.x.dot(b.y)) < 1e-5 and absf(b.x.dot(b.z)) < 1e-5 and absf(b.y.dot(b.z)) < 1e-5 \
				and absf(absf(b.determinant()) - 1.0) < 1e-5 and b[axe].distance_to(n.normalized()) < 1e-5
			ok = ok and orth
	# une aile posée à gauche est l'image en miroir de l'aile posée à droite
	var droite: Basis = AtelierScript.base_alignee(0, Vector3.RIGHT)
	var gauche: Basis = AtelierScript.base_alignee(0, Vector3.LEFT)
	ok = ok and droite.determinant() > 0.0 and gauche.determinant() < 0.0 and gauche.y.is_equal_approx(Vector3.UP) and droite.y.is_equal_approx(Vector3.UP)
	lignes.append("repères droits pour 6 surfaces × 3 axes ; aile à gauche = miroir de l'aile à droite")
	# grille de 10 cm le long de la surface, sans quitter son plan
	var g: Vector3 = AtelierScript.sur_grille(Vector3(0.537, 1.0, -2.461), Vector3.UP)
	ok = ok and g.distance_to(Vector3(0.5, 1.0, -2.5)) < 1e-6
	var n2 := Vector3(0.0, 0.6, -0.8)
	var g2: Vector3 = AtelierScript.sur_grille(Vector3(0.33, 1.0, 1.0), n2)
	ok = ok and absf((g2 - Vector3(0.33, 1.0, 1.0)).dot(n2)) < 1e-6
	lignes.append("grille : (0,537 ; 1 ; −2,461) → %s" % Analyse.vecteur_txt(g))
	# rotation par pas de 15° autour de la normale
	var b0: Basis = AtelierScript.orientation_pose("propulseur", Vector3.UP, Vector3i.ZERO)
	var b1: Basis = AtelierScript.orientation_pose("propulseur", Vector3.UP, Vector3i(1, 0, 0))
	var angle := rad_to_deg(b0.z.angle_to(b1.z))
	ok = ok and absf(angle - 15.0) < 1e-3 and b1.y.is_equal_approx(Vector3.UP)
	lignes.append("R : %.1f° autour de la normale" % angle)
	_resultat(ok, "Pose : orientation, grille de 10 cm, pas de 15°", " ; ".join(lignes))


# =====================================================================
# ÉTAPE 3 — G. L'ÉCRAN : poser, pièce qui flotte, Lancer refusé, enlever, enregistrer
# =====================================================================
func _attendre_atelier() -> void:
	for i in 2:
		await get_tree().process_frame
	for i in 5:
		await get_tree().physics_frame


## Rayon (repère du monde) qui tombe d'en haut sur le centre d'un maillage, ou qui vient de côté.
static func _rayon_vers(mi: MeshInstance3D, dir: Vector3) -> Array:
	var c: Vector3 = (mi.global_transform * mi.get_aabb()).get_center()
	return [c - dir.normalized() * 30.0, dir.normalized()]


func _tests_ecran_etape3() -> void:
	_vider_dossier(DOSSIER_ESSAI)
	var at = (load(SCENE_ATELIER) as PackedScene).instantiate()
	at.dossier_vaisseaux = DOSSIER_ESSAI
	add_child(at)
	await _attendre_atelier()
	at.case_symetrie.button_pressed = true
	var n_pieces: int = at.plan.pieces.size()
	var masse0: float = at.analyse.masse_totale
	# 1. poser un propulseur sur l'aile haute droite (repliée dans le hangar), à la souris : sa jumelle part
	#    sur l'aile haute gauche
	at.commencer_pose("propulseur", {})
	var aile: MeshInstance3D = at.maillages["Aile_haut_droit"][0]
	var r: Array = _rayon_vers(aile, Vector3.DOWN)
	at.calculer_pose_rayon(r[0], r[1])
	var pose_ok: bool = bool(at.pose["touche"]) and String(at.pose["fixe_a"]) == "Aile_haut_droit" and String(at.pose["articulation"]) == "aile_haut_droit"
	var fantome_vert: bool = at._fantome != null and at._fantome.visible and at._fantome_jumeau.visible
	at.valider_pose()
	await _attendre_atelier()
	var ajouts: Array = at.edition.ajouts()
	var ok: bool = pose_ok and fantome_vert and ajouts.size() == 2 and at.plan.pieces.size() == n_pieces + 4 and at.pose.is_empty() \
		and at.analyse.masse_totale > masse0 and at.nb_flottantes == 0 and at.maillages.has(String(ajouts[0]["id"])) \
		and String(at.selection.get("id", "")) == String(ajouts[0]["id"]) and at.fiche.visible
	_resultat(ok, "Écran : poser une pièce à la souris (avec sa jumelle)", "posée sur %s (aile repliée), jumelle sur %s ; %d pièces posées, masse %.1f → %.1f kg ; rien ne flotte : %s ; fiche « %s »" % [
		ajouts[0].get("fixe_a", "?") if ajouts.size() > 0 else "?", ajouts[1].get("fixe_a", "?") if ajouts.size() > 1 else "?", ajouts.size(),
		masse0, at.analyse.masse_totale, at.nb_flottantes == 0, at.fiche_titre.text])
	# le dessin de la pièce posée est cliquable
	var id1 := String(ajouts[0]["id"]) if ajouts.size() > 0 else ""
	var mi1: MeshInstance3D = at.maillages[id1][0] if at.maillages.has(id1) else null
	var touche := ""
	if mi1 != null:
		var r1: Array = _rayon_vers(mi1, Vector3.DOWN)
		var rr: Dictionary = at._rayon_monde(r1[0], r1[1])
		touche = String(rr["collider"].get_meta("piece", "")) if not rr.is_empty() else ""
	_resultat(touche == id1, "Écran : une pièce posée se choisit d'un clic", "sous la souris : « %s »" % touche)
	# 2. une pièce posée dans le vide : rouge, et « Lancer » refusé
	at.commencer_pose("boite", {})
	var haut_pilote: Vector3 = at.pilote.global_position + at.corps.global_transform.basis * Vector3(7.0, 4.0, 0.0)
	at.calculer_pose_rayon(haut_pilote - Vector3(0, 0, 40.0), Vector3(0, 0, 1))   # passe loin au-dessus de l'aile : ne touche rien
	var rouge_fantome: bool = not bool(at.pose["touche"]) and (at._fantome.get_child(0) as MeshInstance3D).material_override == at._materiau_fantome_rouge
	at.valider_pose()
	await _attendre_atelier()
	var boite_id := ""
	for e in at.edition.ajouts():
		if e["modele"] == "boite":
			boite_id = String(e["id"])
	var mb: MeshInstance3D = at.maillages[boite_id][0] if at.maillages.has(boite_id) else null
	at.deselectionner()
	var rouge: bool = mb != null and mb.material_overlay == at._materiau_flotte
	var lance := true
	if at.nb_flottantes > 0:   # sinon « Lancer » partirait vraiment dans le jeu
		lance = await at.lancer_jeu()
	ok = rouge_fantome and at.nb_flottantes == 2 and at.flottantes.has(boite_id) and rouge and not lance and at.avis.visible \
		and not at.chargement.visible
	_resultat(ok, "Écran : une pièce qui ne touche rien est rouge, « Lancer » refusé", "fantôme rouge : %s ; %d pièces flottent (la boîte et sa jumelle), dessinées en rouge : %s ; Lancer : %s (« %s »)" % [
		rouge_fantome, at.nb_flottantes, rouge, "refusé" if not lance else "ACCEPTÉ", at.texte_avis.text.left(70)])
	# 3. Ctrl + Z : la pièce part, plus rien ne flotte
	at.annuler()
	await _attendre_atelier()
	ok = at.edition.ajouts().size() == 2 and at.nb_flottantes == 0
	_resultat(ok, "Écran : annuler (Ctrl + Z)", "%d pièces posées, %d flotte(nt)" % [at.edition.ajouts().size(), at.nb_flottantes])
	# 4. enlever un module : le train avant ; le vaisseau se repose (sur son nez), la pièce sur l'aile tient toujours
	var roue: MeshInstance3D = at.maillages["Roue_avant"][0]
	at.choisir("module", "train_avant")
	var orange: bool = roue.material_overlay == at._materiau_surligne
	at.supprimer_selection()
	await _attendre_atelier()
	ok = orange and not at.maillages.has("Roue_avant") and roue.mesh == null and at.vaisseau_pose.roues.size() == 2 \
		and at.vaisseau_pose.au_sol and is_finite(at.vaisseau_pose.py) and at.nb_flottantes == 0
	_resultat(ok, "Écran : enlever un module du chasseur", "train avant enlevé (roue cachée : %s) ; posé sur %d roues et la coque : %s ; rien ne flotte : %s" % [
		roue.mesh == null, at.vaisseau_pose.roues.size(), at.vaisseau_pose.au_sol, at.nb_flottantes == 0])
	at.annuler()
	await _attendre_atelier()
	ok = at.maillages.has("Roue_avant") and roue.mesh != null and at.vaisseau_pose.roues.size() == 3 and absf(at.hauteur_roues()) < 0.02
	_resultat(ok, "Écran : le module revient (Ctrl + Z)", "roue avant de retour, posé sur 3 roues (%.1f mm du sol)" % (at.hauteur_roues() * 1000.0))
	# 5. sans fuselage, tout le reste tombe : en rouge
	at.choisir("module", "fuselage")
	at.supprimer_selection()
	await _attendre_atelier()
	var n_flotte: int = at.nb_flottantes
	var aile_rouge: bool = (at.maillages["Aile_bas_droit"][0] as MeshInstance3D).material_overlay == at._materiau_flotte
	at.annuler()
	await _attendre_atelier()
	_resultat(n_flotte > 10 and aile_rouge and at.nb_flottantes == 0, "Écran : sans fuselage, le reste ne tient plus", "%d modules et pièces flottent, ailes en rouge : %s ; remis : %d" % [
		n_flotte, aile_rouge, at.nb_flottantes])
	# 6. régler dans la fiche : le tableau ingénieur suit
	at.choisir("ajout", id1)
	var spin: SpinBox = null
	for c in at.fiche_outils.find_children("*", "SpinBox", true, false):
		spin = c
		break
	var tuile_avant := String((at.tableau.get_child(0).find_children("*", "Label", true, false)[1] as Label).text)
	var case_trouvee := spin != null
	if case_trouvee:
		spin.value = 12.0
	await _attendre_atelier()
	var tuile_apres := String((at.tableau.get_child(0).find_children("*", "Label", true, false)[1] as Label).text)
	var reglage: float = float(at.edition.element(id1)["reglages"]["poussee_kn"])
	ok = case_trouvee and absf(reglage - 12.0) < 1e-6 and tuile_avant != tuile_apres
	_resultat(ok, "Écran : régler une pièce dans sa fiche", "poussée %.3f kN (case trouvée : %s) ; masse du tableau %s → %s" % [reglage, case_trouvee, tuile_avant, tuile_apres])
	# 7. déplacer (G) : la pièce et sa jumelle changent de place ensemble
	at.deplacer_selection()
	var fus: MeshInstance3D = at.maillages["Fuselage"][0]
	var b_fus: AABB = fus.global_transform * fus.get_aabb()
	at.calculer_pose_rayon(b_fus.get_center() + Vector3(0.6, 30.0, 0.0), Vector3.DOWN)
	var sur := String(at.pose.get("fixe_a", ""))
	at.valider_pose()
	await _attendre_atelier()
	var e1: Dictionary = at.edition.element(id1)
	var e2: Dictionary = at.edition.element(String(e1.get("symetrique", "")))
	ok = sur != "" and not sur.begins_with("Aile") and String(e1.get("fixe_a", "")) == sur and not e2.is_empty() \
		and String(e2.get("fixe_a", "")) == sur \
		and absf(Catalogue.vecteur(e1["position"]).x + Catalogue.vecteur(e2["position"]).x) < 1e-5 and at.nb_flottantes == 0
	_resultat(ok, "Écran : déplacer une pièce (G)", "maintenant sur %s, en %s ; jumelle en %s" % [e1.get("fixe_a", ""),
		Analyse.vecteur_txt(e1.get("position", [0, 0, 0])), Analyse.vecteur_txt(e2.get("position", [0, 0, 0]))])
	# 8. enregistrer (Ctrl + S) : fichier écrit, c'est lui que le jeu chargera
	var enregistre: bool = at.enregistrer()
	var chemin: String = at.edition.chemin
	ok = enregistre and FileAccess.file_exists(chemin) and Partie.plan_choisi() == chemin and not at.edition.modifie \
		and chemin.begins_with(DOSSIER_ESSAI)
	_resultat(ok, "Écran : enregistrer", "%s (le jeu prendra ce vaisseau)" % chemin.get_file())
	at.queue_free()
	await get_tree().process_frame


# =====================================================================
# ÉTAPE 4 : L'ANALYSE INGÉNIEUR
# =====================================================================
func _tests_analyse_etape4() -> void:
	var a = Analyse.new(Plan.par_defaut())
	var v = a.v
	var tous: Array = a.plan.pieces.map(func(p): return p["id"])
	# 1. tout le vaisseau choisi = le vaisseau (masse, centre de gravité, inertie : la physique du jeu)
	var g: Dictionary = a.analyse_groupe(tous)
	var ib: Basis = g["inertie"]
	var ok: bool = absf(float(g["masse"]) - v.masse) < 1e-6 and ((g["centre"] as Vector3) - v.centre_gravite).length() < 1e-6 \
		and float(g["masse_sans"]) == 0.0 and absf(float(g["part"]) - 1.0) < 1e-9 \
		and Vector3(ib.x.x, ib.y.y, ib.z.z).distance_to(v.inertie) < 1e-6 * v.inertie.length()
	_resultat(ok, "Analyse : tout choisir = le vaisseau", "%.1f kg, centre %s, inertie %.0f / %.0f / %.0f kg·m² (physique : %.0f / %.0f / %.0f)" % [
		g["masse"], Analyse.vecteur_txt(g["centre"]), ib.x.x, ib.y.y, ib.z.z, v.inertie.x, v.inertie.y, v.inertie.z])
	# 2. « le vaisseau sans elle » = ce que donne la physique quand on l'enlève vraiment
	var ga: Dictionary = a.analyse_groupe(a.pieces_module("aile_haut_droit"))
	var ed = _ed_depart()
	ed.supprimer(["module:aile_haut_droit"])
	var v2 = VaisseauPhysique.new(ed.plan())
	ok = absf(v2.masse - float(ga["masse_sans"])) < 1e-6 and (v2.centre_gravite - (ga["centre_sans"] as Vector3)).length() < 1e-6 \
		and absf(float(ga["masse"]) + float(ga["masse_sans"]) - v.masse) < 1e-6 and (ga["deplacement"] as Vector3).x < -0.1
	_resultat(ok, "Analyse : le vaisseau sans une aile", "aile %.1f kg ; sans elle %.1f kg (physique %.1f), centre de gravité qui %s (physique : %s)" % [
		ga["masse"], ga["masse_sans"], v2.masse, Analyse.deplacement_txt(ga["deplacement"]), Analyse.deplacement_txt(v2.centre_gravite - v.centre_gravite)])
	# 3. répartition des masses : catégories et matières font chacune 100 %, les plus lourdes en premier
	var r: Dictionary = a.repartition_masses()
	var somme_cat := 0.0
	for c in r["par_categorie"]:
		somme_cat += float(c["masse"])
	var somme_mat := 0.0
	for c in r["par_matiere"]:
		somme_mat += float(c["masse"])
	var lourdes: Array = r["lourdes"]
	var range_ok := true
	for k in range(1, lourdes.size()):
		range_ok = range_ok and float(lourdes[k - 1]["masse"]) >= float(lourdes[k]["masse"])
	var f: Dictionary = a.fiche_masses()
	ok = absf(somme_cat - v.masse) < 1e-6 and absf(somme_mat - v.masse) < 1e-3 and range_ok and lourdes.size() == 15 \
		and (f["sections"] as Array).size() == 3 and String(f["sections"][0]["liste"][0]["choix"]["genre"]) == "categorie"
	_resultat(ok, "Analyse : répartition des masses", "catégories %.1f kg, matières %.1f kg (vaisseau %.1f) ; la plus lourde : %s (%s)" % [
		somme_cat, somme_mat, v.masse, lourdes[0]["nom"], Analyse._kg_part(lourdes[0])])
	# 4. poussées : 5 moteurs principaux, leurs couples font le couple du tableau ; chaque petit propulseur a un rôle
	var po: Dictionary = a.poussees()
	var somme_c := Vector3.ZERO
	for d in po["principaux"]:
		somme_c += d["couple"] as Vector3
	var n_roles := 0
	for g2 in po["roles"]:
		n_roles += (g2["ids"] as Array).size()
	var fp: Dictionary = a.fiche_poussees()
	var section_moteurs: Array = (fp["sections"] as Array).filter(func(x): return String(x["titre"]).begins_with("MOTEURS PRINCIPAUX"))
	ok = (po["principaux"] as Array).size() == 5 and absf(float(po["total"]) - 1.0e6) < 1.0 and somme_c.distance_to(po["couple"]) < 1.0 \
		and n_roles == v.rcs.size() and (po["axes"] as Array).size() == 3 and section_moteurs.size() == 1 \
		and (section_moteurs[0]["liste"] as Array).size() == 5 and bool(po["compense"])
	_resultat(ok, "Analyse : poussées et couple, moteur par moteur", "%d moteurs, %.0f kN ; couple %.0f N·m (somme des moteurs %.0f) ; %d propulseurs en %d rôles ; tangage %.0f %%, lacet %.0f %%, roulis %.0f %% de ce que les propulseurs compensent" % [
		(po["principaux"] as Array).size(), float(po["total"]) / 1000.0, (po["couple"] as Vector3).length(), somme_c.length(), n_roles,
		(po["roles"] as Array).size(), 100.0 * float(po["axes"][0]["part"]), 100.0 * float(po["axes"][1]["part"]), 100.0 * float(po["axes"][2]["part"])])
	# 5. symétrie du chasseur : centré ; seules quelques pièces du cockpit (manche, levier) et des buses sans jumelle
	var s: Dictionary = a.symetrie()
	var sans: Array = s["sans_jumelle"]
	var t8: Array = a.tuiles()[7]
	ok = absf(float(s["cg_x"])) < 0.001 and sans.has("Manche_piece") and sans.has("Levier_gaz_piece") and sans.size() <= 4 \
		and String(t8[0]) == "SYMÉTRIE" and String(t8[1]) == "centrée" and absf(float(s["poussee_gauche"]) - float(s["poussee_droite"])) < 1.0
	_resultat(ok, "Analyse : symétrie du chasseur", "centre de gravité à %.2f mm du milieu ; sans jumelle : %s ; tuile « %s »" % [
		float(s["cg_x"]) * 1000.0, ", ".join(sans), t8[1]])
	# 6. un moteur posé d'un seul côté : défaut de symétrie, et le vaisseau tourne vers la gauche (couple de
	#    lacet positif : moteur à droite qui pousse vers l'avant), plus que les propulseurs ne compensent.
	#    Le couple est moins que 200 kN × 3 m : le centre de gravité part aussi à droite, et les 5 moteurs du
	#    milieu, maintenant à sa gauche, tournent un peu dans l'autre sens.
	var ed3 = _ed_depart()
	var ids3: Array = ed3.ajouter("moteur_ionique", {"poussee_kn": 200.0}, Transform3D(Basis.IDENTITY, Vector3(3.0, 0.0, 2.0)), "Fuselage")
	var a3 = Analyse.new(ed3.plan())
	var s3: Dictionary = a3.symetrie()
	var t3: Dictionary = a3.tableau()
	var c3: Vector3 = t3["couple_moteurs"]
	var dans_liste: bool = (s3["elements"] as Array).any(func(e): return e["genre"] == "ajout" and e["id"] == ids3[0])
	ok = ids3.size() == 1 and float(s3["cg_x"]) > 0.01 and dans_liste and String(a3.tuiles()[7][1]).ends_with("à droite") \
		and absf(float(s3["poussee_droite"]) - float(s3["poussee_gauche"]) - 2.0e5) < 1.0 and c3.y > 1.0e5 and not bool(t3["couple_compense"]) \
		and float(a3.poussees()["axes"][1]["part"]) > 1.0
	_resultat(ok, "Analyse : un moteur d'un seul côté", "centre de gravité %s à droite ; tuile « %s » ; poussée droite − gauche %.0f kN ; couple de lacet %.0f kN·m (vers la gauche), compensé : %s" % [
		Analyse.longueur_txt(float(s3["cg_x"])), a3.tuiles()[7][1], (float(s3["poussee_droite"]) - float(s3["poussee_gauche"])) / 1000.0, c3.y / 1000.0, t3["couple_compense"]])
	# 7. la flèche courbe du couple tourne dans le bon sens (règle de la main droite), plus grande pour un plus gros couple
	var bons := 0
	for c in [Vector3(0, 0, 8000.0), Vector3(0, -2.0e5, 0), Vector3(3.0e4, 1.0e4, -5.0e3)]:
		var fc: Node3D = AtelierScript.fleche_couple(Vector3(1, 2, 3), c, Color.RED)
		var mp: Node3D = fc.get_child(1)
		var tangente: Vector3 = mp.transform.basis.y.normalized()
		var radial: Vector3 = (mp.position - tangente * 0.21 - Vector3(1, 2, 3)).normalized()
		if c.normalized().cross(radial).dot(tangente) > 0.99 and absf(radial.dot(c.normalized())) < 1e-3:
			bons += 1
		fc.free()
	ok = bons == 3 and AtelierScript.rayon_couple(1.0e3) < AtelierScript.rayon_couple(1.0e5) and AtelierScript.rayon_couple(1.0e5) < AtelierScript.rayon_couple(1.0e7)
	_resultat(ok, "Analyse : flèche du couple", "%d / 3 flèches dans le sens de rotation ; rayon %.2f / %.2f / %.2f m pour 1 kN·m / 100 kN·m / 10 MN·m" % [
		bons, AtelierScript.rayon_couple(1.0e3), AtelierScript.rayon_couple(1.0e5), AtelierScript.rayon_couple(1.0e7)])
	# 8. l'analyse de la symétrie reste rapide sur un gros vaisseau (300 pièces posées en plus)
	var ed4 = _ed_depart()
	for k in 150:
		ed4.ajouter("boite", {}, Transform3D(Basis.IDENTITY, Vector3(0.5 + 0.05 * k, -0.5, 4.0 - 0.05 * k)), "Fuselage", "", true)
	var a4 = Analyse.new(ed4.plan())
	var t0 := Time.get_ticks_usec()
	var s4: Dictionary = a4.symetrie()
	var ms := (Time.get_ticks_usec() - t0) / 1000.0
	ok = a4.plan.pieces.size() > 400 and ms < 250.0 and absf(float(s4["cg_x"])) < 0.001
	_resultat(ok, "Analyse : symétrie d'un gros vaisseau", "%d pièces analysées en %.0f ms ; centre de gravité à %.2f mm du milieu" % [a4.plan.pieces.size(), ms, float(s4["cg_x"]) * 1000.0])


static func _clic_gauche() -> InputEventMouseButton:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	return ev


static func _touche(code: Key) -> InputEventKey:
	var ev := InputEventKey.new()
	ev.keycode = code
	ev.pressed = true
	return ev


static func _textes_tuile(t: Control) -> Array:
	return t.find_children("*", "Label", true, false).map(func(l): return String((l as Label).text))


func _tests_ecran_etape4() -> void:
	_vider_dossier(DOSSIER_ESSAI)
	var at = (load(SCENE_ATELIER) as PackedScene).instantiate()
	at.dossier_vaisseaux = DOSSIER_ESSAI
	add_child(at)
	await _attendre_atelier()
	at.case_symetrie.button_pressed = true
	# 1. Ctrl + clic : les deux ailes du haut ensemble ; leur centre de gravité (boule bleue) est au milieu
	at.choisir("piece", "Aile_haut_droit")
	at.basculer_dans_selection("piece", "Aile_haut_gauche")
	var ids: Array = at.pieces_choisies()
	var orange: bool = (at.maillages["Aile_haut_droit"][0] as MeshInstance3D).material_overlay == at._materiau_surligne \
		and (at.maillages["Aile_haut_gauche"][0] as MeshInstance3D).material_overlay == at._materiau_surligne
	var ok: bool = String(at.selection.get("genre", "")) == "groupe" and ids.size() == 2 and at.fiche_titre.text.begins_with("Sélection : 2") \
		and orange and at._cg_selection.visible and absf(at._cg_selection.position.x) < 0.01 and at.fiche_sections.get_child_count() >= 3
	_resultat(ok, "Écran : choisir plusieurs pièces (Ctrl + clic)", "« %s » ; deux ailes en orange : %s ; leur centre de gravité à %.1f cm du milieu" % [
		at.fiche_titre.text, orange, at._cg_selection.position.x * 100.0])
	# un vrai Ctrl + clic dans la vue ajoute la pièce sous la souris ; un second Ctrl + clic l'enlève
	at.camera.vue("dessus")
	await _attendre_atelier()
	var fus: MeshInstance3D = at.maillages["Fuselage"][0]
	var pos: Vector2 = at.camera.unproject_position((fus.global_transform * fus.get_aabb()).get_center())
	var sous: String = at.piece_sous(pos)
	at._demande_clic = pos
	at._demande_clic_ctrl = true
	await _attendre_atelier()
	var avec: bool = at.selection.get("genre", "") == "groupe" and (at.selection["elements"] as Array).size() == 3
	at._demande_clic = pos
	at._demande_clic_ctrl = true
	await _attendre_atelier()
	var sans: bool = at.selection.get("genre", "") == "groupe" and (at.selection["elements"] as Array).size() == 2
	_resultat(sous != "" and avec and sans, "Écran : Ctrl + clic dans la vue", "sous la souris : « %s » ; ajoutée : %s, retirée : %s" % [sous, avec, sans])
	at.camera.vue("trois_quarts")
	# 2. un clic sur une tuile ouvre sa page détaillée
	var tuiles_ok: bool = at.tableau.get_child_count() == 9   # (étape 5 : 9e tuile, AVANT LE VOL)
	(at.tableau.get_child(7) as Control).gui_input.emit(_clic_gauche())
	var page_sym: bool = at.selection == {"genre": "analyse", "id": "symetrie"} and at.fiche.visible and at.fiche_titre.text == "Symétrie gauche-droite"
	var manche_orange: bool = not at.maillages.has("Manche_piece") or (at.maillages["Manche_piece"][0] as MeshInstance3D).material_overlay == at._materiau_surligne
	(at.tableau.get_child(0) as Control).gui_input.emit(_clic_gauche())
	var page_masses: bool = at.fiche_titre.text == "Répartition des masses" and at.fiche_sections.get_child_count() > 20
	_resultat(tuiles_ok and page_sym and manche_orange and page_masses, "Écran : tuiles cliquables", "9 tuiles : %s ; « Symétrie » ouvre « %s » (manche en orange : %s) ; « Masse » ouvre « %s » (%d lignes)" % [
		tuiles_ok, "Symétrie gauche-droite" if page_sym else at.fiche_titre.text, manche_orange, at.fiche_titre.text, at.fiche_sections.get_child_count()])
	# un clic sur une ligne de la page choisit ces pièces dans le vaisseau
	var lignes: Array = at.fiche_sections.get_children().filter(func(c): return c is PanelContainer and (c as Control).mouse_filter == Control.MOUSE_FILTER_STOP)
	var derniere: Control = lignes[-1] if not lignes.is_empty() else null
	if derniere != null:
		derniere.gui_input.emit(_clic_gauche())
	ok = derniere != null and String(at.selection.get("genre", "")) in ["piece", "ajout", "module"] and at.fiche_titre.text != "Répartition des masses"
	_resultat(ok, "Écran : une ligne de la page choisit ses pièces", "%d lignes cliquables ; la dernière ouvre « %s »" % [lignes.size(), at.fiche_titre.text])
	# 3. « Poussées » : flèches de chaque moteur, et la flèche courbe du couple (violette : compensé)
	(at.tableau.get_child(1) as Control).gui_input.emit(_clic_gauche())
	var fl_c: Node3D = at._fleche_couple
	var couleur_avant := Color.BLACK
	if fl_c.get_child_count() > 0:
		couleur_avant = ((fl_c.get_child(0).get_child(0) as MeshInstance3D).material_override as StandardMaterial3D).albedo_color
	ok = at.fiche_titre.text == "Poussées et couple" and at.case_poussees.button_pressed and at._fleches_poussee.visible and fl_c.visible \
		and fl_c.get_child_count() == 1 and couleur_avant.b > 0.9 and at._fleches_poussee.get_child_count() == 6
	_resultat(ok, "Écran : page des poussées et flèche du couple", "« %s » ; %d flèches de poussée ; flèche du couple : %d, couleur %s" % [
		at.fiche_titre.text, at._fleches_poussee.get_child_count(), fl_c.get_child_count(), couleur_avant])
	# un gros moteur d'un seul côté : la flèche du couple devient rouge, la tuile Symétrie le dit
	at.case_symetrie.button_pressed = false
	at.edition.ajouter("moteur_ionique", {"poussee_kn": 400.0}, Transform3D(Basis.IDENTITY, Vector3(1.0, -0.2, 2.6)), "Fuselage")
	await _attendre_atelier()
	var couleur_apres := Color.BLACK
	if fl_c.get_child_count() > 0:
		couleur_apres = ((fl_c.get_child(0).get_child(0) as MeshInstance3D).material_override as StandardMaterial3D).albedo_color
	var t_sym: Array = _textes_tuile(at.tableau.get_child(7))
	ok = couleur_apres.r > 0.9 and couleur_apres.g < 0.4 and String(t_sym[1]).ends_with("à droite") and at._fleches_poussee.get_child_count() == 7
	_resultat(ok, "Écran : un moteur d'un seul côté", "flèche du couple %s ; tuile Symétrie « %s » ; %d flèches" % [couleur_apres, t_sym[1], at._fleches_poussee.get_child_count()])
	at.annuler()
	await _attendre_atelier()
	at.case_symetrie.button_pressed = true
	# 4. la salle à part : l'aile haute droite seule, le reste du vaisseau et le hangar disparaissent
	at.choisir("module", "aile_haut_droit")
	var masse_aile: float = float(at.analyse._masse_de(at.analyse.pieces_module("aile_haut_droit"))[0])
	var aile: MeshInstance3D = at.maillages["Aile_haut_droit"][0]
	var calques_fus: int = fus.layers
	var calques_aile: int = aile.layers
	var cam_avant: Vector3 = at.camera.global_position
	at.entrer_salle()
	await _attendre_atelier()
	var t0: Array = _textes_tuile(at.tableau.get_child(0))
	var r_fus: Array = _rayon_vers(fus, Vector3.DOWN)
	var touche_fus: Dictionary = at._rayon_monde(r_fus[0], r_fus[1])
	var r_aile: Array = _rayon_vers(aile, Vector3.DOWN)
	var touche_aile: Dictionary = at._rayon_monde(r_aile[0], r_aile[1])
	var aile_touchee: bool = not touche_aile.is_empty() and String(touche_aile["collider"].get_meta("piece", "")) == "Aile_haut_droit"
	var cible_ok: bool = at.camera.cible.distance_to((aile.global_transform * aile.get_aabb()).get_center()) < 2.0
	ok = not at.salle.is_empty() and at.hangar.en_salle and not at.hangar.sol.visible and at.hangar.salle.visible and at.bandeau_salle.visible \
		and fus.layers == 1 << (AtelierScript.CALQUE_CACHE - 1) and aile.layers == calques_aile and touche_fus.is_empty() and aile_touchee \
		and String(t0[0]) == "MASSE DU MORCEAU" and String(t0[1]) == "%s kg" % Analyse.nombre(masse_aile, 1) and cible_ok \
		and at._centre_gravite.position.length() > 0.5
	_resultat(ok, "Écran : la salle à part", "« %s » ; fuselage caché : %s, aile visible : %s ; la souris ne touche que l'aile : %s ; tuile « %s : %s » ; caméra sur l'aile : %s" % [
		at.texte_salle.text, fus.layers != calques_fus, aile.layers == calques_aile, touche_fus.is_empty() and aile_touchee, t0[0], t0[1], cible_ok])
	# poser une pièce dans la salle : elle y entre (sa jumelle, sur l'autre aile, reste cachée avec le vaisseau)
	at.commencer_pose("propulseur", {})
	at.calculer_pose_rayon(r_aile[0], r_aile[1])
	var sur := String(at.pose.get("fixe_a", ""))
	at.valider_pose()
	await _attendre_atelier()
	var ici := ""
	var la_bas := ""
	for e in at.edition.ajouts():
		if String(e.get("fixe_a", "")) == "Aile_haut_droit":
			ici = String(e["id"])
		elif String(e.get("fixe_a", "")) == "Aile_haut_gauche":
			la_bas = String(e["id"])
	var m_ici: MeshInstance3D = at.maillages[ici][0] if at.maillages.has(ici) else null
	var m_la: MeshInstance3D = at.maillages[la_bas][0] if at.maillages.has(la_bas) else null
	var t0b: Array = _textes_tuile(at.tableau.get_child(0))
	ok = sur == "Aile_haut_droit" and m_ici != null and m_la != null and (at.salle["cles"] as Dictionary).has(ici) \
		and m_ici.layers != 1 << (AtelierScript.CALQUE_CACHE - 1) and m_la.layers == 1 << (AtelierScript.CALQUE_CACHE - 1) \
		and String(t0b[1]) == "%s kg" % Analyse.nombre(masse_aile + at.analyse.masse_ajout(ici), 1)
	_resultat(ok, "Écran : poser une pièce dans la salle à part", "posée sur %s, dans la salle : %s ; jumelle cachée : %s ; masse du morceau %s" % [
		sur, (at.salle.get("cles", {}) as Dictionary).has(ici), m_la != null and m_la.layers == 1 << (AtelierScript.CALQUE_CACHE - 1), t0b[1]])
	# un clic sur une tuile de la salle : la fiche du morceau
	(at.tableau.get_child(0) as Control).gui_input.emit(_clic_gauche())
	var fiche_morceau: bool = at.selection == {"genre": "module", "id": "aile_haut_droit"}
	# 5. I : remettre en place ; tout revient, la pièce posée reste sur l'aile
	at._unhandled_input(_touche(KEY_I))
	await _attendre_atelier()
	var t0c: Array = _textes_tuile(at.tableau.get_child(0))
	ok = fiche_morceau and at.salle.is_empty() and not at.hangar.en_salle and at.hangar.sol.visible and not at.bandeau_salle.visible \
		and fus.layers == calques_fus and m_la.layers != 1 << (AtelierScript.CALQUE_CACHE - 1) and at.camera.global_position.distance_to(cam_avant) < 0.01 \
		and String(t0c[0]) == "MASSE" and at.edition.ajouts().size() == 2 and at._centre_gravite.position.length() < 1e-6 and at.nb_flottantes == 0
	_resultat(ok, "Écran : remettre en place (I)", "fiche du morceau : %s ; vaisseau et hangar revenus : %s ; caméra revenue : %s ; pièces posées : %d, rien ne flotte : %s" % [
		fiche_morceau, fus.layers == calques_fus and at.hangar.sol.visible, at.camera.global_position.distance_to(cam_avant) < 0.01,
		at.edition.ajouts().size(), at.nb_flottantes == 0])
	# Échap : d'abord on ne choisit plus rien, puis on sort de la salle
	at.choisir("module", "canons")
	at.entrer_salle()
	at._unhandled_input(_touche(KEY_ESCAPE))
	var encore_dedans: bool = not at.salle.is_empty() and at.selection.is_empty()
	at._unhandled_input(_touche(KEY_ESCAPE))
	_resultat(encore_dedans and at.salle.is_empty(), "Écran : Échap sort de la salle à part", "1er Échap : rien de choisi, toujours dans la salle (%s) ; 2e : dehors (%s)" % [encore_dedans, at.salle.is_empty()])
	# 6. enlever une sélection d'un coup (Suppr) : pièce posée + module ; la pièce du chasseur reste ; un Ctrl + Z remet tout
	await _attendre_atelier()
	at.choisir("ajout", ici)
	at.basculer_dans_selection("module", "canons")
	at.basculer_dans_selection("piece", "Fuselage")
	var n_avant: int = at.plan.pieces.size()
	at.supprimer_selection()
	await _attendre_atelier()
	var enleve: bool = at.edition.ajouts().is_empty() and at.analyse.pieces_module("canons").is_empty() and at.analyse.a_piece("Fuselage")
	var texte_avis: String = at.texte_avis.text
	at.annuler()
	await _attendre_atelier()
	ok = enleve and at.plan.pieces.size() == n_avant and at.edition.ajouts().size() == 2 and not at.analyse.pieces_module("canons").is_empty()
	_resultat(ok, "Écran : enlever une sélection d'un coup", "« %s » ; un Ctrl + Z : %d pièces (avant : %d)" % [texte_avis, at.plan.pieces.size(), n_avant])
	at.queue_free()
	await get_tree().process_frame



# =====================================================================
# ÉTAPE 5 — A. LE JEU DESSINE TOUT LE PLAN
# =====================================================================
## Un plan pour les essais : le chasseur de départ (moins des modules), plus des pièces posées
## ([modèle, réglages, position, rotation en degrés]) et des pièces écrites à la main (sans ensemble).
static func _plan_essai(poses: Array, bruts := [], enlever := []):
	var ed = _ed_depart()
	if not enlever.is_empty():
		ed.supprimer(enlever.map(func(m): return "module:" + m))
	var d: Dictionary = ed.donnees.duplicate(true)
	var n := 0
	for a in poses:
		n += 1
		var id := "essai_%d" % n
		var r := Pieces.reglages_complets(String(a[0]), a[1])
		var e := {"id": id, "type": "ensemble", "modele": a[0], "nom": "%s %d" % [Pieces.nom(String(a[0])), n], "reglages": r}
		var rot: Vector3 = a[3] if a.size() > 3 else Vector3.ZERO
		Edition.ecrire_xf(e, Transform3D(Basis.from_euler(rot * PI / 180.0), a[2]))
		e["pieces"] = Pieces.pieces(String(a[0]), r, id)
		(d["pieces"] as Array).append(e)
	for b in bruts:
		(d["pieces"] as Array).append(b)
	var p = Plan.new()
	p.lire_dictionnaire(d)
	return p


## Les pièces d'un modèle tout fait, écrites à la main au premier niveau du plan (déplacées de « dx »).
static func _pieces_brutes(modele: String, reglages: Dictionary, prefixe: String, dx: Vector3) -> Array:
	var liste := []
	for q in Pieces.pieces(modele, Pieces.reglages_complets(modele, reglages), ""):
		var c: Dictionary = (q as Dictionary).duplicate(true)
		c["id"] = prefixe + String(c["id"]).trim_prefix("/")
		for k in ["centre", "point", "position"]:
			if c.has(k):
				var v := _v(c[k]) + dx
				c[k] = [v.x, v.y, v.z]
		liste.append(c)
	return liste


## Une pièce du chasseur de départ (écrite dans son fichier), d'un type donné, copiée sous un autre nom.
static func _copie_piece_depart(type: String, id: String, dx: Vector3) -> Dictionary:
	var pile: Array = (Plan.par_defaut().donnees["pieces"] as Array).duplicate()
	while not pile.is_empty():
		var q = pile.pop_front()
		if not (q is Dictionary):
			continue
		if String(q.get("type", "")) == type and not q.has("articulation"):
			var c: Dictionary = (q as Dictionary).duplicate(true)
			c["id"] = id
			for k in ["centre", "point", "position"]:
				if c.has(k):
					var v := _v(c[k]) + dx
					c[k] = [v.x, v.y, v.z]
			return c
		pile.append_array(q.get("pieces", []))
	return {}


## Ce que dessine un modèle : surfaces et triangles de chaque maillage (même ceux des jets, cachés au repos).
static func _compte_reel(racine: Node) -> Dictionary:
	var r := {"surfaces": 0, "triangles": 0, "maillages": 0}
	for n in racine.find_children("*", "MeshInstance3D", true, false):
		var m := n as MeshInstance3D
		if m.mesh == null or m.is_queued_for_deletion():
			continue
		r["maillages"] += 1
		for s in m.mesh.get_surface_count():
			r["surfaces"] += 1
			var a := m.mesh.surface_get_arrays(s)
			var ix = a[Mesh.ARRAY_INDEX]
			r["triangles"] += ((ix as PackedInt32Array).size() if ix != null else (a[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()) / 3
	return r


## Sens des triangles (rapport des faces tournées vers leurs normales) : 1 = toutes, comme une boîte.
static func _faces_dehors(m: Mesh, signe_ref: float) -> float:
	var bons := 0
	var tous := 0
	for s in m.get_surface_count():
		var a := m.surface_get_arrays(s)
		var vs: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
		var ns: PackedVector3Array = a[Mesh.ARRAY_NORMAL]
		var ix: PackedInt32Array = a[Mesh.ARRAY_INDEX]
		for k in range(0, ix.size() - 2, 3):
			var c := (vs[ix[k + 1]] - vs[ix[k]]).cross(vs[ix[k + 2]] - vs[ix[k]])
			if c.length() < 1e-9:
				continue
			var n := ns[ix[k]] + ns[ix[k + 1]] + ns[ix[k + 2]]
			tous += 1
			if signf(c.dot(n)) == signe_ref:
				bons += 1
	return float(bons) / maxf(tous, 1.0)


static func _signe_boite() -> float:
	var a := BoxMesh.new().get_mesh_arrays()
	var vs: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
	var ns: PackedVector3Array = a[Mesh.ARRAY_NORMAL]
	var ix: PackedInt32Array = a[Mesh.ARRAY_INDEX]
	return signf((vs[ix[1]] - vs[ix[0]]).cross(vs[ix[2]] - vs[ix[0]]).dot(ns[ix[0]]))


func _nouveau_dessin(p, v) -> Array:
	var ext: Node3D = (load("res://modeles/vaisseau/vaisseau_exterieur.glb") as PackedScene).instantiate()
	var mv = ModeleVaisseau.new(ext, v)
	var d = DessinVaisseau.new(ext, mv, null)
	return [ext, d]


func _tests_dessin_etape5() -> void:
	# 1. des pièces écrites à la main (sans dessin Blender) : chacune est dessinée, là où la physique la voit
	var bruts := []
	bruts.append_array(_pieces_brutes("boite", {}, "brut_boite", Vector3(0.0, 2.0, 1.0)))
	bruts.append_array(_pieces_brutes("reservoir", {}, "brut_reservoir", Vector3(1.5, 1.6, 2.0)))
	bruts.append_array(_pieces_brutes("poutre", {}, "brut_poutre", Vector3(-1.5, 1.6, 2.0)))
	bruts.append_array(_pieces_brutes("plaque", {"matiere": "verre_aluminosilicate"}, "brut_vitre", Vector3(0.0, 2.6, 2.5)))
	bruts.append_array(_pieces_brutes("aile", {}, "brut_aile", Vector3(3.0, 1.0, 3.0)))
	bruts.append_array(_pieces_brutes("propulseur", {}, "brut_rcs", Vector3(0.0, 2.2, 4.0)))
	bruts.append_array(_pieces_brutes("moteur_ionique", {}, "brut_moteur", Vector3(0.0, 2.0, 6.0)))
	bruts.append(_copie_piece_depart("roue", "brut_roue", Vector3(0.0, 0.0, -2.0)))
	bruts.append(_copie_piece_depart("structure", "brut_structure", Vector3(0.0, 3.0, 0.0)))
	var p = _plan_essai([["plaque", {"matiere": "verre_aluminosilicate"}, Vector3(0.0, 1.2, 1.5)]], bruts)
	var v = VaisseauPhysique.new(p)
	var r := _nouveau_dessin(p, v)
	var ext: Node3D = r[0]
	var d = r[1]
	d.construire(p, v)
	var attendus := []
	for b in bruts:
		if DessinVaisseau.TYPES_DESSINES.has(String(b.get("type", ""))):
			attendus.append(String(b["id"]))
	var manquent := attendus.filter(func(id): return not d.bruts.has(id) or (d.maillages_bruts[id] as Array).is_empty())
	var types := {}
	for id in d.bruts:
		types[String(p.pieces.filter(func(q): return q["id"] == id)[0]["type"])] = true
	# chaque bloc, poutre ou plaque est dessiné centré sur son centre de masse (celui de la physique)
	var ecart_max := 0.0
	for q in p.pieces:
		if d.bruts.has(String(q["id"])) and String(q["type"]) in ["bloc", "poutre", "plaque"]:
			var mi: MeshInstance3D = d.maillages_bruts[String(q["id"])][0]
			var c: Vector3 = DessinVaisseau._relatif(mi, ext) * mi.get_aabb().get_center()
			ecart_max = maxf(ecart_max, c.distance_to(q["masse_calculee"]["centre"]))
	var par_id := {}
	for t in v.moteurs + v.rcs:
		par_id[String(t["id"])] = t
	var relies := 0
	var brillants := 0
	for id in d.lueurs_bruts:
		for mi in d.lueurs_bruts[id]:
			brillants += 1
			if par_id.has(String((mi as Node).get_meta("extras", {}).get("id_physique", ""))):
				relies += 1
	var ok: bool = p.valide() and manquent.is_empty() and types.size() >= 8 and ecart_max < 0.005 and brillants >= 4 and relies == brillants
	_resultat(ok, "Dessin (étape 5) : chaque pièce du plan est dessinée", "%d pièces écrites à la main dessinées (%s) ; manquent : %s ; écart au centre de masse %.1f mm ; %d lueurs et jets reliés à la physique sur %d" % [
		d.bruts.size(), ", ".join(types.keys()), manquent, ecart_max * 1000.0, relies, brillants])
	# 2. une plaque en verre est une VITRE : transparente, sans ombre ; le système de lumière en fait une vraie
	#    vitre (loi de Fresnel, comme la verrière)
	var vitres := []
	for dico in [d.maillages_bruts, d.maillages_ajouts]:
		for id in dico:
			for mi in dico[id]:
				if bool((mi as Node).get_meta("vitre", false)):
					vitres.append(mi)
	var transparentes := vitres.filter(func(mi): return ((mi as MeshInstance3D).mesh.surface_get_material(0) as BaseMaterial3D).transparency != BaseMaterial3D.TRANSPARENCY_DISABLED \
		and (mi as MeshInstance3D).cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF).size()
	var obj = Objets.new()
	obj.convertir(ext, ext)
	var vraies := vitres.filter(func(mi): return (mi as MeshInstance3D).get_surface_override_material(0) is ShaderMaterial \
		and ((mi as MeshInstance3D).get_surface_override_material(0) as ShaderMaterial).shader == Objets.ShaderVitre).size()
	obj.liberer()
	ok = vitres.size() == 2 and transparentes == 2 and vraies == 2 and int(DessinVaisseau.compter(p)["vitres"]) == 2
	_resultat(ok, "Dessin (étape 5) : une plaque en verre est une vraie vitre", "%d vitres (une posée, une écrite à la main) : transparentes et sans ombre %d, vraies vitres du système de lumière %d" % [
		vitres.size(), transparentes, vraies])
	ext.free()
	# 3. FUSION (jeu) : les pièces posées de même matière ne font plus qu'un maillage ; les triangles sont les
	#    mêmes, une pièce vue en miroir (jumelle) garde ses faces dehors, et les lueurs restent reliées
	var ed = _ed_depart()
	for k in 12:
		ed.ajouter("boite", {}, Transform3D(Basis.IDENTITY, Vector3(-1.5 + 0.25 * k, 1.4, 1.0 + 0.1 * k)), "Fuselage")
	ed.ajouter("poutre", {}, Transform3D(Basis.from_euler(Vector3(0.3, 0.5, 0.2)), Vector3(1.2, 1.0, 2.0)), "Fuselage", "", true)
	ed.ajouter("reservoir", {}, Transform3D(Basis.from_euler(Vector3(0.0, 0.4, 0.0)), Vector3(1.4, 0.4, 3.0)), "Fuselage", "", true)
	ed.ajouter("moteur_ionique", {"poussee_kn": 150.0}, Transform3D(Basis.IDENTITY, Vector3(2.6, -0.45, 2.4)), "Aile_bas_droit", "aile_bas_droit", true)
	ed.ajouter("plaque", {"matiere": "verre_aluminosilicate"}, Transform3D(Basis.IDENTITY, Vector3(0.0, 1.3, 2.5)), "Fuselage")
	var p2 = ed.plan()
	var v2 = VaisseauPhysique.new(p2)
	var r1 := _nouveau_dessin(p2, v2)
	var r2 := _nouveau_dessin(p2, v2)
	(r1[1]).construire(p2, v2)
	(r2[1]).construire(p2, v2, true)
	var c1 := _compte_reel(r1[0])
	var c2 := _compte_reel(r2[0])
	var d2 = r2[1]
	var signe := _signe_boite()
	var pire := 1.0
	for fm in d2.fusions:
		pire = minf(pire, _faces_dehors((fm as MeshInstance3D).mesh, signe))
	var lueurs_ok := true
	var nb_lueurs := 0
	for id in d2.lueurs_ajouts:
		for mi in d2.lueurs_ajouts[id]:
			nb_lueurs += 1
			lueurs_ok = lueurs_ok and is_instance_valid(mi) and not (mi as Node).is_queued_for_deletion() and (mi as Node).get_meta("extras", {}).has("id_physique")
	var pieces_posees: int = ed.ajouts().size()
	var gain: int = int(c1["surfaces"]) - int(c2["surfaces"])
	ok = c1["triangles"] == c2["triangles"] and gain >= pieces_posees and pire > 0.999 and lueurs_ok and nb_lueurs == 4 and d2.fusions.size() < pieces_posees
	_resultat(ok, "Dessin (étape 5) : le jeu fusionne les pièces posées", "%d pièces posées : %d surfaces → %d (%d maillages fusionnés), triangles %d → %d ; faces dehors (jumelles en miroir comprises) : %.1f %% ; %d lueurs et jets toujours reliés : %s" % [
		pieces_posees, c1["surfaces"], c2["surfaces"], d2.fusions.size(), c1["triangles"], c2["triangles"], pire * 100.0, nb_lueurs, lueurs_ok])
	# 4. le COMPTE (contrôle avant le vol) dit exactement ce que la carte graphique dessinera, avec et sans fusion
	var k1: Dictionary = DessinVaisseau.compter(p2, false)
	var k2: Dictionary = DessinVaisseau.compter(p2, true)
	var k0: Dictionary = DessinVaisseau.compter(Plan.par_defaut())
	var r0 := _nouveau_dessin(Plan.par_defaut(), VaisseauPhysique.new(Plan.par_defaut()))
	var c0 := _compte_reel(r0[0])
	ok = k1["surfaces"] == c1["surfaces"] and k1["triangles"] == c1["triangles"] and k2["surfaces"] == c2["surfaces"] and k2["triangles"] == c2["triangles"] \
		and k0["surfaces"] == c0["surfaces"] and k0["triangles"] == c0["triangles"]
	_resultat(ok, "Dessin (étape 5) : le compte des surfaces et triangles est exact", "chasseur %d surfaces / %d triangles (dessiné : %d / %d) ; avec les pièces posées : sans fusion %d / %d (dessiné %d / %d), fusionné %d / %d (dessiné %d / %d)" % [
		k0["surfaces"], k0["triangles"], c0["surfaces"], c0["triangles"], k1["surfaces"], k1["triangles"], c1["surfaces"], c1["triangles"],
		k2["surfaces"], k2["triangles"], c2["surfaces"], c2["triangles"]])
	for x in [r0, r1, r2]:
		(x[0] as Node).free()


# =====================================================================
# ÉTAPE 5 — B. LE CONTRÔLE AVANT LE VOL
# =====================================================================
static func _trouve(c, niveau: String, debut: String) -> Dictionary:
	for e in c.elements:
		if e["niveau"] == niveau and String(e["titre"]).begins_with(debut):
			return e
	return {}


static func _resume(c) -> String:
	return "; ".join(c.elements.filter(func(e): return e["niveau"] != ControleVol.OK).map(func(e): return "%s %s" % [ControleVol.symbole(e["niveau"]), e["titre"]]))


func _tests_controle_vol() -> void:
	# 1. le chasseur de départ : prêt (ni blocage ni avertissement), environ 60 images/s, il tient sur ses roues
	var t0 := Time.get_ticks_msec()
	var c = ControleVol.new(Plan.par_defaut())
	var duree := Time.get_ticks_msec() - t0
	var parts: Array = c.sol.get("parts", [])
	var ok: bool = not c.bloque() and not c.avertit() and c.tuile()[1] == "prêt" and float(c.charge["ips"]) >= 59.0 and bool(c.sol["stable"]) \
		and parts.size() == 3 and absf(float(parts[0]) + float(parts[1]) + float(parts[2]) - 1.0) < 1e-6 and float(parts[0]) < float(parts[1])
	_resultat(ok, "Contrôle avant le vol : le chasseur de départ est prêt", "%s ; ≈ %d images/s ; part du poids sur les roues %s ; pour information : %s (%d ms)" % [
		c.tuile()[1], roundi(float(c.charge["ips"])), parts.map(func(x): return "%.0f %%" % (100.0 * x)), _resume(c), duree])
	# 2. les couleurs de toutes les matières, et celles des pièces toutes faites, existent sous une vraie
	#    lumière (entre le charbon et la neige) : poser une pièce du catalogue ne fait jamais d'avertissement
	var hors := []
	var couleurs := []
	for m in Catalogue.MATIERES:
		couleurs.append([m, Pieces._couleur(m)])
	for modele in Pieces.MODELES:
		for fo in Pieces.dessin(modele, {}):
			if String(fo["role"]) == "":
				couleurs.append([modele, fo["couleur"]])
	for cc in couleurs:
		var col := (cc[1] as Color).srgb_to_linear()
		var y := 0.2126 * col.r + 0.7152 * col.g + 0.0722 * col.b
		if y < ControleVol.ALBEDO_MIN or y > ControleVol.ALBEDO_MAX:
			hors.append("%s %.3f" % [cc[0], y])
	_resultat(hors.is_empty(), "Contrôle avant le vol : les couleurs sont possibles", "%d couleurs (%d matières, et les pièces toutes faites) entre %.2f et %.2f d'albédo ; hors bornes : %s" % [
		couleurs.size(), Catalogue.MATIERES.size(), ControleVol.ALBEDO_MIN, ControleVol.ALBEDO_MAX, hors])
	# 3. AU SOL : un lest à l'arrière le fait basculer ; un lest énorme écrase les amortisseurs ; deux roues, pas de train
	var cg: Vector3 = VaisseauPhysique.new(Plan.par_defaut()).centre_gravite
	var lest_arriere := {"id": "lest", "type": "masse", "masse_kg": 40000.0, "centre": [0.0, 0.0, 10.0]}
	var c_bascule = ControleVol.new(_plan_essai([], [lest_arriere]))
	var lest_lourd := {"id": "lest", "type": "masse", "masse_kg": 80000.0, "centre": [cg.x, cg.y, cg.z]}
	var c_butee = ControleVol.new(_plan_essai([], [lest_lourd]))
	var c_deux = ControleVol.new(_plan_essai([], [], ["train_avant"]))
	var c_sans = ControleVol.new(_plan_essai([], [], ["train_avant", "train_arriere_gauche", "train_arriere_droit"]))
	var bascule := _trouve(c_bascule, ControleVol.AVERTIT, "Il bascule vers l'arrière")
	var butees: int = c_butee.elements.filter(func(e): return e["niveau"] == ControleVol.AVERTIT and String(e["titre"]).ends_with("amortisseur en butée")).size()
	ok = not bascule.is_empty() and butees == 3 and not _trouve(c_deux, ControleVol.AVERTIT, "Seulement 2 roues").is_empty() \
		and not _trouve(c_sans, ControleVol.AVERTIT, "Pas de train").is_empty() and not c_bascule.bloque() and not c_sans.bloque()
	_resultat(ok, "Contrôle avant le vol : au sol", "lest de 40 t à l'arrière : « %s » (%s) ; 80 t au centre : %d amortisseurs en butée ; sans train avant : %s ; sans train : %s" % [
		bascule.get("titre", "RIEN"), bascule.get("valeur", ""), butees, _resume(c_deux), _resume(c_sans)])
	# 4. LUMIÈRE : une boîte posée sur le nez, devant la verrière : la vue du pilote est cachée
	var c_vue = ControleVol.new(_plan_essai([["boite", {"hauteur_m": 0.6}, Vector3(0.0, 0.7, -2.4)]]))
	var vue := _trouve(c_vue, ControleVol.AVERTIT, "Boîte")
	var c_cote = ControleVol.new(_plan_essai([["boite", {}, Vector3(0.0, -0.8, 3.5)]]))
	ok = not vue.is_empty() and String(vue["titre"]).ends_with("devant la verrière") and String(vue["choix"].get("id", "")) == "essai_1" \
		and _trouve(c_cote, ControleVol.AVERTIT, "Boîte").is_empty() and not c_cote.avertit()
	_resultat(ok, "Contrôle avant le vol : une pièce devant la verrière", "boîte sur le nez : « %s » ; boîte sous le ventre : %s" % [
		vue.get("titre", "RIEN"), _resume(c_cote) if c_cote.avertit() else "rien à dire"])
	# 5. EN VOL : sans ailes (et leurs moteurs), ni moteur central, ni levage : aucun moteur principal, et il ne
	#    quitte pas le sol ; sans le seul moteur central, il ne décolle plus à la verticale (pour information)
	var c_sol = ControleVol.new(_plan_essai([], [], ["aile_haut_gauche", "aile_haut_droit", "aile_bas_gauche", "aile_bas_droit", "moteurs_levage", "moteur_central"]))
	var sol_e := _trouve(c_sol, ControleVol.AVERTIT, "Il ne peut pas quitter le sol")
	var sans_m := _trouve(c_sol, ControleVol.AVERTIT, "Aucun moteur principal")
	var c_moteur = ControleVol.new(_plan_essai([], [], ["moteur_central"]))
	ok = not sol_e.is_empty() and not sans_m.is_empty() and not c_sol.bloque() and c_moteur.nombre_de(ControleVol.BLOQUE) == 0 \
		and not _trouve(c_moteur, ControleVol.INFO, "Pas de décollage vertical").is_empty()
	_resultat(ok, "Contrôle avant le vol : en vol", "sans ailes, moteur central ni levage : %s (« %s ») ; sans moteur central : %s" % [_resume(c_sol), sol_e.get("texte", "RIEN"), _resume(c_moteur)])
	# 6. VITESSE DU PC : 520 petites boîtes de même matière (fusionnées : le PC suit) ; un vaisseau de 33 m ;
	#    1 000 plaques de verre (chaque vitre coûte : trop lourd, le vol est bloqué)
	var poses := []
	for k in 520:
		poses.append(["boite", {"largeur_m": 0.2, "hauteur_m": 0.2, "longueur_m": 0.2, "masse_kg": 5.0},
			Vector3(-5.0 + 0.5 * (k % 21), -2.0 - 0.3 * (k / 210), -6.0 + 0.5 * ((k / 21) % 10))])
	t0 = Time.get_ticks_msec()
	var c_520 = ControleVol.new(_plan_essai(poses))
	var duree_520 := Time.get_ticks_msec() - t0
	var e520 := _trouve(c_520, ControleVol.AVERTIT, "520 pièces posées")
	var c_long = ControleVol.new(_plan_essai([["boite", {}, Vector3(0.0, 0.5, 18.0)], ["boite", {}, Vector3(0.0, 0.5, -14.0)]]))
	var e_long := _trouve(c_long, ControleVol.AVERTIT, "33")
	var vitres := []
	for k in 1000:
		vitres.append(["plaque", {"matiere": "verre_aluminosilicate", "longueur_m": 0.3, "largeur_m": 0.3}, Vector3(-5.0 + 0.4 * (k % 25), 3.0 + 0.2 * (k / 250), -5.0 + 0.4 * ((k / 25) % 10))])
	var c_vitres = ControleVol.new(_plan_essai(vitres))
	var trop := _trouve(c_vitres, ControleVol.BLOQUE, "Trop lourd")
	var compte: Dictionary = c_520.charge["compte"]
	var sans_fusion: Dictionary = c_520.charge["sans_fusion"]
	ok = not e520.is_empty() and float(c_520.charge["ips"]) >= ControleVol.IPS_AVERTIT and not c_520.bloque() and int(compte["surfaces"]) * 5 < int(sans_fusion["surfaces"]) \
		and not e_long.is_empty() and not trop.is_empty() and c_vitres.bloque() and float(c_vitres.charge["ips"]) < float(c_520.charge["ips"]) \
		and c_vitres.tuile()[1] == "BLOQUÉ"
	_resultat(ok, "Contrôle avant le vol : vitesse du PC", "520 boîtes : « %s », ≈ %d images/s (%d surfaces au lieu de %d grâce à la fusion, contrôle en %d ms) ; %s ; 1 000 vitres : « %s »" % [
		e520.get("titre", "RIEN"), roundi(float(c_520.charge["ips"])), compte["surfaces"], sans_fusion["surfaces"], duree_520, e_long.get("titre", "RIEN"), trop.get("titre", "RIEN")])
	# 7. PLAN : un plan illisible, et des pièces qui flottent (vues par l'atelier, ou enregistrées par lui)
	var illisible = Plan.new()
	illisible.lire_texte("{\"format\": \"plan-vaisseau\", \"pieces\": [{\"id\": \"x\", \"type\": \"inconnu\"}]}")
	var c_ill = ControleVol.new(illisible)
	var c_flotte = ControleVol.new(_plan_essai([["boite", {}, Vector3(0.0, 6.0, 0.0)]]), null, {"flottantes": ["essai_1"]})
	var p_enr = _plan_essai([["boite", {}, Vector3(0.0, 6.0, 0.0)]])
	p_enr.donnees["atelier"] = {"flottantes": ["essai_1"]}
	var c_enr = ControleVol.new(p_enr)
	var c_fuselage = ControleVol.new(_plan_essai([], [], ["fuselage"]))
	var fl := _trouve(c_flotte, ControleVol.BLOQUE, "1 pièce ne touche rien")
	ok = c_ill.bloque() and c_ill.tuile()[1] == "BLOQUÉ" and not fl.is_empty() and String(fl["choix"].get("id", "")) == "essai_1" and c_enr.bloque() \
		and c_fuselage.bloque() and not ControleVol.new(_plan_essai([["boite", {}, Vector3(0.0, 6.0, 0.0)]])).bloque()
	_resultat(ok, "Contrôle avant le vol : ce qui bloque le départ", "plan illisible : %s ; boîte qui flotte : « %s » ; enregistrée par l'atelier : %s ; sans fuselage : %s" % [
		_resume(c_ill), fl.get("titre", "RIEN"), _resume(c_enr), _resume(c_fuselage).left(90)])
	# 8. la page du contrôle : une section par sujet, chaque ligne expliquée
	var f: Dictionary = c_vue.fiche()
	var titres: Array = (f["sections"] as Array).map(func(sct): return sct["titre"])
	var expliquees := true
	for sct in f["sections"]:
		for l in sct["liste"]:
			expliquees = expliquees and String(l.get("detail", "")) != "" and l.has("couleur")
	ok = f["titre"] == "Contrôle avant le vol" and titres.has("VITESSE DU PC") and titres.has("LUMIÈRE") and titres.has("AU SOL") and titres.has("EN VOL") and expliquees
	_resultat(ok, "Contrôle avant le vol : sa page", "« %s » : %s ; chaque ligne expliquée : %s" % [f["titre"], ", ".join(titres), expliquees])


# =====================================================================
# ÉTAPE 5 — C. DANS L'ÉCRAN : tuile, page, fenêtre de Lancer, Jouer de l'accueil
# =====================================================================
static func _boutons(n: Node) -> Array:
	return n.find_children("*", "Button", true, false).map(func(b): return (b as Button).text)


func _tests_ecran_etape5() -> void:
	_vider_dossier(DOSSIER_ESSAI)
	Engine.set_meta("partie", {"plan": Plan.PLAN_PAR_DEFAUT, "depart": "", "plan_lu": true})
	var at = (load(SCENE_ATELIER) as PackedScene).instantiate()
	at.dossier_vaisseaux = DOSSIER_ESSAI
	add_child(at)
	await _attendre_atelier()
	at.case_symetrie.button_pressed = false
	# 1. la 9e tuile : AVANT LE VOL, « prêt » pour le chasseur de départ ; un clic ouvre la page du contrôle
	var tuile: Control = at.tableau.get_child(8)
	var textes: Array = tuile.find_children("*", "Label", true, false).map(func(l): return (l as Label).text)
	tuile.gui_input.emit(_clic_gauche())
	var ok: bool = at.tableau.get_child_count() == 9 and textes[0] == "AVANT LE VOL" and textes[1] == "prêt" and at.fiche_titre.text == "Contrôle avant le vol" \
		and at.fiche_sections.get_child_count() > 8
	_resultat(ok, "Écran (étape 5) : la tuile AVANT LE VOL", "« %s » ; un clic ouvre « %s » (%d lignes)" % [" / ".join(textes), at.fiche_titre.text, at.fiche_sections.get_child_count()])
	# 2. une boîte posée (à la souris) sur le nez, devant la verrière : la tuile avertit, « Lancer » ouvre la
	#    fenêtre du contrôle (avec « Lancer quand même »), sans partir
	at.commencer_pose("boite", {"hauteur_m": 0.6})
	var haut: Vector3 = at.corps.global_transform * Vector3(0.0, 6.0, -2.4)
	at.calculer_pose_rayon(haut, -(at.corps.global_transform.basis.y.normalized()))
	var touche: bool = bool(at.pose.get("touche", false))
	at.valider_pose()
	await _attendre_atelier()
	await _attendre_atelier()
	textes = (at.tableau.get_child(8) as Control).find_children("*", "Label", true, false).map(func(l): return (l as Label).text)
	at.deselectionner()
	var lance: bool = await at.lancer_jeu()
	var fenetre: Control = at.fenetre_controle
	var boutons: Array = _boutons(fenetre) if fenetre != null else []
	ok = touche and at.nb_flottantes == 0 and textes[1] == "1 avertissement" and not lance and fenetre != null and fenetre.is_inside_tree() \
		and boutons.has("▶  Lancer quand même") and not at.chargement.visible
	_resultat(ok, "Écran (étape 5) : Lancer avec un avertissement", "boîte posée sur le nez (touche : %s, flotte : %d) ; tuile « %s » ; Lancer : %s ; fenêtre : %s" % [
		touche, at.nb_flottantes, textes[1], "PARTI" if lance else "pas parti", boutons])
	# « Voir le détail » ferme la fenêtre et ouvre la page ; la boîte est en orange
	var voir: Button = null
	for b in fenetre.find_children("*", "Button", true, false):
		if (b as Button).text == "Voir le détail":
			voir = b
	var a_voir := voir != null
	if a_voir:
		voir.pressed.emit()   # (le bouton part avec la fenêtre)
	await get_tree().process_frame
	var boite_id := ""
	for e in at.edition.ajouts():
		boite_id = String(e["id"])
	var orange: bool = at.maillages.has(boite_id) and (at.maillages[boite_id][0] as MeshInstance3D).material_overlay == at._materiau_surligne
	ok = a_voir and at.fenetre_controle == null and at.fiche_titre.text == "Contrôle avant le vol" and orange
	_resultat(ok, "Écran (étape 5) : la fenêtre mène au détail", "fiche « %s » ; boîte en orange : %s" % [at.fiche_titre.text, orange])
	# 3. une boîte dans le vide : « Lancer » refusé, la fenêtre n'a pas de « Lancer quand même »
	at.commencer_pose("boite", {})
	at.calculer_pose_rayon(at.corps.global_transform * Vector3(9.0, 6.0, 0.0) - Vector3(0, 0, 40.0), Vector3(0, 0, 1))
	at.valider_pose()
	await _attendre_atelier()
	await _attendre_atelier()
	lance = await at.lancer_jeu()
	boutons = _boutons(at.fenetre_controle) if at.fenetre_controle != null else []
	textes = (at.tableau.get_child(8) as Control).find_children("*", "Label", true, false).map(func(l): return (l as Label).text)
	ok = not lance and at.nb_flottantes == 1 and at.fenetre_controle != null and not boutons.has("▶  Lancer quand même") and textes[1] == "BLOQUÉ" and at.avis.visible
	_resultat(ok, "Écran (étape 5) : Lancer refusé (pièce qui flotte)", "tuile « %s » ; fenêtre : %s" % [textes[1], boutons])
	# Échap ferme la fenêtre
	var ev := InputEventKey.new()
	ev.keycode = KEY_ESCAPE
	ev.pressed = true
	at._unhandled_input(ev)
	var fermee: bool = at.fenetre_controle == null
	# 4. enregistrer : le fichier garde ce que l'atelier voit flotter (pour « Jouer » de l'accueil)
	at.enregistrer()
	var j = JSON.parse_string(FileAccess.get_file_as_string(at.edition.chemin))
	var gardees: Array = (j.get("atelier", {}) as Dictionary).get("flottantes", []) if j is Dictionary else []
	var chemin: String = at.edition.chemin
	ok = fermee and gardees.size() == 1 and String(gardees[0]).begins_with("boite_")
	_resultat(ok, "Écran (étape 5) : le vaisseau enregistré garde ses pièces qui flottent", "Échap ferme la fenêtre : %s ; dans le fichier : %s" % [fermee, gardees])
	at.queue_free()
	await get_tree().process_frame
	# 5. l'accueil : « Jouer » avec ce vaisseau est refusé (fenêtre avec « Ouvrir l'atelier ») ; avec seulement
	#    un avertissement, « Jouer quand même » est proposé
	Partie.choisir_plan(chemin)
	var ac = (load(SCENE_ACCUEIL) as PackedScene).instantiate()
	add_child(ac)
	await get_tree().process_frame
	var joue: bool = ac.jouer_maintenant()
	var b1: Array = _boutons(ac.fenetre_controle) if ac.fenetre_controle != null else []
	# même vaisseau, la boîte qui flotte enlevée : il reste l'avertissement de la verrière
	var ed = Edition.new(j, chemin)
	var flotte_id := String(gardees[0]) if not gardees.is_empty() else ""
	ed.supprimer([flotte_id])
	ed.donnees["atelier"] = {"flottantes": []}
	ed.enregistrer(DOSSIER_ESSAI)
	Partie.choisir_plan(ed.chemin)
	var joue2: bool = ac.jouer_maintenant()
	var b2: Array = _boutons(ac.fenetre_controle) if ac.fenetre_controle != null else []
	ok = not joue and b1.has("Ouvrir l'atelier") and not b1.has("▶  Jouer quand même") and not joue2 and b2.has("▶  Jouer quand même") and not ac.chargement.visible
	_resultat(ok, "Écran (étape 5) : Jouer (accueil) passe par le contrôle", "boîte qui flotte : %s, fenêtre %s ; avertissement seul : %s, fenêtre %s" % [
		"PARTI" if joue else "refusé", b1, "PARTI" if joue2 else "pas parti", b2])
	ac.queue_free()
	await get_tree().process_frame
