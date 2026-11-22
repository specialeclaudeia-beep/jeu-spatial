extends RefCounted
## Ce que l'air fait au vaisseau : TRAÎNÉE et PORTANCE, par de vraies forces (programme de départ :
## atmosphère).
##
## Le vaisseau est découpé en morceaux qui touchent l'air (décrits dans son plan ; chasseur : mesurés sur
## le modèle 3D v26) :
## - les 4 ailes, chacune en 3 bandes (de l'emplanture au bout) : des plaques minces. Chaque bande voit
##   SON vent (vitesse du vaisseau + rotation × position : une aile qui monte pendant un roulis voit l'air
##   arriver par-dessus, ce qui freine le roulis, sans rien ajouter à la main) ;
## - les 2 dérives sur le dos, à l'arrière ;
## - le fuselage : traînée de face, écoulement de travers (loi d'Allen), portance du nez effilé ;
## - le train, quand il est sorti.
## Chaque force est posée à son vrai point d'application (quart avant de la corde pour une aile) : les
## couples (stabilité, amortissement) en sortent tout seuls.
##
## Une plaque reçoit une force perpendiculaire à elle (la « force normale ») et un frottement le long du
## vent. La force normale dépend de l'angle d'attaque α et de la vitesse (nombre de Mach) :
## - en dessous du son : pente de portance des ailes d'allongement fini (Helmbold), corrigée de la
##   compressibilité (Prandtl-Glauert), et portance tourbillonnaire des grands angles (qui finit, à 90°,
##   à la traînée d'une plaque face au vent : 1,2) ;
## - au-dessus du son : théorie des plaques minces supersoniques (Ackeret, 4α/√(M²−1)) ;
## - très vite (rentrée) : impact des molécules (Newton : 2 sin²α), qui donne la grosse traînée qui
##   freine le vaisseau quand il rentre « à plat » ;
## - très haut (molécules rares, libre parcours plus grand que le vaisseau) : chaque molécule frappe la
##   coque seule (écoulement moléculaire libre : traînée ≈ 2,2 fois la surface face au vent).

## Atelier, étape 1 : la description des morceaux qui touchent l'air vient du PLAN du vaisseau
## (scripts/atelier/plan.gd) : plaques « surface_air » (bandes d'aile, dérives) et réglages « air » du
## fuselage, du nez et du train. Ce fichier ne garde que les lois de l'air.
const Plan = preload("res://scripts/atelier/plan.gd")
var centre_gravite := Vector3.ZERO
var longueur := 10.0            # m, longueur du vaisseau (pour le régime moléculaire)
## Plaques : {point, normale (pose de référence), surface (m²), allongement, corde (m, 0 = inconnue),
## biplan (gêne des ailes proches), groupe (prise du son), art (index dans _arts, −1 = fixe), d_axe (m)}.
var plaques: Array = []
## Charnières qui portent des plaques (ailes) : {point, axe, angle_0, angle_1, angle_ref (degrés), phase, commande}.
var _arts: Array = []
## Fuselage (projections du modèle 3D) : surface de face, de côté, de dessus (m²), centre de ces surfaces.
var face := 0.0
var cote := 0.0
var dessus := 0.0
var centre_fuselage := Vector3.ZERO
## Portance du nez effilé (théorie des corps élancés) : 2 × la plus grande section × l'angle, posée là où
## la section grandit (moyenne des positions, pesée par la croissance de la section : mesuré sur le modèle).
var nez := Vector3.ZERO
var section_max := 0.0
const FROTTEMENT_PLAQUE := 0.004                    # par face (couche limite turbulente)
var point_train := Vector3.ZERO
var train_surface := 0.0                            # m², roues et jambes face au vent (Cx ≈ 1)
var _n_groupes := 0


func _init(plan_vaisseau = null) -> void:
	var p = plan_vaisseau if plan_vaisseau != null else Plan.par_defaut()
	configurer(p, p.proprietes_masse()["centre"])


## Lit dans le plan les morceaux qui touchent l'air. cg = centre de gravité (repère du modèle).
func configurer(plan, cg: Vector3) -> void:
	centre_gravite = cg
	var air: Dictionary = plan.donnees.get("air", {})
	longueur = float((plan.donnees.get("coque", {}) as Dictionary).get("longueur_m", 10.0))
	var fu: Dictionary = air.get("fuselage", {})
	face = float(fu.get("surface_face_m2", 0.0))
	cote = float(fu.get("surface_cote_m2", 0.0))
	dessus = float(fu.get("surface_dessus_m2", 0.0))
	centre_fuselage = Plan.Catalogue.vecteur(fu.get("centre", [0.0, 0.0, 0.0]))
	var ne: Dictionary = air.get("nez", {})
	nez = Plan.Catalogue.vecteur(ne.get("point", [0.0, 0.0, 0.0]))
	section_max = float(ne.get("section_max_m2", 0.0))
	var tr: Dictionary = air.get("train", {})
	point_train = Plan.Catalogue.vecteur(tr.get("point", [0.0, 0.0, 0.0]))
	train_surface = float(tr.get("surface_m2", 0.0))
	plaques = []
	_arts = []
	var index_art := {}
	var groupes := {}
	for p in plan.pieces_de_type("surface_air"):
		var k := -1
		var d_axe := 0.0
		var id := String(p.get("articulation", ""))
		var a: Dictionary = plan.articulations.get(id, {})
		if not a.is_empty() and a["type"] == "charniere":
			if not index_art.has(id):
				index_art[id] = _arts.size()
				var c := String(a["commande"])
				var a0 := float(a["angle_0_deg"])
				var a1 := float(a["angle_1_deg"])
				_arts.append({"point": a["point"], "axe": a["axe"], "angle_0": a0, "angle_1": a1, "art": a,
					"commande": c, "angle_ref": lerpf(a0, a1, Plan.progression(a, plan.valeur_reference(c)))})
			k = index_art[id]
			# distance de la plaque à l'axe de la charnière (pour la gêne entre ailes proches)
			var r: Vector3 = (p["point"] as Vector3) - (a["point"] as Vector3)
			d_axe = (r - (a["axe"] as Vector3) * r.dot(a["axe"])).length()
		var g := String(p.get("groupe", p["id"]))
		if not groupes.has(g):
			groupes[g] = groupes.size()
		plaques.append({"point": p["point"], "normale": p["normale"], "surface": float(p["surface_m2"]),
			"allongement": float(p["allongement"]), "corde": float(p.get("corde_m", 0.0)),
			"biplan": bool(p.get("biplan", false)), "groupe": groupes[g], "art": k, "d_axe": d_axe})
	_n_groupes = groupes.size()
	prise_surfaces = _n_groupes + 3
	prise_plaques = plaques.size()
	prise_f.resize(prise_surfaces)
	prise_c.resize(prise_surfaces)
	prise_f.fill(Vector3.ZERO)
	prise_c.fill(Vector3.ZERO)
	prise_alpha.resize(0)


## Son, phase 4 : « prise » des forces de chaque surface, en LECTURE SEULE (rien de ce qui est noté ici ne
## sert à la physique). Force (N) et couple autour du centre de gravité (N·m), repère du vaisseau, du dernier
## calcul. D'abord les groupes de plaques du plan, dans l'ordre (chasseur : 0-3 ailes haut gauche, haut
## droit, bas gauche, bas droit ; 4-5 dérives gauche, droite), puis fuselage, nez, train (chasseur : 6, 7, 8).
## Le son en tire la tension de chaque pièce (scripts/son/charges.gd).
var prise_surfaces := 0
var prise_f := PackedVector3Array()
var prise_c := PackedVector3Array()
var _surface := 0   # surface en cours (prise du son)
## Son, phase 5 : « prise » de chaque plaque (chasseur : 12 bandes d'aile, dans l'ordre des ailes, puis les
## 2 dérives), en LECTURE SEULE : angle d'attaque vu par la plaque (rad, 0 à π/2), vitesse de l'air qu'elle
## voit (m/s), surface (m²), corde (m), et son point (repère du vaisseau). Le son en tire le décrochage et le
## tremblement transsonique (scripts/son/air_son.gd). Rien de ce qui est noté ici ne sert à la physique.
var prise_plaques := 0
var prise_alpha := PackedFloat64Array()
var prise_v := PackedFloat64Array()
var prise_surface := PackedFloat64Array()
var prise_corde := PackedFloat64Array()
var prise_point := PackedVector3Array()
var part_libre := 0.0            # part « molécules isolées » de l'air (0 = fluide, 1 = molécules seules), dernier calcul
var _plaque_n := 0

## Dernières valeurs (affichage, tests).
var mach := 0.0
var pression_dyn := 0.0          # Pa : ½ ρ v²
var portance := 0.0              # N : composante perpendiculaire au vent, vers le haut du vaisseau
var trainee := 0.0               # N : composante le long du vent
var incidence := 0.0             # rad : angle d'attaque du vaisseau (nez au-dessus du vent > 0)


## Pente de portance (par radian) d'une aile d'allongement ar, au nombre de Mach m.
static func pente(ar: float, m: float) -> float:
	if m < 0.9:
		var b := sqrt(1.0 - m * m)
		return TAU * ar / (2.0 + sqrt(ar * ar * b * b + 4.0))
	var a_sub := TAU * ar / (2.0 + sqrt(ar * ar * 0.19 + 4.0))   # valeur à Mach 0,9
	if m <= 1.2:
		return a_sub   # zone transsonique : pas de pic infini
	var b2 := sqrt(m * m - 1.0)
	var a_sup := 4.0 / b2 * maxf(1.0 - 1.0 / (2.0 * ar * b2), 0.3)
	return minf(a_sup, a_sub)


## Coefficient de force normale d'une plaque (α = angle d'attaque, de −π à π).
static func coef_normal(alpha: float, ar: float, m: float) -> float:
	var s := sin(alpha)
	var c := cos(alpha)
	var a := pente(ar, m)
	# portance « attachée » qui s'efface aux grands angles + portance de plaque décrochée
	var cn := a * s * c * c * signf(c) + 1.2 * s * absf(s)
	if m > 1.0:
		# Newton (impact des molécules) : seulement la face au vent, jamais moins
		var newton := 2.0 * s * absf(s)
		var f := clampf((m - 1.0) / 4.0, 0.0, 1.0)
		cn = lerpf(cn, signf(cn) * maxf(absf(cn), absf(newton)), f)
	return cn


## Traînée du fuselage vu de face, selon le nombre de Mach (nez pointu + culot).
static func cx_face(m: float) -> float:
	if m < 0.8:
		return 0.25
	if m < 1.1:
		return lerpf(0.25, 0.65, (m - 0.8) / 0.3)
	return lerpf(0.65, 0.45, clampf((m - 1.1) / 3.0, 0.0, 1.0))


## Forces de l'air. vent_corps = vitesse de l'AIR par rapport au vaisseau, dans le repère du vaisseau
## (donc −vitesse du vaisseau par rapport à l'air) ; omega = rotation du vaisseau (repère du vaisseau) ;
## rho, son = densité et vitesse du son ; ailes = ouverture (0..1) ; train = sorti (0..1).
## Renvoie [force (N, repère du vaisseau), couple (N·m, repère du vaisseau, autour du centre de gravité)].
func forces(vent_corps: Vector3, omega: Vector3, rho: float, son: float, ailes: float, train: float) -> Array:
	_f_cumul = Vector3.ZERO
	_c_cumul = Vector3.ZERO
	prise_f.fill(Vector3.ZERO)   # prise du son (lecture seule)
	prise_c.fill(Vector3.ZERO)
	if prise_alpha.size() != prise_plaques:
		for a in [prise_alpha, prise_v, prise_surface, prise_corde]:
			a.resize(prise_plaques)
		prise_point.resize(prise_plaques)
	prise_v.fill(0.0)
	prise_alpha.fill(0.0)
	_plaque_n = 0
	part_libre = 0.0
	var v := vent_corps.length()
	pression_dyn = 0.5 * rho * v * v
	mach = v / maxf(son, 1.0)
	portance = 0.0
	trainee = 0.0
	incidence = 0.0
	if rho <= 0.0 or v < 1e-3:
		return [Vector3.ZERO, Vector3.ZERO]
	incidence = atan2(vent_corps.y, vent_corps.z)   # air qui vient d'en dessous → nez au-dessus du vent
	# Régime moléculaire (molécules rares) : de 0 (fluide) à 1 (molécules seules), selon Knudsen
	var kn := 6.63e-8 * 1.225 / rho / longueur
	var libre := clampf((log(kn) / log(10.0) + 1.0) / 2.0, 0.0, 1.0)   # 0 sous Kn = 0,1 ; 1 au-dessus de Kn = 10
	part_libre = libre   # prise du son (lecture seule)

	# 1. Les plaques : bandes d'aile et dérives. Une plaque posée sur une charnière (aile) tourne avec elle.
	#    Ailes repliées l'une sur l'autre, ou très proches : elles se gênent (biplan) ; l'écart entre l'aile
	#    du haut et celle du bas, rapporté à la corde, dit de combien.
	var rots := []
	var ouvertures := PackedFloat64Array()
	for ar in _arts:
		var c := ailes if ar["commande"] == "ailes" else (train if ar["commande"] == "train" else 0.0)
		var angle := lerpf(float(ar["angle_0"]), float(ar["angle_1"]), Plan.progression(ar["art"], c))
		rots.append(Basis(ar["axe"], deg_to_rad(angle - float(ar["angle_ref"]))))
		ouvertures.append(deg_to_rad(absf(angle - float(ar["angle_0"]))))
	for pl in plaques:
		var p: Vector3 = pl["point"]
		var normale: Vector3 = pl["normale"]
		var gene := 1.0
		var k: int = pl["art"]
		if k >= 0:
			var rot: Basis = rots[k]
			var pivot: Vector3 = _arts[k]["point"]
			p = pivot + rot * (p - pivot)
			normale = rot * normale
		var corde: float = pl["corde"]
		if pl["biplan"] and k >= 0 and corde > 0.0:
			var ecart := 2.0 * float(pl["d_axe"]) * sin(ouvertures[k])
			gene = 0.5 + 0.35 * clampf(ecart / corde, 0.0, 1.0)
		_surface = pl["groupe"]
		_plaque(p, normale, pl["surface"], pl["allongement"], gene, vent_corps, omega, rho, son, libre, corde)
	# 2. Le fuselage. Vent vu par son centre (la rotation compte aussi).
	_surface = _n_groupes
	var r_c := centre_fuselage - centre_gravite
	var w := vent_corps - omega.cross(r_c)
	var q := 0.5 * rho
	var m := w.length() / maxf(son, 1.0)
	# de face (le long de l'axe) : nez pointu, culot, onde de choc au-delà du son
	var cx := lerpf(cx_face(m), 2.2, libre)
	var f_ax := Vector3(0.0, 0.0, q * cx * face * absf(w.z) * w.z)
	# de travers (loi d'Allen) : chaque tranche du fuselage freine l'air qui la traverse comme un cylindre
	var cdc := lerpf(1.2, 2.2, libre)
	var f_tr := Vector3(q * cdc * cote * absf(w.x) * w.x, q * cdc * dessus * absf(w.y) * w.y, 0.0)
	_ajouter(r_c, f_ax + f_tr)
	# portance du nez effilé (corps élancé : 2 × surface de face × angle), seulement en fluide
	var r_n := nez - centre_gravite
	var wn := vent_corps - omega.cross(r_n)
	_surface = _n_groupes + 1
	if wn.z > 0.0 and libre < 1.0:
		var vn := wn.length()
		var f_nez := Vector3(wn.x, wn.y, 0.0) * (q * 2.0 * section_max * vn * absf(wn.z) / maxf(vn, 1e-6) * (1.0 - libre))
		# l'air qui arrive par en dessous pousse le nez vers le haut (même sens que la vitesse de travers)
		_ajouter(r_n, f_nez)
	# 3. Le train sorti
	_surface = _n_groupes + 2
	if train > 0.0:
		var r_t := point_train - centre_gravite
		var wt := vent_corps - omega.cross(r_t)
		_ajouter(r_t, wt * (q * train_surface * train * wt.length()))

	# Portance et traînée totales (pour l'affichage)
	var f_tot := _f_cumul
	var u := vent_corps / v                          # sens de l'air
	trainee = f_tot.dot(u)
	var lat := u.cross(Vector3.RIGHT).normalized()   # perpendiculaire au vent, vers le haut du vaisseau
	if lat.y < 0.0:
		lat = -lat
	portance = f_tot.dot(lat)
	return [f_tot, _c_cumul]


## Une plaque : force normale + frottement, au point p (repère du vaisseau).
func _plaque(p: Vector3, n: Vector3, surface: float, ar: float, gene: float, vent_corps: Vector3,
		omega: Vector3, rho: float, son: float, libre: float, corde_prise := 0.0) -> void:
	var r := p - centre_gravite
	var w := vent_corps - omega.cross(r)   # air vu par la plaque
	var v := w.length()
	var k_prise := _plaque_n   # prise du son (lecture seule)
	_plaque_n += 1
	if k_prise < prise_plaques:
		prise_point[k_prise] = p
		prise_surface[k_prise] = surface
		prise_corde[k_prise] = corde_prise if corde_prise > 0.0 else sqrt(surface / ar)
	if v < 1e-6:
		return
	var q := 0.5 * rho * v * v
	var m := v / maxf(son, 1.0)
	var wn := w.dot(n)
	var alpha := asin(clampf(wn / v, -1.0, 1.0))   # > 0 : l'air frappe la face de dessous et pousse vers +n
	if k_prise < prise_plaques:
		prise_alpha[k_prise] = absf(alpha)
		prise_v[k_prise] = v
	var cn := coef_normal(alpha, ar, m) * gene
	# écoulement moléculaire : la plaque reçoit la quantité de mouvement des molécules qui la frappent
	var cn_libre := 2.0 * sin(alpha) * absf(sin(alpha))
	cn = lerpf(cn, cn_libre, libre)
	var f := n * (q * surface * cn)
	# frottement sur les deux faces, le long de l'air
	# (au-delà du son, l'épaisseur de l'aile, 5 % de la corde, ajoute une traînée d'onde : 4·(e/c)²/√(M²−1))
	var cf := 2.0 * FROTTEMENT_PLAQUE
	if m > 1.2:
		cf += 4.0 * 0.05 * 0.05 / sqrt(m * m - 1.0)
	cf = lerpf(cf, 0.3, libre)
	f += w / v * (q * surface * cf)
	_ajouter(r, f)


func _ajouter(r: Vector3, f: Vector3) -> void:
	_f_cumul += f
	_c_cumul += r.cross(f)
	prise_f[_surface] += f              # prise du son (lecture seule)
	prise_c[_surface] += r.cross(f)


var _f_cumul := Vector3.ZERO
var _c_cumul := Vector3.ZERO
