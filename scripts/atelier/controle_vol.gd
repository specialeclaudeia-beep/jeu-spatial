extends RefCounted
## Atelier, étape 5 : le CONTRÔLE AVANT LE VOL. Avant que « Lancer » (atelier) ou « Jouer » (accueil)
## charge le jeu, on vérifie le vaisseau avec le même code que le jeu (plan, physique, dessin) :
##   - PLAN : erreurs du fichier, pièces qui ne touchent rien ;
##   - VITESSE DU PC : ce que la carte graphique devra dessiner (surfaces, triangles, vitres, comptés comme le
##     jeu les dessine, pièces posées fusionnées) et ce que coûte la physique (le calcul des poussées grandit
##     avec le nombre de moteurs et de propulseurs) → images par seconde estimées sur le PC de Gwenaël ;
##     nombre de pièces posées et longueur (limites prévues au début, Q7 : 500 pièces, 30 m) ;
##   - LUMIÈRE : couleurs que la vraie lumière ne peut pas montrer (plus blanc que la neige, plus noir que
##     le charbon), vitres, lueurs des moteurs posés (elles brillent mais n'éclairent rien : le système de
##     lumière a deux lampes, le projecteur et la lampe du cockpit), pièce devant la verrière (elle cache la
##     vue du pilote et met le cockpit à l'ombre) ;
##   - AU SOL (le vol commence posé devant le hangar) : le vaisseau tient-il sur ses roues (centre de gravité
##     au-dessus des roues), chaque amortisseur porte-t-il sa part du poids sans aller en butée ;
##   - EN VOL : moteurs, décollage, rotation possible sur chaque axe, poussée réduite par un couple ;
##   - SYMÉTRIE : centre de gravité sur le côté, pièces sans jumelle (pour information).
## Étape 6, l'ARMATURE : un morceau d'armature posé à la fois sur deux pièces qui bougent l'une par rapport
## à l'autre (une aile et le fuselage) reste avec le fuselage, et avertit (il bloquerait l'aile dans la
## réalité) ; ses connecteurs (fabriqués tout seuls) ne comptent pas dans les pièces posées ; dans l'air,
## seuls ses panneaux « portants » comptent pour l'instant (pour information).
## Chaque point a un NIVEAU (réponse de Gwenaël, Q21) :
##   - "bloque" : ce qui casserait le jeu (plan illisible, pièce qui flotte, vaisseau trop lourd pour le PC) :
##     le vol ne part pas ;
##   - "avertit" : un avertissement expliqué ; une fenêtre s'ouvre et on choisit de partir quand même ;
##   - "info" : seulement dans la page du contrôle (tuile AVANT LE VOL) ; "ok" : ce qui va bien.
## Le chasseur de départ n'a ni blocage ni avertissement : « Lancer » part tout de suite, comme avant.
##
## Les images par seconde sont une ESTIMATION à partir de la référence mesurée sur le PC de Gwenaël (le
## chasseur v27 : environ 60 images/s en cockpit). À vérifier sur le PC (compteur en haut à droite du
## cockpit, ou « -- --mesure --plan <fichier> »), puis corriger les constantes ci-dessous si besoin.

const Analyse = preload("res://scripts/atelier/analyse.gd")
const Plan = preload("res://scripts/atelier/plan.gd")
const Pieces = preload("res://scripts/atelier/pieces_toutes_faites.gd")
const Edition = preload("res://scripts/atelier/edition.gd")
const Catalogue = preload("res://scripts/atelier/catalogue.gd")
const DessinVaisseau = preload("res://scripts/dessin_vaisseau.gd")
const VaisseauPhysique = preload("res://scripts/physique/vaisseau_physique.gd")
const Style = preload("res://scripts/atelier/style.gd")
const Armature = preload("res://scripts/atelier/armature.gd")

const BLOQUE := "bloque"
const AVERTIT := "avertit"
const INFO := "info"
const OK := "ok"
const ORDRE_NIVEAUX := [BLOQUE, AVERTIT, INFO, OK]
const CATEGORIES := ["Plan", "Vitesse du PC", "Lumière", "Au sol", "En vol", "Symétrie"]

## Vitesse du PC (référence : le chasseur v27 sur le PC de Gwenaël, i3-1005G1 + Intel UHD).
const IPS_REFERENCE := 60.0          # images/s du chasseur en cockpit (objectif atteint le 19/11, synchro écran)
const PART_VAISSEAU := 0.4           # part d'une image passée à dessiner le vaisseau (40 % des appels de dessin)
const US_PAR_POUSSEE := 4.2          # µs par moteur ou propulseur et par pas de physique (mesuré : 0,33 ms le pas)
const FACTEUR_PC := 1.5              # le processeur du PC de Gwenaël, comparé à celui de la mesure
const PAS_PAR_IMAGE := 2.0           # 120 pas de physique par seconde, 60 images
const TRIANGLES_PAR_UNITE := 1000.0  # 1 000 triangles coûtent comme un appel de dessin
const POIDS_VITRE := 3.0             # une vitre relit l'image derrière elle (plus cher qu'une surface)
const IPS_AVERTIT := 50.0
const IPS_BLOQUE := 20.0             # en dessous : le jeu n'est plus jouable (et la physique ralentit)
## Limites prévues au début (Q7 : « jusqu'à 500 pièces et 30 m de long, avec un compteur qui prévient »).
const PIECES_POSEES_MAX := 500
const PIECES_POSEES_PREVIENT := 400
const LONGUEUR_MAX := 30.0
const ZONE_OMBRE_FINE := 20.0        # m : la carte d'ombre fine du Soleil (lumiere_jeu.gd, 1re zone de 200 m × 0,1)
## Lumière : un albédo (part de lumière renvoyée) au-delà de ces bornes n'existe pas pour une peinture ou un
## métal (neige fraîche : 0,9 ; charbon : 0,04). Le système de lumière calcule la vraie luminance : une pièce
## plus blanche que la neige aurait l'air d'une lampe.
const ALBEDO_MIN := 0.02
const ALBEDO_MAX := 0.9
## Vue du pilote : l'œil (cockpit, point Oeil_pilote du modèle) et ce qu'il voit par la verrière.
const OEIL_PILOTE := Vector3(0.0, 0.58, 0.38)
const VUE_LACET := 50.0              # degrés à gauche et à droite
const VUE_BAS := -4.0                # degrés (plus bas : le nez du vaisseau cache déjà la vue)
const VUE_HAUT := 32.0
const VUE_PORTEE := 40.0             # m
## Au sol : marge minimale entre le centre de gravité et le bord du polygone des roues.
const MARGE_SOL := 0.05

var plan
var analyse
var v
var options := {}
var elements: Array = []             # [{niveau, categorie, titre, texte, valeur, choix}]
var charge := {}                     # vitesse du PC (voir _vitesse_pc)
var sol := {}                        # au sol (voir _au_sol)

static var _reference := {}          # charge du chasseur de départ (calculée une fois)


## options : "flottantes" (ids des pièces qui ne touchent rien, vu par l'atelier ; sans elle : la liste
## enregistrée dans le plan par l'atelier, et les modules sans fuselage), "oeil" (Vector3).
func _init(p_plan, p_analyse = null, p_options := {}) -> void:
	plan = p_plan
	options = p_options
	elements = []
	if not plan.valide():
		_ajouter(BLOQUE, "Plan", "Le plan du vaisseau a des erreurs",
			"Le jeu ne peut pas le construire : " + "; ".join(Array(plan.erreurs).slice(0, 3)) + ".", "illisible")
		return
	analyse = p_analyse if p_analyse != null else Analyse.new(plan)
	v = analyse.v
	_plan_tient()
	_armature()
	_vitesse_pc()
	_lumiere()
	_au_sol()
	_en_vol()
	_symetrie()
	elements.sort_custom(func(a, b): return ORDRE_NIVEAUX.find(a["niveau"]) < ORDRE_NIVEAUX.find(b["niveau"]))


func _ajouter(niveau: String, categorie: String, titre: String, texte: String, valeur := "", choix := {}) -> void:
	elements.append({"niveau": niveau, "categorie": categorie, "titre": titre, "texte": texte, "valeur": valeur, "choix": choix})


func nombre_de(niveau: String) -> int:
	return elements.filter(func(e): return e["niveau"] == niveau).size()


func bloque() -> bool:
	return nombre_de(BLOQUE) > 0


func avertit() -> bool:
	return nombre_de(AVERTIT) > 0


## Ce qu'il faut montrer avant de partir (fenêtre) : les blocages, puis les avertissements.
func a_montrer() -> Array:
	return elements.filter(func(e): return e["niveau"] == BLOQUE or e["niveau"] == AVERTIT)


static func _groupe(liste: Array) -> Dictionary:
	if liste.is_empty():
		return {}
	if liste.size() == 1:
		return liste[0]
	return {"genre": "groupe", "elements": liste}


static func _pluriel(n: int, mot: String, mots := "") -> String:
	return "%d %s" % [n, mot if n <= 1 else (mots if mots != "" else mot + "s")]


# =====================================================================
# PLAN : tout tient ensemble
# =====================================================================
func _plan_tient() -> void:
	var ids: Array = []
	if options.has("flottantes"):
		ids = options["flottantes"]
	else:
		# sans l'atelier (accueil) : ce que l'atelier a vu au dernier enregistrement, et les modules du
		# chasseur qui ne tiennent plus sans fuselage
		ids = ((plan.donnees.get("atelier", {}) as Dictionary).get("flottantes", []) as Array).duplicate()
		if analyse.pieces_module("fuselage").is_empty():
			for cle in (plan.donnees.get("modules", {}) as Dictionary):
				if cle != "fuselage" and not Edition.MODULES_INDISPENSABLES.has(cle) and not analyse.pieces_module(cle).is_empty():
					ids.append("module:" + cle)
	if ids.is_empty():
		return
	var elts := []
	var vus := {}
	for i in ids:
		var s := String(i)
		var e := {}
		if s.begins_with("module:"):
			e = {"genre": "module", "id": s.substr(7)}
		elif analyse.ajouts.has(s):
			e = {"genre": "ajout", "id": s}
		elif analyse.a_piece(s):
			var p: Dictionary = analyse.piece(s)
			e = {"genre": "module", "id": String(p["module"])} if p.has("module") and not p.has("ajout") else Analyse.element_de(p)
		else:
			continue
		var cle := String(e["genre"]) + ":" + String(e["id"])
		if not vus.has(cle):
			vus[cle] = true
			elts.append(e)
	if elts.is_empty():
		return
	_ajouter(BLOQUE, "Plan", "%s ne %s rien" % [_pluriel(elts.size(), "pièce"), "touche" if elts.size() == 1 else "touchent"],
		"En rouge dans l'atelier. Une pièce qui flotte tomberait du vaisseau au départ : pose-la contre le vaisseau (G), ou enlève-la (Suppr).",
		"%d" % elts.size(), _groupe(elts))


# =====================================================================
# VITESSE DU PC
# =====================================================================
## Unités de charge du dessin : une par appel de dessin (une surface, et encore une si elle fait de
## l'ombre), plus les triangles, plus les vitres.
static func unites(c: Dictionary, ck: Dictionary) -> float:
	return float(c["surfaces"] + c["surfaces_ombre"] + ck["surfaces"] + ck["surfaces_ombre"]) \
		+ float(c["triangles"] + c["triangles_ombre"] + ck["triangles"] + ck["triangles_ombre"]) / TRIANGLES_PAR_UNITE \
		+ POIDS_VITRE * float(c["vitres"])


static func charge_reference() -> Dictionary:
	if _reference.is_empty():
		var p = Plan.par_defaut()
		var vr = VaisseauPhysique.new(p)
		_reference = {"unites": unites(DessinVaisseau.compter(p), DessinVaisseau.compter_cockpit()),
			"poussees": vr.moteurs.size() + vr.rcs.size(), "compte": DessinVaisseau.compter(p)}
	return _reference


## Images par seconde estimées sur le PC de Gwenaël pour ce vaisseau.
static func images_par_seconde(u: float, poussees: int) -> float:
	var ref := charge_reference()
	var t := (1.0 / IPS_REFERENCE) * (1.0 + PART_VAISSEAU * (u / float(ref["unites"]) - 1.0))
	t += PAS_PAR_IMAGE * FACTEUR_PC * US_PAR_POUSSEE * 1e-6 * float(poussees - int(ref["poussees"]))
	return minf(IPS_REFERENCE, 1.0 / maxf(t, 1e-4))


func _vitesse_pc() -> void:
	var c := DessinVaisseau.compter(plan)
	var ck := DessinVaisseau.compter_cockpit()
	var sans_fusion := DessinVaisseau.compter(plan, false)
	var ref := charge_reference()
	var u := unites(c, ck)
	var poussees: int = v.moteurs.size() + v.rcs.size()
	var ips := images_par_seconde(u, poussees)
	var part := u / float(ref["unites"])
	var phys_ms := PAS_PAR_IMAGE * FACTEUR_PC * US_PAR_POUSSEE * 1e-3 * float(poussees - int(ref["poussees"]))
	var longueur := _boite().size
	charge = {"compte": c, "sans_fusion": sans_fusion, "cockpit": ck, "unites": u, "part": part, "ips": ips,
		"poussees": poussees, "physique_ms": phys_ms, "pieces_posees": _nb_posees(), "taille": longueur,
		"surfaces": int(c["surfaces"]) + int(ck["surfaces"]), "triangles": int(c["triangles"]) + int(ck["triangles"])}
	var texte := "Dessin : %s %% du chasseur de départ (%s surfaces, %s triangles%s). Physique : %s moteurs et propulseurs%s. " % [
		Analyse.nombre(100.0 * part), Analyse.nombre(charge["surfaces"]), Analyse.nombre(charge["triangles"]),
		(", %s" % _pluriel(int(c["vitres"]), "vitre")) if int(c["vitres"]) > 0 else "", poussees,
		(" (+%s ms par image)" % Analyse.nombre(phys_ms, 1)) if phys_ms > 0.05 else ""]
	if int(sans_fusion["surfaces"]) > int(c["surfaces"]):
		texte += "Les pièces posées de même matière sont fusionnées : %s surfaces au lieu de %s. " % [
			Analyse.nombre(c["surfaces"]), Analyse.nombre(sans_fusion["surfaces"])]
	texte += "Estimation à vérifier sur ton PC (compteur en haut à droite dans le cockpit)."
	var valeur := "≈ %d i/s" % roundi(ips)
	if ips < IPS_BLOQUE:
		_ajouter(BLOQUE, "Vitesse du PC", "Trop lourd pour ton PC : environ %d images par seconde" % roundi(ips),
			texte + " En dessous de %d images/s, le jeu n'est plus jouable : enlève des pièces, ou donne-leur la même matière (elles sont fusionnées)." % roundi(IPS_BLOQUE), valeur)
	elif ips < IPS_AVERTIT:
		_ajouter(AVERTIT, "Vitesse du PC", "Le jeu risque de ralentir : environ %d images par seconde" % roundi(ips), texte, valeur)
	else:
		_ajouter(OK, "Vitesse du PC", "Vitesse du PC : environ %d images par seconde" % roundi(ips), texte, valeur)
	var n: int = _nb_posees()
	if n > PIECES_POSEES_MAX:
		_ajouter(AVERTIT, "Vitesse du PC", "%d pièces posées : plus que les %d prévues au début" % [n, PIECES_POSEES_MAX],
			"La limite de départ était de %d pièces posées (question 7). Le jeu peut aller au-delà si ton PC suit : essaie, et regarde le compteur d'images." % PIECES_POSEES_MAX, "%d" % n)
	elif n >= PIECES_POSEES_PREVIENT:
		_ajouter(INFO, "Vitesse du PC", "%d pièces posées sur %d prévues au début" % [n, PIECES_POSEES_MAX],
			"Tu approches de la limite de départ (question 7).", "%d / %d" % [n, PIECES_POSEES_MAX])
	var l := maxf(longueur.x, maxf(longueur.y, longueur.z))
	if l > LONGUEUR_MAX:
		_ajouter(AVERTIT, "Vitesse du PC", "%s m de long : plus que les %d m prévus au début" % [Analyse.nombre(l, 1), roundi(LONGUEUR_MAX)],
			"La limite de départ était de %d m (question 7). Au-delà de %d m de la caméra, les ombres du Soleil sont moins fines ; le hangar fait 64 m." % [roundi(LONGUEUR_MAX), roundi(ZONE_OMBRE_FINE)],
			"%s m" % Analyse.nombre(l, 1))


## Boîte (repère du plan) qui contient le vaisseau : les points des pièces et les pièces posées.
func _boite() -> AABB:
	var b := AABB()
	var premier := true
	for p in plan.pieces:
		for k in ["centre", "point", "position"]:
			if p.has(k) and p[k] is Vector3:
				if premier:
					b = AABB(p[k], Vector3.ZERO)
					premier = false
				else:
					b = b.expand(p[k])
	for id in analyse.ajouts:
		var e: Dictionary = analyse.ajouts[id]
		var bb := Analyse.boite_ajout(e)
		var xf := Edition.xf_de(e)
		for k in 8:
			b = b.expand(xf * bb.get_endpoint(k))
	return b


## Pièces posées (toutes faites, poutres et panneaux ; les connecteurs se fabriquent tout seuls).
func _nb_posees() -> int:
	return analyse.ajouts.keys().filter(func(i): return String(analyse.ajouts[i].get("modele", "")) != Armature.CONNECTEUR).size()


# =====================================================================
# ARMATURE
# =====================================================================
## Un morceau d'armature tenu par deux pièces qui bougent l'une par rapport à l'autre ; ce que voit l'air.
func _armature() -> void:
	if analyse.armature.is_empty():
		return
	var g := Armature.graphe(plan.donnees)
	for m in Armature.morceaux(g):
		var arts: Array = (m["articulations"] as Dictionary).keys()
		if arts.size() < 2:
			continue
		var noms := PackedStringArray()
		for a in arts:
			noms.append(Analyse._majuscule(Analyse._mots(String(a)))
				if String(a) != "" else "le fuselage")
		var elts: Array = (m["connecteurs"] as Array).filter(func(c): return String(g["connecteurs"][c].get("fixe_a", "")) != "") \
			.map(func(c): return {"genre": "ajout", "id": String(c)})
		_ajouter(AVERTIT, "Plan", "Une armature relie des pièces qui bougent l'une par rapport à l'autre",
			"Ses connecteurs sont posés sur %s : elle reste avec le fuselage, et dans un vrai vaisseau elle empêcherait la pièce mobile de bouger. Enlève une poutre, ou pose ce morceau sur une seule pièce." % " et ".join(noms),
			_pluriel((m["poutres"] as Array).size(), "poutre"), _groupe(elts))
	var portants: Array = analyse.armature.keys().filter(func(i): return String(analyse.armature[i].get("modele", "")) == Armature.PANNEAU \
		and String((analyse.armature[i].get("reglages", {}) as Dictionary).get("portant", "non")) == "oui")
	_ajouter(INFO, "En vol", "L'air ne voit que les surfaces d'aile de l'armature",
		"%s porte dans l'air comme une aile. Le reste de l'armature (tôles, vitres) compte pour la masse et le dessin, pas encore pour la traînée : elle viendra avec l'analyse de la coque construite." % _pluriel(portants.size(), "panneau"),
		"%d" % portants.size())


# =====================================================================
# LUMIÈRE
# =====================================================================
func _lumiere() -> void:
	var els := DessinVaisseau.elements(plan)
	var trop_clair := []
	var trop_sombre := []
	var vitres := 0
	var moteurs_poses := 0
	for el in els:
		var elt := {"genre": el["genre"], "id": el["id"]}
		var a_lueur := false
		for f in el["formes"]:
			var role := String(f["role"])
			if role == "lueur":
				a_lueur = true
			if role != "":
				continue
			if bool(f.get("vitre", false)):
				vitres += 1
				continue
			var c := (f["couleur"] as Color).srgb_to_linear()
			var y := 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b
			if y > ALBEDO_MAX and not trop_clair.has(elt):
				trop_clair.append(elt)
			elif y < ALBEDO_MIN and not trop_sombre.has(elt):
				trop_sombre.append(elt)
		if a_lueur and el["genre"] == "ajout":
			moteurs_poses += 1
	if not trop_clair.is_empty():
		_ajouter(AVERTIT, "Lumière", "%s plus %s que la neige" % [_pluriel(trop_clair.size(), "pièce"), "blanche" if trop_clair.size() == 1 else "blanches"],
			"La vraie lumière ne renvoie jamais plus de 90 % de ce qu'elle reçoit : ces pièces auraient l'air de lampes au Soleil.",
			"", _groupe(trop_clair))
	if not trop_sombre.is_empty():
		_ajouter(AVERTIT, "Lumière", "%s plus %s que le charbon" % [_pluriel(trop_sombre.size(), "pièce"), "noire" if trop_sombre.size() == 1 else "noires"],
			"Moins de 2 % de la lumière renvoyée : on ne les verrait jamais, même au Soleil.", "", _groupe(trop_sombre))
	var caches := _pieces_devant_la_verriere(els)
	if not caches.is_empty():
		var noms := caches.map(func(e): return analyse.nom_element(String(e["id"])) if e["genre"] == "ajout" else Analyse.nom_lisible(analyse.piece(String(e["id"]))))
		_ajouter(AVERTIT, "Lumière", "%s devant la verrière" % (String(noms[0]) if noms.size() == 1 else _pluriel(noms.size(), "pièce")),
			"Vu du siège du pilote, %s cache%s une partie du ciel et met de l'ombre dans le cockpit." % [
				", ".join(noms.slice(0, 4)) + ("…" if noms.size() > 4 else ""), "" if noms.size() == 1 else "nt"], "", _groupe(caches))
	if vitres > 0:
		_ajouter(INFO, "Lumière", _pluriel(vitres, "vitre"),
			"Une plaque en verre est une vraie vitre dans le jeu : on voit à travers, elle renvoie la lumière selon l'angle (loi de Fresnel, comme la verrière) et ne fait pas d'ombre.", "%d" % vitres)
	if moteurs_poses > 0:
		_ajouter(INFO, "Lumière", "Lueurs de %s" % _pluriel(moteurs_poses, "moteur posé", "moteurs posés"),
			"Leurs sorties brillent selon leur vraie poussée, mais n'éclairent pas la coque : le système de lumière a deux lampes (le projecteur du nez, touche J, et la lampe du cockpit).", "%d" % moteurs_poses)
	if trop_clair.is_empty() and trop_sombre.is_empty() and caches.is_empty():
		_ajouter(OK, "Lumière", "Lumière : couleurs possibles, vue du pilote dégagée",
			"Toutes les couleurs existent sous une vraie lumière, et rien ne cache la verrière.")


## Les éléments que l'œil du pilote voit par la verrière (rayons vers l'avant, au-dessus du nez).
func _pieces_devant_la_verriere(els: Array) -> Array:
	var oeil: Vector3 = options.get("oeil", OEIL_PILOTE)
	var boites := []
	for el in els:
		var bb := AABB()
		var premier := true
		for f in el["formes"]:
			if String(f["role"]) == "panache":
				continue
			var fb := _boite_forme(String(f["forme"]), f["taille"])
			var fx: Transform3D = f["xf"]
			for k in 8:
				var q := fx * fb.get_endpoint(k)
				if premier:
					bb = AABB(q, Vector3.ZERO)
					premier = false
				else:
					bb = bb.expand(q)
		if not premier:
			boites.append([el, (el["xf"] as Transform3D).affine_inverse(), bb])
	var vus := []
	var lacet := -VUE_LACET
	while lacet <= VUE_LACET + 0.01:
		var tangage := VUE_BAS
		while tangage <= VUE_HAUT + 0.01:
			var d := Basis.from_euler(Vector3(deg_to_rad(tangage), deg_to_rad(-lacet), 0.0)) * Vector3.FORWARD
			for b in boites:
				var el: Dictionary = b[0]
				var inv: Transform3D = b[1]
				var o := inv * oeil
				var dl := inv.basis * d
				if _rayon_boite(o, dl, b[2], VUE_PORTEE):
					var elt := {"genre": el["genre"], "id": el["id"]}
					if not vus.has(elt):
						vus.append(elt)
			tangage += 6.0
		lacet += 6.25
	return vus


static func _boite_forme(forme: String, t: Vector3) -> AABB:
	match forme:
		"cylindre":
			var r := maxf(t.x, t.y)
			return AABB(Vector3(-r, -t.z * 0.5, -r), Vector3(2.0 * r, t.z, 2.0 * r))
		"gelule":
			return AABB(Vector3(-t.x, -t.y * 0.5, -t.x), Vector3(2.0 * t.x, t.y, 2.0 * t.x))
	return AABB(-t * 0.5, t)


## Le rayon (origine o, direction d) touche-t-il la boîte avant la distance l ? (méthode des « tranches »)
static func _rayon_boite(o: Vector3, d: Vector3, b: AABB, l: float) -> bool:
	var t0 := 0.0
	var t1 := l * d.length()
	var dn := d.normalized()
	for k in 3:
		if absf(dn[k]) < 1e-9:
			if o[k] < b.position[k] or o[k] > b.end[k]:
				return false
			continue
		var ta := (b.position[k] - o[k]) / dn[k]
		var tb := (b.end[k] - o[k]) / dn[k]
		t0 = maxf(t0, minf(ta, tb))
		t1 = minf(t1, maxf(ta, tb))
		if t0 > t1:
			return false
	return true


# =====================================================================
# AU SOL (départ devant le hangar)
# =====================================================================
func _au_sol() -> void:
	var roues: Array = plan.pieces_de_type("roue")
	var poids: float = v.masse * Analyse.G_SOL
	var cg: Vector3 = v.centre_gravite
	sol = {"roues": roues.size(), "stable": false, "marge": 0.0, "parts": []}
	if roues.is_empty():
		_ajouter(AVERTIT, "Au sol", "Pas de train d'atterrissage",
			"Au départ devant le hangar, il est posé sur le ventre (la coque frotte le sol). %s" % (
				"Il peut décoller à la verticale." if v.poussee_verticale_max > poids else "Il ne peut pas décoller à la verticale : il glissera sur le ventre."),
			"0 roue")
		return
	if roues.size() < 3:
		_ajouter(AVERTIT, "Au sol", "Seulement %s" % _pluriel(roues.size(), "roue"),
			"Il faut au moins trois roues pour tenir debout : il va pencher et poser la coque.", "%d" % roues.size())
		return
	var pts := roues.map(func(p): return (p["point"] as Vector3) - cg)
	var n := VaisseauPhysique._normale_points(pts, Vector3.UP)
	if n.length() < 0.5:
		n = Vector3.UP
	var u := (Vector3.RIGHT - n * n.dot(Vector3.RIGHT)).normalized()
	var w := n.cross(u).normalized()
	var p2 := pts.map(func(q): return Vector2((q as Vector3).dot(u), (q as Vector3).dot(w)))
	var coque := _enveloppe(p2)
	# distance (signée) du centre de gravité (0, 0) au bord : positive dedans
	var marge := INF
	var sortie := Vector2.ZERO
	for i in coque.size():
		var a: Vector2 = coque[i]
		var b: Vector2 = coque[(i + 1) % coque.size()]
		var ab := b - a
		var dehors := Vector2(ab.y, -ab.x).normalized()   # enveloppe dans le sens inverse des aiguilles d'une montre
		var dd := -(Vector2.ZERO - a).dot(dehors)
		if dd < marge:
			marge = dd
			sortie = dehors
	sol["marge"] = marge
	sol["stable"] = marge >= MARGE_SOL
	var roues_ids := roues.map(func(p): return {"genre": "piece", "id": p["id"]})
	if marge < MARGE_SOL:
		var d3 := (u * sortie.x + w * sortie.y)
		var cote := ("vers l'arrière" if d3.z > 0.0 else "vers l'avant") if absf(d3.z) >= absf(d3.x) else ("vers la droite" if d3.x > 0.0 else "vers la gauche")
		_ajouter(AVERTIT, "Au sol", "Il bascule %s" % cote,
			("Son centre de gravité est %s en dehors des roues : au départ devant le hangar, il va tomber %s sur la coque. Déplace des pièces lourdes, ou le train." % [Analyse.longueur_txt(-marge), cote]) if marge < 0.0
				else ("Son centre de gravité est à seulement %s du bord des roues : il tient à peine, et basculera %s au premier freinage." % [Analyse.longueur_txt(marge), cote]),
			Analyse.longueur_txt(marge), _groupe(roues_ids))
		return
	# part du poids sur chaque roue (trois roues : coordonnées barycentriques, exactes ; plus : on ne dit
	# que la marge) ; un amortisseur qui porte plus que raideur × course arrive en butée
	var lignes := []
	if roues.size() == 3:
		var a2: Vector2 = p2[0]
		var b2: Vector2 = p2[1]
		var c2: Vector2 = p2[2]
		var det := (b2 - a2).cross(c2 - a2)
		var parts := [(b2 - Vector2.ZERO).cross(c2 - Vector2.ZERO) / det, (c2 - Vector2.ZERO).cross(a2 - Vector2.ZERO) / det,
			(a2 - Vector2.ZERO).cross(b2 - Vector2.ZERO) / det]
		var gn := n.dot(Vector3.UP)
		for k in 3:
			var p: Dictionary = roues[k]
			var f := float(parts[k]) * poids * gn
			var tient := float(p["raideur_n_m"]) * float(p["course_m"])
			(sol["parts"] as Array).append(float(parts[k]))
			lignes.append("%s %s %%" % [Analyse.nom_lisible(p), Analyse.nombre(100.0 * float(parts[k]))])
			if f > tient:
				_ajouter(AVERTIT, "Au sol", "%s : amortisseur en butée" % Analyse.nom_lisible(p),
					"Il porte %s kN, son ressort en tient %s kN avant d'arriver au bout de sa course (%s) : le train touche presque la coque, et le moindre choc le casse." % [
						Analyse.nombre(f / 1000.0, 1), Analyse.nombre(tient / 1000.0, 1), Analyse.longueur_txt(float(p["course_m"]))],
					"%s kN" % Analyse.nombre(f / 1000.0, 1), {"genre": "piece", "id": p["id"]})
	_ajouter(OK, "Au sol", "Au sol : il tient sur ses roues",
		"Centre de gravité à %s du bord des roues.%s" % [Analyse.longueur_txt(marge), (" Part du poids : " + ", ".join(lignes) + ".") if not lignes.is_empty() else ""],
		Analyse.longueur_txt(marge), _groupe(roues_ids))


## Enveloppe convexe (sens inverse des aiguilles d'une montre) : méthode de la « chaîne monotone ».
static func _enveloppe(points: Array) -> Array:
	var p := points.duplicate()
	p.sort_custom(func(a, b): return a.x < b.x or (a.x == b.x and a.y < b.y))
	if p.size() < 3:
		return p
	var bas := []
	for q in p:
		while bas.size() >= 2 and ((bas[-1] as Vector2) - (bas[-2] as Vector2)).cross((q as Vector2) - (bas[-2] as Vector2)) <= 0.0:
			bas.pop_back()
		bas.append(q)
	var haut := []
	for i in range(p.size() - 1, -1, -1):
		var q: Vector2 = p[i]
		while haut.size() >= 2 and ((haut[-1] as Vector2) - (haut[-2] as Vector2)).cross(q - (haut[-2] as Vector2)) <= 0.0:
			haut.pop_back()
		haut.append(q)
	bas.pop_back()
	haut.pop_back()
	return bas + haut


# =====================================================================
# EN VOL
# =====================================================================
func _en_vol() -> void:
	var t: Dictionary = analyse.tableau()
	var poids := float(t["poids"])
	var ok := true
	if int(t["moteurs_principaux"]) == 0:
		ok = false
		_ajouter(AVERTIT, "En vol", "Aucun moteur principal",
			"Seuls les petits propulseurs et les moteurs de levage poussent : il avancera très lentement.", "0")
	var ailes: int = plan.pieces_de_type("surface_air").size()
	if not bool(t["peut_decoller"]):
		var r := Analyse.nombre(float(t["rapport_vertical"]), 2)
		if ailes == 0 or float(t["poussee_poids"]) < 0.3:
			ok = false
			_ajouter(AVERTIT, "En vol", "Il ne peut pas quitter le sol",
				"À la verticale, ses moteurs ne portent que %s fois son poids, et %s." % [r,
					"il n'a pas d'aile pour décoller en roulant" if ailes == 0 else "il pousse trop peu vers l'avant pour décoller en roulant"],
				"× %s" % r)
		else:
			_ajouter(INFO, "En vol", "Pas de décollage vertical",
				"À la verticale, ses moteurs ne portent que %s fois son poids : il faudra décoller en roulant, avec les ailes." % r, "× %s" % r)
	var cm: Vector3 = t["couple_max"]
	var axes := []
	for k in 3:
		if cm[k] < 1.0:
			axes.append(["le tangage", "le lacet", "le roulis"][k])
	if not axes.is_empty():
		ok = false
		_ajouter(AVERTIT, "En vol", "Il ne peut pas tourner sur un axe",
			"Aucun petit propulseur pour %s : %s." % [" ni ".join(axes),
				"le roulis n'est possible qu'avec eux" if axes.has("le roulis") else "il ne pourra pas viser"], ", ".join(axes))
	var a_fond := float(t["poussee_moteurs"])
	var avant := float(t["poussee_avant"])
	if a_fond > 0.0 and avant < 0.99 * a_fond:
		var niveau := AVERTIT if avant < 0.5 * a_fond else INFO
		if niveau == AVERTIT:
			ok = false
		_ajouter(niveau, "En vol", "Poussée réduite à %s %%" % Analyse.nombre(100.0 * avant / a_fond),
			"La poussée des moteurs ne passe pas par le centre de gravité : pour ne pas faire tourner le vaisseau, le pilotage les réduit à %s kN (%s kN à fond)." % [
				Analyse.nombre(avant / 1000.0), Analyse.nombre(a_fond / 1000.0)], "%s kN" % Analyse.nombre(avant / 1000.0))
	if ok:
		_ajouter(OK, "En vol", "En vol : il pousse, décolle et tourne",
			"Poussée / poids : %s ; à la verticale : %s fois son poids ; il tourne sur les trois axes." % [
				Analyse.nombre(float(t["poussee_poids"]), 1), Analyse.nombre(float(t["rapport_vertical"]), 2)],
			"%s" % Analyse.nombre(float(t["poussee_poids"]), 1))


# =====================================================================
# SYMÉTRIE (pour information)
# =====================================================================
func _symetrie() -> void:
	var s: Dictionary = analyse.symetrie()
	var x := float(s["cg_x"])
	if absf(x) >= 0.05:
		_ajouter(INFO, "Symétrie", "Centre de gravité %s %s" % [Analyse.longueur_txt(absf(x)), "à droite" if x > 0.0 else "à gauche"],
			"Il est plus lourd d'un côté : les propulseurs devront compenser (voir la page Symétrie).", Analyse.longueur_txt(absf(x)))
	var elts: Array = (s["elements"] as Array).map(func(e): return {"genre": e["genre"], "id": e["id"]})
	if not elts.is_empty():
		_ajouter(INFO, "Symétrie", "%s sans jumelle" % _pluriel(elts.size(), "pièce"),
			"Pas forcément une erreur (le chasseur a le levier des gaz à gauche, le manche à droite, et ses deux buses de montée ne sont pas tout à fait en miroir).",
			"%d" % elts.size(), _groupe(elts))


# =====================================================================
# AFFICHAGE (tuile, page de l'atelier, fenêtre)
# =====================================================================
## La tuile du tableau ingénieur : [titre, valeur, détail, couleur de la valeur].
func tuile() -> Array:
	var nb := nombre_de(BLOQUE)
	var na := nombre_de(AVERTIT)
	var detail := "≈ %d images/s sur ton PC · dessin %s %% du chasseur" % [roundi(float(charge.get("ips", 0.0))), Analyse.nombre(100.0 * float(charge.get("part", 0.0)))] if not charge.is_empty() else "plan illisible"
	if nb > 0:
		return ["AVANT LE VOL", "BLOQUÉ", "%s · %s" % [_pluriel(nb, "blocage"), detail], couleur(BLOQUE)]
	if na > 0:
		return ["AVANT LE VOL", _pluriel(na, "avertissement"), detail, couleur(AVERTIT)]
	return ["AVANT LE VOL", "prêt", detail, couleur(OK)]


static func couleur(niveau: String) -> Color:
	match niveau:
		BLOQUE:
			return Color(1.0, 0.42, 0.38)
		AVERTIT:
			return Color(1.0, 0.72, 0.28)
		OK:
			return Color(0.42, 0.86, 0.55)
	return Color(0.58, 0.63, 0.71)


static func symbole(niveau: String) -> String:
	match niveau:
		BLOQUE:
			return "✕"
		AVERTIT:
			return "⚠"
		OK:
			return "✓"
	return "•"


## La page détaillée (fiche de l'atelier) : une section par catégorie.
func fiche() -> Dictionary:
	var nb := nombre_de(BLOQUE)
	var na := nombre_de(AVERTIT)
	var etat := "prêt à voler" if nb == 0 and na == 0 else (("BLOQUÉ : %s" % _pluriel(nb, "blocage")) if nb > 0 else _pluriel(na, "avertissement"))
	var lignes := [["Résultat", etat]]
	if not charge.is_empty():
		var c: Dictionary = charge["compte"]
		lignes.append(["Vitesse du PC", "≈ %d images/s (estimation ; le chasseur : %d)" % [roundi(float(charge["ips"])), roundi(IPS_REFERENCE)]])
		lignes.append(["Dessin", "%s %% du chasseur : %s surfaces, %s triangles%s" % [Analyse.nombre(100.0 * float(charge["part"])),
			Analyse.nombre(charge["surfaces"]), Analyse.nombre(charge["triangles"]),
			(", %s" % _pluriel(int(c["vitres"]), "vitre")) if int(c["vitres"]) > 0 else ""]])
		lignes.append(["Pièces posées", "%d (limite prévue : %d)" % [int(charge["pieces_posees"]), PIECES_POSEES_MAX]])
		var tl: Vector3 = charge["taille"]
		lignes.append(["Taille", "%s × %s × %s m (longueur prévue : %d m au plus)" % [Analyse.nombre(tl.z, 1), Analyse.nombre(tl.x, 1),
			Analyse.nombre(tl.y, 1), roundi(LONGUEUR_MAX)]])
	var sections := []
	for cat in CATEGORIES:
		var liste := []
		for e in elements:
			if e["categorie"] != cat:
				continue
			var l := Analyse.ligne_liste("%s  %s" % [symbole(e["niveau"]), e["titre"]], String(e["valeur"]), -1.0, e["choix"])
			l["detail"] = e["texte"]
			l["couleur"] = couleur(e["niveau"])
			liste.append(l)
		if not liste.is_empty():
			sections.append({"titre": String(cat).to_upper(), "liste": liste})
	return {"titre": "Contrôle avant le vol", "sous_titre": "ce que le jeu vérifie avant « Lancer »",
		"lignes": lignes, "sections": sections,
		"note": "✕ bloque le départ (ce qui casserait le jeu) · ⚠ avertit (une fenêtre s'ouvre, tu peux partir quand même) · • pour information · ✓ va bien.\nLes images par seconde sont estimées à partir du chasseur de départ sur ton PC (environ 60) : à vérifier en vol avec le compteur en haut à droite. Clique sur une ligne pour voir les pièces concernées."}


## La fenêtre « Contrôle avant le vol » (atelier : Lancer ; accueil : Jouer), sur un fond assombri qui
## couvre l'écran : ce qui bloque ou avertit, expliqué. boutons : [[texte, Callable, principal (bool)]].
func fenetre(boutons: Array, note := "") -> Control:
	var fond := ColorRect.new()
	fond.name = "FenetreControle"
	fond.color = Color(0, 0, 0, 0.45)
	fond.set_anchors_preset(Control.PRESET_FULL_RECT)
	fond.mouse_filter = Control.MOUSE_FILTER_STOP
	var centre := CenterContainer.new()
	centre.set_anchors_preset(Control.PRESET_FULL_RECT)
	centre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fond.add_child(centre)
	var b := bloque()
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", Style.boite(Color(Style.FOND_CLAIR, 0.98), couleur(BLOQUE if b else AVERTIT), 8, 18.0))
	centre.add_child(p)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	v.custom_minimum_size = Vector2(560, 0)
	p.add_child(v)
	v.add_child(Style.label("CONTRÔLE AVANT LE VOL", 12, Style.TEXTE_DOUX))
	var na := nombre_de(AVERTIT)
	v.add_child(_texte("Le vol ne peut pas partir" if b else ("Avant de partir, " + ("un point à savoir" if na == 1 else "%d points à savoir" % na)),
		Color.WHITE, 22))
	if b:
		v.add_child(_texte("Ce qui est en rouge casserait le jeu : corrige-le dans l'atelier, puis relance.%s" % (
			"" if na == 0 else " Le reste est un avertissement."), Style.TEXTE_DOUX, 13))
	var defil := ScrollContainer.new()
	defil.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	defil.custom_minimum_size = Vector2(0, mini(80 * a_montrer().size(), 420))
	v.add_child(defil)
	var liste := VBoxContainer.new()
	liste.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	liste.add_theme_constant_override("separation", 12)
	defil.add_child(liste)
	for e in a_montrer():
		var bloc := VBoxContainer.new()
		bloc.add_theme_constant_override("separation", 2)
		bloc.add_child(_texte("%s  %s" % [symbole(e["niveau"]), e["titre"]], couleur(e["niveau"]), 16))
		bloc.add_child(_texte(String(e["texte"]), Style.TEXTE, 13))
		liste.add_child(bloc)
	if not charge.is_empty():
		v.add_child(_texte("Estimation : ≈ %d images par seconde sur ton PC.%s" % [roundi(float(charge["ips"])),
			(" " + note) if note != "" else ""], Style.TEXTE_DOUX, 12))
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	h.alignment = BoxContainer.ALIGNMENT_END
	v.add_child(h)
	for bt in boutons:
		var bouton: Button = Style.bouton_principal(String(bt[0]), 16) if bool(bt[2]) else Style.bouton(String(bt[0]), 14)
		bouton.name = "Bouton_" + String(bt[0]).replace(" ", "_")
		bouton.pressed.connect(bt[1])
		h.add_child(bouton)
	return fond


static func _texte(texte: String, c: Color, taille: int) -> Label:
	var l := Style.label(texte, taille, c)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(520, 0)
	return l
