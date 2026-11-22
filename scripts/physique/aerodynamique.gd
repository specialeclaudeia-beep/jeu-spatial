extends RefCounted
## Ce que l'air fait au vaisseau : TRAÎNÉE et PORTANCE, par de vraies forces (programme de départ :
## atmosphère).
##
## Le vaisseau est découpé en morceaux qui touchent l'air, mesurés sur le modèle 3D (v26) :
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

const CENTRE_GRAVITE := Vector3(0.0, 0.0147, 1.431)
const LONGUEUR := 10.3          # m, longueur du vaisseau (pour le régime moléculaire)

## Bandes d'une aile, dans le repère de sa charnière (aile repliée à plat) : [x du milieu (m),
## corde (m), envergure de la bande (m), z du quart avant de la corde (m)]. Mesuré sur le modèle 3D.
const BANDES := [
	[1.0, 3.1, 2.0, 1.68],
	[2.85, 2.1, 1.7, 1.83],
	[4.55, 1.9, 1.7, 1.73],
]
const ALLONGEMENT_AILES := 4.8   # envergure² / surface d'une paire d'ailes (haut ou bas), fuselage compris
const OUVERT := 22.249           # degrés, ouverture des ailes en X (comme AILES dans vaisseau_physique.gd)
## Dérives : [position du quart avant de la corde, normale, surface (m²), allongement (effet de la coque compris)]
const DERIVES := [
	[Vector3(-0.62, 1.2, 3.0), Vector3(1.0, 0.0, 0.0), 1.2, 1.4],
	[Vector3(0.62, 1.2, 3.0), Vector3(1.0, 0.0, 0.0), 1.2, 1.4],
]
## Fuselage (projections du modèle 3D) : surface de face, de côté, de dessus (m²).
const FACE := 3.34
const COTE := 13.07
const DESSUS := 12.68
const CENTRE_FUSELAGE := Vector3(0.0, 0.09, -0.5)   # centre des surfaces de côté et de dessus
## Portance du nez effilé (théorie des corps élancés) : 2 × la plus grande section × l'angle, posée là où
## la section grandit (moyenne des positions, pesée par la croissance de la section : mesuré sur le modèle).
const NEZ := Vector3(0.0, 0.0, -1.46)
const SECTION_MAX := 2.8
const FROTTEMENT_PLAQUE := 0.004                    # par face (couche limite turbulente)
const TRAIN_SURFACE := 0.9                          # m², roues et jambes face au vent (Cx ≈ 1)

## Son, phase 4 : « prise » des forces de chaque surface, en LECTURE SEULE (rien de ce qui est noté ici ne
## sert à la physique). Force (N) et couple autour du centre de gravité (N·m), repère du vaisseau, du dernier
## calcul. 0-3 : ailes haut gauche, haut droit, bas gauche, bas droit ; 4-5 : dérives gauche, droite ;
## 6 : fuselage ; 7 : nez ; 8 : train. Le son en tire la tension de chaque pièce (scripts/son/charges.gd).
const PRISE_SURFACES := 9
var prise_f := PackedVector3Array([Vector3.ZERO, Vector3.ZERO, Vector3.ZERO, Vector3.ZERO, Vector3.ZERO,
	Vector3.ZERO, Vector3.ZERO, Vector3.ZERO, Vector3.ZERO])
var prise_c := PackedVector3Array([Vector3.ZERO, Vector3.ZERO, Vector3.ZERO, Vector3.ZERO, Vector3.ZERO,
	Vector3.ZERO, Vector3.ZERO, Vector3.ZERO, Vector3.ZERO])
var _surface := 6   # surface en cours (prise du son)
## Son, phase 5 : « prise » de chaque plaque (12 bandes d'aile, dans l'ordre des ailes ci-dessous, puis les 2 dérives),
## en LECTURE SEULE : angle d'attaque vu par la plaque (rad, 0 à π/2), vitesse de l'air qu'elle voit (m/s), surface
## (m²), corde (m), et son point (repère du vaisseau). Le son en tire le décrochage et le tremblement transsonique
## (scripts/son/air_son.gd). Rien de ce qui est noté ici ne sert à la physique.
const PRISE_PLAQUES := 14
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
	if prise_alpha.size() != PRISE_PLAQUES:
		for a in [prise_alpha, prise_v, prise_surface, prise_corde]:
			a.resize(PRISE_PLAQUES)
		prise_point.resize(PRISE_PLAQUES)
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
	var kn := 6.63e-8 * 1.225 / rho / LONGUEUR
	var libre := clampf((log(kn) / log(10.0) + 1.0) / 2.0, 0.0, 1.0)   # 0 sous Kn = 0,1 ; 1 au-dessus de Kn = 10
	part_libre = libre   # prise du son (lecture seule)

	# 1. Les 4 ailes, 3 bandes chacune. Ailes repliées l'une sur l'autre, ou très proches : elles se gênent
	#    (biplan) ; l'écart entre l'aile du haut et celle du bas, rapporté à la corde, dit de combien.
	var ouverture := deg_to_rad(OUVERT * ailes)
	_surface = 0
	for nom in ["haut_gauche", "haut_droit", "bas_gauche", "bas_droit"]:
		var gauche: bool = nom.ends_with("gauche")
		var haut: bool = nom.begins_with("haut")
		var angle := ouverture * (-1.0 if gauche else 1.0)
		if not haut:
			angle = (PI - ouverture) * (-1.0 if gauche else 1.0)
		var rot := Basis(Vector3.BACK, angle)
		var charniere := Vector3(-0.6 if gauche else 0.6, 0.0, 0.0)
		var normale: Vector3 = rot * Vector3.UP
		for b in BANDES:
			var x: float = b[0] * (-1.0 if gauche != (not haut) else 1.0)
			# (repère de la charnière : l'aile droite s'étend vers +x ; tournée de 180°, l'aile du bas
			# s'étend vers −x de son repère)
			var p: Vector3 = charniere + rot * Vector3(x, 0.0, float(b[3]))
			var corde: float = b[1]
			var surface: float = corde * float(b[2])
			var ecart := 2.0 * absf(float(b[0])) * sin(ouverture)
			var gene := 0.5 + 0.35 * clampf(ecart / corde, 0.0, 1.0)
			_plaque(p, normale, surface, ALLONGEMENT_AILES, gene, vent_corps, omega, rho, son, libre, corde)
		_surface += 1
	# 2. Les dérives
	for d in DERIVES:
		_plaque(d[0], d[1], d[2], d[3], 1.0, vent_corps, omega, rho, son, libre)
		_surface += 1
	# 3. Le fuselage. Vent vu par son centre (la rotation compte aussi).
	_surface = 6
	var r_c := CENTRE_FUSELAGE - CENTRE_GRAVITE
	var w := vent_corps - omega.cross(r_c)
	var q := 0.5 * rho
	var m := w.length() / maxf(son, 1.0)
	# de face (le long de l'axe) : nez pointu, culot, onde de choc au-delà du son
	var cx := lerpf(cx_face(m), 2.2, libre)
	var f_ax := Vector3(0.0, 0.0, q * cx * FACE * absf(w.z) * w.z)
	# de travers (loi d'Allen) : chaque tranche du fuselage freine l'air qui la traverse comme un cylindre
	var cdc := lerpf(1.2, 2.2, libre)
	var f_tr := Vector3(q * cdc * COTE * absf(w.x) * w.x, q * cdc * DESSUS * absf(w.y) * w.y, 0.0)
	_ajouter(r_c, f_ax + f_tr)
	# portance du nez effilé (corps élancé : 2 × surface de face × angle), seulement en fluide
	var r_n := NEZ - CENTRE_GRAVITE
	var wn := vent_corps - omega.cross(r_n)
	_surface = 7
	if wn.z > 0.0 and libre < 1.0:
		var vn := wn.length()
		var f_nez := Vector3(wn.x, wn.y, 0.0) * (q * 2.0 * SECTION_MAX * vn * absf(wn.z) / maxf(vn, 1e-6) * (1.0 - libre))
		# l'air qui arrive par en dessous pousse le nez vers le haut (même sens que la vitesse de travers)
		_ajouter(r_n, f_nez)
	# 4. Le train sorti
	_surface = 8
	if train > 0.0:
		var r_t := Vector3(0.0, -1.3, -1.0) - CENTRE_GRAVITE
		var wt := vent_corps - omega.cross(r_t)
		_ajouter(r_t, wt * (q * TRAIN_SURFACE * train * wt.length()))

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
	var r := p - CENTRE_GRAVITE
	var w := vent_corps - omega.cross(r)   # air vu par la plaque
	var v := w.length()
	var k_prise := _plaque_n   # prise du son (lecture seule)
	_plaque_n += 1
	if k_prise < PRISE_PLAQUES:
		prise_point[k_prise] = p
		prise_surface[k_prise] = surface
		prise_corde[k_prise] = corde_prise if corde_prise > 0.0 else sqrt(surface / ar)
	if v < 1e-6:
		return
	var q := 0.5 * rho * v * v
	var m := v / maxf(son, 1.0)
	var wn := w.dot(n)
	var alpha := asin(clampf(wn / v, -1.0, 1.0))   # > 0 : l'air frappe la face de dessous et pousse vers +n
	if k_prise < PRISE_PLAQUES:
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
