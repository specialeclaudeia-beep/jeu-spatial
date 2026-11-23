extends RefCounted
## Écrans du cockpit, remplis en direct. Chaque écran du modèle (Ecran_*) reçoit une petite image
## dessinée par Godot (un SubViewport), redessinée 10 fois par seconde seulement, pour rester léger.
##
##   Ecran_centre          : radar des astres proches (position autour du vaisseau, distance)
##   Ecran_gauche          : état du vaisseau (ailes, train, gaz, moteurs, stabilisateur)
##   Ecran_droit           : vol (vitesses totale / horizontale / verticale, altitude, G, rotation)
##   Ecran_lateral_gauche  : système : temps (x1 à x1000, pause), cabine (pression, oxygène, fuite), vue
##   Ecran_lateral_droit   : orbite (périapside, apoapside, excentricité), sol

const PIXELS_PAR_METRE := 1500.0
const FREQUENCE := 10.0          # images par seconde pour les écrans
const VERT := Color(0.45, 1.0, 0.6)
const AMBRE := Color(1.0, 0.75, 0.3)
const ROUGE := Color(1.0, 0.4, 0.35)
const GRIS := Color(0.55, 0.65, 0.6)
const FOND := Color(0.02, 0.05, 0.04)
const DISTANCE_RADAR_MAX := 1.0e7   # m : bord du radar (10 000 km), échelle logarithmique

var ecrans := {}                 # nom -> {viewport, dessin (Control), mesh}
var infos := {}
var _temps := 0.0
var police: Font


func _init(cockpit: Node3D, parent: Node) -> void:
	police = ThemeDB.fallback_font
	for m in cockpit.find_children("Ecran_*", "MeshInstance3D", true, false):
		var e = m.get_meta("extras", {})
		var largeur := 0.25
		var hauteur := 0.16
		if e is Dictionary:
			largeur = float(e.get("largeur_m", largeur))
			hauteur = float(e.get("hauteur_m", hauteur))
		var vp := SubViewport.new()
		vp.size = Vector2i(int(largeur * PIXELS_PAR_METRE), int(hauteur * PIXELS_PAR_METRE))
		vp.transparent_bg = false
		vp.render_target_update_mode = SubViewport.UPDATE_ONCE
		var dessin := Control.new()
		dessin.size = Vector2(vp.size)
		var nom: String = m.name
		dessin.draw.connect(_dessiner.bind(nom, dessin))
		vp.add_child(dessin)
		parent.add_child(vp)
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_texture = vp.get_texture()
		(m as MeshInstance3D).set_surface_override_material(0, mat)
		ecrans[nom] = {"viewport": vp, "dessin": dessin, "mesh": m}


## infos : dictionnaire préparé par jeu.gd (voir jeu.gd, _infos_cockpit).
func mettre_a_jour(nouvelles: Dictionary, delta: float, actif: bool) -> void:
	infos = nouvelles
	_temps += delta
	if not actif or _temps < 1.0 / FREQUENCE:
		return
	_temps = 0.0
	for nom in ecrans:
		(ecrans[nom]["dessin"] as Control).queue_redraw()
		(ecrans[nom]["viewport"] as SubViewport).render_target_update_mode = SubViewport.UPDATE_ONCE


# =====================================================================
# DESSIN
# =====================================================================
func _dessiner(nom: String, c: Control) -> void:
	c.draw_rect(Rect2(Vector2.ZERO, c.size), FOND)
	if infos.is_empty():
		return
	match nom:
		"Ecran_centre": _radar(c)
		"Ecran_gauche": _etat(c)
		"Ecran_droit": _vol(c)
		"Ecran_lateral_gauche": _temps_ecran(c)
		"Ecran_lateral_droit": _orbite(c)


func _texte(c: Control, pos: Vector2, t: String, taille := 18, couleur := VERT) -> void:
	c.draw_string(police, pos, t, HORIZONTAL_ALIGNMENT_LEFT, -1, taille, couleur)


func _lignes(c: Control, titre: String, lignes: Array, taille := 19) -> void:
	_texte(c, Vector2(10, 24), titre, 16, GRIS)
	c.draw_line(Vector2(8, 32), Vector2(c.size.x - 8, 32), GRIS, 1.0)
	var y := 32.0 + taille * 1.35
	for l in lignes:
		var couleur: Color = l[1] if l.size() > 1 else VERT
		_texte(c, Vector2(10, y), String(l[0]), taille, couleur)
		y += taille * 1.35


static func distance_txt(m: float) -> String:
	if absf(m) >= 1.0e6:
		return "%.0f km" % (m / 1000.0)
	if absf(m) >= 10000.0:
		return "%.1f km" % (m / 1000.0)
	return "%.0f m" % m


func _barre(x: float, n := 10) -> String:
	var k := int(round(clampf(x, 0.0, 1.0) * n))
	return "|".repeat(k) + ".".repeat(n - k)


## Radar vu de dessus : le vaisseau au centre, l'avant vers le haut de l'écran.
## La distance est en échelle logarithmique (1 km, 100 km, 10 000 km), la hauteur est écrite à côté.
func _radar(c: Control) -> void:
	var centre := Vector2(c.size.x * 0.36, c.size.y * 0.52)
	var r_max := c.size.y * 0.44
	for d in [1.0e3, 1.0e5, 1.0e7]:
		var r := _rayon_radar(d, r_max)
		c.draw_arc(centre, r, 0.0, TAU, 48, Color(GRIS, 0.5), 1.0)
		_texte(c, centre + Vector2(3, -r + 12), distance_txt(d), 11, GRIS)
	c.draw_line(centre + Vector2(0, -r_max), centre + Vector2(0, r_max), Color(GRIS, 0.3), 1.0)
	c.draw_line(centre + Vector2(-r_max, 0), centre + Vector2(r_max, 0), Color(GRIS, 0.3), 1.0)
	c.draw_colored_polygon(PackedVector2Array([centre + Vector2(0, -7), centre + Vector2(5, 5), centre + Vector2(-5, 5)]), VERT)
	var x_liste := c.size.x * 0.72
	var y := 22.0
	_texte(c, Vector2(x_liste, y), "ASTRES", 14, GRIS)
	for a in infos.get("astres", []):
		var p: Vector3 = a["position"]          # repère du vaisseau : x droite, y haut, -z avant
		var dist: float = a["distance"]         # m jusqu'à la surface (ou au centre si pas de rayon)
		var plat := Vector2(p.x, p.z)
		var r := _rayon_radar(dist, r_max)
		var point := centre + (plat.normalized() * r if plat.length() > 1e-6 else Vector2.ZERO)
		var hauteur := rad_to_deg(atan2(p.y, plat.length()))
		var couleur := AMBRE if a.get("principal", false) else VERT
		c.draw_circle(point, 6.0, couleur)
		_texte(c, point + Vector2(8, 4), String(a["nom"]), 13, couleur)
		y += 18.0
		_texte(c, Vector2(x_liste, y), String(a["nom"]), 13, couleur)
		y += 16.0
		_texte(c, Vector2(x_liste, y), distance_txt(dist), 13, VERT)
		y += 16.0
		_texte(c, Vector2(x_liste, y), "cap %+.0f°  haut %+.0f°" % [rad_to_deg(atan2(p.x, -p.z)), hauteur], 12, VERT)


static func _rayon_radar(d: float, r_max: float) -> float:
	return r_max * clampf(log(1.0 + maxf(d, 0.0) / 100.0) / log(1.0 + DISTANCE_RADAR_MAX / 100.0), 0.0, 1.0)


func _etat(c: Control) -> void:
	var m: Array = infos.get("moteurs", [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0])
	_lignes(c, "ÉTAT DU VAISSEAU", [
		["GAZ    %s %3d %%" % [_barre(infos["gaz"]), int(round(infos["gaz"] * 100.0))]],
		["MOTEURS HG %s HD %s" % [_barre(m[0], 5), _barre(m[1], 5)]],
		["        BG %s BD %s" % [_barre(m[2], 5), _barre(m[3], 5)]],
		["        C  %s  LEVAGE %s %s" % [_barre(m[4], 5), _barre(m[5], 5), _barre(m[6], 5)]],
		["AILES  %s" % infos["ailes_txt"], VERT if infos["ailes"] >= 1.0 else AMBRE],
		["TRAIN  %s" % infos["train_txt"], AMBRE if infos["train"] > 0.0 else VERT],
		["STABILISATEUR  %s" % ("ACTIF" if infos["stabilisateur"] else "arrêt"), VERT if infos["stabilisateur"] else GRIS],
		["VOL VERTICAL   %s" % infos["vertical_txt"], AMBRE if infos["vertical"] > 0.0 else GRIS],
		["PROPULSEURS ORIENT. %d actifs" % infos.get("rcs_actifs", 0)],
	], 15)


func _vol(c: Control) -> void:
	var g: float = infos["g"]
	var w: Vector3 = infos["rotation"]
	_lignes(c, "VOL", [
		["VITESSE     %.1f m/s" % infos["vitesse"]],
		["HORIZONTALE %.1f m/s" % infos["v_horiz"]],
		["VERTICALE   %+.1f m/s" % infos["v_vert"], ROUGE if infos["v_vert"] < -50.0 and infos["altitude"] < 5000.0 else VERT],
		["ALTITUDE    %s" % distance_txt(infos["altitude"])],
		["ACCÉLÉR.    %.2f g" % g, ROUGE if g > 6.0 else (AMBRE if g > 3.0 else VERT)],
		["ROT. T %+.1f L %+.1f R %+.1f °/s" % [w.x, w.y, w.z]],
	], 17)


func _temps_ecran(c: Control) -> void:
	var lignes := [
		["TEMPS x%d" % infos["temps"], AMBRE if infos["temps"] > 1 else VERT],
		["PAUSE" if infos["pause"] else "", ROUGE],
	]
	# étape 8 : la cabine (pression, oxygène, et ce qui ne va pas)
	var cab: Dictionary = infos.get("cabine", {})
	if cab.is_empty():
		lignes.append(["CABINE --", GRIS])
		lignes.append([""])
		lignes.append([""])
	else:
		var p: float = cab["pression"]
		var ok_p := p >= 0.9 * float(cab["consigne"])
		lignes.append(["CABINE %.0f kPa" % (p / 1000.0) if p >= 10000.0 else "CABINE %.1f kPa" % (p / 1000.0),
			VERT if ok_p else (AMBRE if p > 0.5 * float(cab["consigne"]) else ROUGE)])
		var o2: float = cab["ppo2"]
		lignes.append(["O2 %.1f kPa" % (o2 / 1000.0), VERT if o2 >= 16000.0 else (AMBRE if o2 >= 10600.0 else ROUGE)])
		if float(cab["conscience"]) < INF:
			lignes.append(["HYPOXIE %d s" % ceili(float(cab["conscience"])), ROUGE])
		elif bool(cab["fuite"]):
			var t: float = cab["trou"]
			lignes.append([("FUITE %.0f cm²" % (t * 1.0e4)) if t < 0.1 else ("FUITE %.1f m²" % t), ROUGE])
		elif bool(cab["vanne"]):
			lignes.append(["VANNE OUVERTE", AMBRE])
		else:
			lignes.append(["AIR %d %%" % roundi(100.0 * float(cab["reserve"])), VERT if float(cab["reserve"]) > 0.25 else AMBRE])
	lignes.append(["VUE " + ("cockpit" if infos["vue_interieure"] else "ext.")])
	_lignes(c, "SYSTÈME", lignes, 18)


func _orbite(c: Control) -> void:
	var o: Dictionary = infos["orbite"]
	var lignes := []
	if infos["ecrase"]:
		lignes = [["ÉCRASÉ", ROUGE]]
	elif infos["au_sol"]:
		lignes = [["POSÉ", AMBRE]]
	elif o["apo"] == INF:
		lignes = [["ÉVASION", AMBRE], ["PÉRI"], [distance_txt(o["peri"])]]
	else:
		lignes = [["PÉRI"], [distance_txt(o["peri"]), ROUGE if o["peri"] < 0.0 else VERT],
			["APO"], [distance_txt(o["apo"])], ["EXC."], ["%.4f" % o["excentricite"]]]
	_lignes(c, "ORBITE", lignes, 17)
