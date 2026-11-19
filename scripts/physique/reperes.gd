extends RefCounted
## Einstein A3 : UN REPÈRE PAR SYSTÈME D'ÉTOILE.
##
## Les nombres de l'ordinateur (64 bits) gardent environ 16 chiffres. Entre deux étoiles (4e16 m), il
## ne reste donc que quelques mètres de précision : impossible de se poser ou de tourner autour d'une
## planète si l'on compte toujours depuis la maison. Comme les vrais navigateurs de l'espace, chaque
## système d'étoile a donc SON repère, centré sur son étoile principale, et qui avance avec elle.
## Le vaisseau compte toujours sa position dans le repère du système où il se trouve : ses nombres
## restent petits et précis, même à 4 années-lumière de chez lui.
##
## Les étoiles bougent les unes par rapport aux autres (Alpha du Centaure vient vers nous à 22 km/s) :
## passer d'un repère à l'autre est donc une vraie TRANSFORMATION DE LORENTZ (relativité restreinte)
## sur la position, l'heure ET la vitesse du vaisseau. Chaque repère a sa propre horloge (« temps de
## l'univers » du vaisseau = l'heure de son repère) ; l'heure de la maison se retrouve à tout moment.
##
## Le repère de la maison, c'est celui de la physique depuis le début : centré sur la planète (qui ne
## bouge pas par rapport au Soleil). Les autres sont placés à leur vraie direction dans le ciel
## (catalogue Hipparcos/Gaia), à leur vraie distance, avec leur vraie vitesse.
##
## Le vaisseau change de repère quand il est nettement plus près d'un autre système (à mi-chemin, en
## plein vide : rien ne change pour lui, sauf ses nombres et la gravité qu'il sent).

const Etoiles = preload("res://scripts/lumiere/etoiles.gd")
const LumiereJeu = preload("res://scripts/lumiere_jeu.gd")

const C := 299792458.0                   # m/s
const UA := 1.495978707e11               # m
const PARSEC := 3.0856775814913673e16    # m
const ANNEE_LUMIERE := 9.4607304725808e15   # m
const GM_SOLEIL := 1.32712440018e20      # m³/s²
const RAYON_SOLEIL := 6.957e8            # m
## Vitesse sur le ciel (m/s) d'une étoile à 1 pc qui avance de 1 millième de seconde d'arc par an.
const M_S_PAR_MAS_PC := 4.740470446
## On change de repère quand un autre système est à moins de 0,8 fois la distance du système actuel
## (pas d'aller-retour sans fin à mi-chemin).
const HYSTERESIS := 0.8
## Magnitude « effacée » d'une étoile du catalogue qu'on dessine autrement (log10 des lux).
const LUX_EFFACE := -40.0

var systemes: Array = []     # chaque système : Dictionary (voir _systeme)
var courant := 0             # système où se trouve le vaisseau (0 = la maison)
var changements := 0         # nombre de changements de repère (tests, affichage)
## Gravité de la maison (planète, sa lune, le Soleil…), gardée pendant que le vaisseau est ailleurs.
var _maison := {}
var _angle_depart := 0.0     # angle de la planète (rotation) au départ de la maison
var _t_depart := 0.0         # heure de la maison au départ
var _omega_maison := 0.0
## Catalogue d'étoiles (ciel) : les étoiles de nos systèmes, à redessiner selon où l'on est.
var _yale: Array = []        # {systeme, etoile, indice, donnee (Color d'origine), m0, d0}
var _compagne_maison := {}


func _init() -> void:
	# --- La maison : la planète, le Soleil à 1 UA, l'étoile compagne à 5 UA (comme lumiere_jeu.gd).
	var p_soleil: PackedFloat64Array = LumiereJeu._loin(LumiereJeu.VERS_SOLEIL, UA)
	var p_compagne: PackedFloat64Array = LumiereJeu._loin(LumiereJeu.VERS_COMPAGNE, LumiereJeu.DISTANCE_COMPAGNE * UA)
	var maison := _systeme("Soleil", true, PackedFloat64Array([0.0, 0.0, 0.0]), PackedFloat64Array([0.0, 0.0, 0.0]))
	maison["etoiles"] = [
		_etoile("Soleil", 1.0, 1.0, 5772.0, p_soleil),
		_etoile("Compagne", 0.69, 0.70, 4400.0, p_compagne),
	]
	maison["lumiere_soleil"] = 0
	maison["lumiere_compagne"] = 1
	systemes.append(maison)

	# --- Alpha du Centaure A et B (catalogue Hipparcos révisé, Gaia ; Kervella et al. 2016-2017).
	#     Ascension droite 14 h 39 min 36,5 s, déclinaison −60° 50′ 02″, parallaxe 747,1 mas (4,37 al),
	#     mouvement propre −3 679 / +474 mas/an, vitesse radiale −22,4 km/s (elle vient vers nous).
	var a := _depuis_catalogue(p_soleil, 219.9021, -60.8340, 747.1, -3679.25, 473.67, -22.4)
	var alpha := _systeme("Alpha du Centaure", false, a[0], a[1])
	# A au centre du repère ; B à 13 UA (les deux tournent l'un autour de l'autre en 80 ans : ici immobiles).
	var e: PackedFloat64Array = a[2]
	var nord: PackedFloat64Array = a[3]
	var p_b := PackedFloat64Array([(0.6 * e[0] + 0.8 * nord[0]) * 13.0 * UA, (0.6 * e[1] + 0.8 * nord[1]) * 13.0 * UA,
		(0.6 * e[2] + 0.8 * nord[2]) * 13.0 * UA])
	alpha["etoiles"] = [
		_etoile("Alpha du Centaure A", 1.0788, 1.2175, 5790.0, PackedFloat64Array([0.0, 0.0, 0.0])),
		_etoile("Alpha du Centaure B", 0.9092, 0.8591, 5260.0, p_b),
	]
	alpha["etoiles"][0]["catalogue"] = [219.9021, -60.8340, -0.01]   # ad, dec, magnitude vue de la Terre
	alpha["etoiles"][1]["catalogue"] = [219.8961, -60.8375, 1.33]
	alpha["lumiere_soleil"] = 0      # A ressemble au Soleil (5 790 K) : elle prend sa place pour la lumière
	alpha["lumiere_compagne"] = 1
	systemes.append(alpha)

	# --- Proxima du Centaure (naine rouge, 3 042 K) : 14 h 29 min 43 s, −62° 40′ 46″, 768,1 mas (4,25 al),
	#     mouvement propre −3 781 / +770 mas/an, vitesse radiale −22,2 km/s.
	var b := _depuis_catalogue(p_soleil, 217.4290, -62.6795, 768.07, -3781.3, 769.8, -22.2)
	var proxima := _systeme("Proxima du Centaure", false, b[0], b[1])
	proxima["etoiles"] = [_etoile("Proxima du Centaure", 0.1221, 0.1542, 3042.0, PackedFloat64Array([0.0, 0.0, 0.0]))]
	proxima["lumiere_soleil"] = -1   # le Soleil, au loin, reste dans son emplacement
	proxima["lumiere_compagne"] = 0
	systemes.append(proxima)

	# --- Einstein B : Gaia BH1, le trou noir connu le plus proche (El-Badry et al. 2023, Gaia DR3 ;
	#     masse : Nagarajan et al. 2023, ESPRESSO). 17 h 28 min 41,1 s, −0° 34′ 52″, parallaxe 2,09 mas
	#     (1 560 al), mouvement propre −7,70 / −25,85 mas/an, vitesse radiale du système ≈ 46,6 km/s.
	#     Un trou noir de 9,27 Soleils, éteint (rien ne tombe dedans), et une étoile jumelle du Soleil
	#     (0,93 Soleil, 5 850 K) qui tourne autour de lui en 185 jours, à 1,4 UA (ici immobile).
	var c := _depuis_catalogue(p_soleil, 262.171236, -0.581001, 2.09, -7.70, -25.85, 46.6)
	var bh := _systeme("Gaia BH1", false, c[0], c[1])
	var trou := _etoile("Gaia BH1 (trou noir)", 9.27, 0.0, 0.0, PackedFloat64Array([0.0, 0.0, 0.0]))
	trou["trou_noir"] = true
	# son « rayon » : l'horizon, en coordonnées isotropes (celles de la physique) : G·M / (2c²)
	trou["rayon"] = float(trou["gm"]) / (2.0 * C * C)
	var e3: PackedFloat64Array = c[2]
	bh["etoiles"] = [trou, _etoile("Gaia BH1 étoile", 0.93, 0.99, 5850.0,
		PackedFloat64Array([e3[0] * 1.40 * UA, e3[1] * 1.40 * UA, e3[2] * 1.40 * UA]))]
	bh["lumiere_soleil"] = 1     # l'étoile jumelle du Soleil prend sa place pour la lumière
	bh["lumiere_compagne"] = -1  # notre Soleil, au loin (invisible à l'œil nu d'ici), dans l'autre
	systemes.append(bh)


static func _systeme(nom: String, maison: bool, o: PackedFloat64Array, v: PackedFloat64Array) -> Dictionary:
	var vl := sqrt(v[0] * v[0] + v[1] * v[1] + v[2] * v[2])
	var n := PackedFloat64Array([1.0, 0.0, 0.0])
	if vl > 0.0:
		n = PackedFloat64Array([v[0] / vl, v[1] / vl, v[2] / vl])
	return {"nom": nom, "maison": maison, "o": o, "v": v, "vitesse": vl, "n": n,
		"gamma": 1.0 / sqrt(1.0 - (vl / C) * (vl / C)), "etoiles": []}


static func _etoile(nom: String, masse_soleils: float, rayon_soleils: float, temperature: float, p: PackedFloat64Array) -> Dictionary:
	return {"nom": nom, "gm": GM_SOLEIL * masse_soleils, "rayon": RAYON_SOLEIL * rayon_soleils,
		"temperature": temperature, "p": p}


## Direction du ciel (même convention que etoiles.gd), en 64 bits.
static func _direction(ad_deg: float, dec_deg: float) -> PackedFloat64Array:
	var ad := deg_to_rad(ad_deg)
	var dec := deg_to_rad(dec_deg)
	return PackedFloat64Array([cos(dec) * cos(ad), sin(dec), -cos(dec) * sin(ad)])


## Position (repère de la maison, au temps 0) et vitesse d'une étoile à partir du catalogue :
## [position, vitesse, direction « est », direction « nord »].
static func _depuis_catalogue(p_soleil: PackedFloat64Array, ad_deg: float, dec_deg: float, parallaxe_mas: float,
		pm_ad_mas: float, pm_dec_mas: float, vr_km_s: float) -> Array:
	var d_pc := 1000.0 / parallaxe_mas
	var n := _direction(ad_deg, dec_deg)
	var ad := deg_to_rad(ad_deg)
	var dec := deg_to_rad(dec_deg)
	var est := PackedFloat64Array([-sin(ad), 0.0, -cos(ad)])
	var nord := PackedFloat64Array([-sin(dec) * cos(ad), cos(dec), sin(dec) * sin(ad)])
	var ve := M_S_PAR_MAS_PC * pm_ad_mas * d_pc
	var vn := M_S_PAR_MAS_PC * pm_dec_mas * d_pc
	var vr := vr_km_s * 1000.0
	var o := PackedFloat64Array()
	var v := PackedFloat64Array()
	for k in 3:
		o.append(p_soleil[k] + n[k] * d_pc * PARSEC)
		v.append(vr * n[k] + ve * est[k] + vn * nord[k])
	return [o, v, est, nord]


# =====================================================================
# TRANSFORMATIONS DE LORENTZ (repère d'un système ↔ repère de la maison)
# =====================================================================
## Un événement (heure t, position x) du système i → [heure, position] dans le repère de la maison.
## Le repère i avance à la vitesse V (vue de la maison) ; son centre était en o à l'heure 0 de la maison.
func vers_maison(i: int, t: float, x: PackedFloat64Array) -> Array:
	var s: Dictionary = systemes[i]
	if s["maison"]:
		return [t, x.duplicate()]
	var g: float = s["gamma"]
	var b: float = s["vitesse"]
	var n: PackedFloat64Array = s["n"]
	var o: PackedFloat64Array = s["o"]
	var xn := x[0] * n[0] + x[1] * n[1] + x[2] * n[2]
	var t_m := g * (t + b * xn / (C * C))
	var k := (g - 1.0) * xn + g * b * t
	return [t_m, PackedFloat64Array([o[0] + x[0] + k * n[0], o[1] + x[1] + k * n[1], o[2] + x[2] + k * n[2]])]


## L'inverse : un événement de la maison → [heure, position] dans le repère du système i.
func depuis_maison(i: int, t_m: float, x_m: PackedFloat64Array) -> Array:
	var s: Dictionary = systemes[i]
	if s["maison"]:
		return [t_m, x_m.duplicate()]
	var g: float = s["gamma"]
	var b: float = s["vitesse"]
	var n: PackedFloat64Array = s["n"]
	var o: PackedFloat64Array = s["o"]
	var dx := PackedFloat64Array([x_m[0] - o[0], x_m[1] - o[1], x_m[2] - o[2]])
	var xn := dx[0] * n[0] + dx[1] * n[1] + dx[2] * n[2]
	var t := g * (t_m - b * xn / (C * C))
	var k := (g - 1.0) * xn - g * b * t_m
	return [t, PackedFloat64Array([dx[0] + k * n[0], dx[1] + k * n[1], dx[2] + k * n[2]])]


## Vitesse propre u (m/s du pilote, u = γv) du système i → vue de la maison. Ce sont les 3 dernières
## composantes de la « quadrivitesse » (cU⁰, u), U⁰ = √(1 + u²/c²) : elle se transforme comme un événement.
func vitesse_vers_maison(i: int, u: PackedFloat64Array) -> PackedFloat64Array:
	return _booster(i, u, 1.0)


func vitesse_depuis_maison(i: int, u: PackedFloat64Array) -> PackedFloat64Array:
	return _booster(i, u, -1.0)


func _booster(i: int, u: PackedFloat64Array, sens: float) -> PackedFloat64Array:
	var s: Dictionary = systemes[i]
	if s["maison"]:
		return u.duplicate()
	var g: float = s["gamma"]
	var b: float = s["vitesse"] * sens
	var n: PackedFloat64Array = s["n"]
	var u0 := sqrt(1.0 + (u[0] * u[0] + u[1] * u[1] + u[2] * u[2]) / (C * C))
	var un := u[0] * n[0] + u[1] * n[1] + u[2] * n[2]
	var k := (g - 1.0) * un + g * b * u0
	return PackedFloat64Array([u[0] + k * n[0], u[1] + k * n[1], u[2] + k * n[2]])


## Vraie position (repère de la maison) de l'étoile e du système i à l'heure t_m de la maison.
func position_etoile_maison(i: int, e: int, t_m: float) -> PackedFloat64Array:
	var s: Dictionary = systemes[i]
	var p: PackedFloat64Array = s["etoiles"][e]["p"]
	if s["maison"]:
		return p.duplicate()
	var n: PackedFloat64Array = s["n"]
	var xn := p[0] * n[0] + p[1] * n[1] + p[2] * n[2]
	# heure de l'étoile (dans son repère) qui correspond à l'heure t_m de la maison, là où elle est
	var t: float = t_m / float(s["gamma"]) - float(s["vitesse"]) * xn / (C * C)
	return vers_maison(i, t, p)[1]


## Centre du système i (son étoile principale) à l'heure t_m de la maison (repère de la maison).
func centre_maison(i: int, t_m: float) -> PackedFloat64Array:
	var s: Dictionary = systemes[i]
	var o: PackedFloat64Array = s["o"]
	var v: PackedFloat64Array = s["v"]
	return PackedFloat64Array([o[0] + v[0] * t_m, o[1] + v[1] * t_m, o[2] + v[2] * t_m])


# =====================================================================
# LE VAISSEAU
# =====================================================================
## À appeler une fois, quand la gravité de la maison est prête (planète, lune) : ajoute celle du
## Soleil et de l'étoile compagne. Le repère de la maison suit la planète, qui tombe elle aussi vers
## elles : on retire donc leur attraction sur la planète (« terme indirect », comme pour la lune). Il
## reste leur marée (minuscule près de la planète) et, loin d'elle, leur vraie attraction.
func preparer(v) -> void:
	for e in systemes[0]["etoiles"]:
		var p: PackedFloat64Array = e["p"]
		v.autres_astres.append({"nom": e["nom"], "gm": e["gm"], "x": p[0], "y": p[1], "z": p[2], "indirect": true})
	courant = 0


func nom_courant() -> String:
	return String(systemes[courant]["nom"])


func a_la_maison() -> bool:
	return courant == 0


## Événement actuel du vaisseau dans le repère de la maison : [heure, position].
func evenement_maison(v) -> Array:
	return vers_maison(courant, v.temps_univers, PackedFloat64Array([v.px, v.py, v.pz]))


## Heure de la maison (s) pour le vaisseau maintenant.
func heure_maison(v) -> float:
	return float(evenement_maison(v)[0])


## Vitesse du vaisseau vue de la maison (m/s, toujours < C).
func vitesse_maison(v) -> PackedFloat64Array:
	v.gamma()   # met la vitesse propre à jour si quelqu'un a écrit vx à la main
	var u := vitesse_vers_maison(courant, PackedFloat64Array([v.ux, v.uy, v.uz]))
	var g := sqrt(1.0 + (u[0] * u[0] + u[1] * u[1] + u[2] * u[2]) / (C * C))
	return PackedFloat64Array([u[0] / g, u[1] / g, u[2] / g])


## Angle de rotation de la planète de la maison à l'heure t_m de la maison.
func angle_planete_maison(v, t_m: float) -> float:
	if a_la_maison():
		return v.angle_planete
	return fposmod(_angle_depart + _omega_maison * (t_m - _t_depart), TAU)


## Étoile la plus proche du système actuel : [nom, distance au centre (m), rayon (m)].
func etoile_proche(v) -> Array:
	var meilleure := []
	for e in systemes[courant]["etoiles"]:
		var p: PackedFloat64Array = e["p"]
		var d := sqrt((v.px - p[0]) ** 2 + (v.py - p[1]) ** 2 + (v.pz - p[2]) ** 2)
		if meilleure.is_empty() or d < float(meilleure[1]):
			meilleure = [e["nom"], d, e["rayon"], e.get("trou_noir", false)]
	return meilleure


## À chaque image : le vaisseau entre-t-il dans une étoile ? Est-il plus près d'un autre système ?
## Renvoie vrai si le repère a changé.
func verifier(v) -> bool:
	var proche := etoile_proche(v)
	if not proche.is_empty() and float(proche[1]) < float(proche[2]) and not v.ecrase:
		v.ecrase = true   # dans une étoile : brûlé (dans un trou noir : passé l'horizon)
		v.vitesse_impact = v.vitesse()
		if proche.size() > 3 and proche[3]:
			v.avale = true
	var ev := evenement_maison(v)
	var t_m: float = ev[0]
	var x_m: PackedFloat64Array = ev[1]
	var d_courant := _distance_systeme(courant, t_m, x_m)
	var meilleur := courant
	var d_meilleur := d_courant
	for i in systemes.size():
		var d := _distance_systeme(i, t_m, x_m)
		if d < d_meilleur:
			meilleur = i
			d_meilleur = d
	if meilleur != courant and d_meilleur < HYSTERESIS * d_courant:
		passer(v, meilleur)
		return true
	return false


func _distance_systeme(i: int, t_m: float, x_m: PackedFloat64Array) -> float:
	var c := centre_maison(i, t_m)
	return sqrt((x_m[0] - c[0]) ** 2 + (x_m[1] - c[1]) ** 2 + (x_m[2] - c[2]) ** 2)


## Fait passer le vaisseau dans le repère du système j : position, heure et vitesse transformées
## (Lorentz), gravité de ce système. L'horloge du pilote, l'orientation et la rotation ne changent pas.
func passer(v, j: int) -> void:
	if j == courant:
		return
	var ev := evenement_maison(v)
	var t_m: float = ev[0]
	var u_m := vitesse_vers_maison(courant, PackedFloat64Array([v.ux, v.uy, v.uz]))
	if a_la_maison():
		_maison = {"gm": v.gm, "rayon_planete": v.rayon_planete, "relief": v.relief, "omega_planete": v.omega_planete,
			"autres_astres": v.autres_astres}
		_angle_depart = v.angle_planete
		_omega_maison = v.omega_planete
		_t_depart = t_m
	var ev_j := depuis_maison(j, t_m, ev[1])
	var p: PackedFloat64Array = ev_j[1]
	var u := vitesse_depuis_maison(j, u_m)
	v.px = p[0]
	v.py = p[1]
	v.pz = p[2]
	v.ux = u[0]
	v.uy = u[1]
	v.uz = u[2]
	v._ecrire_vitesse()
	v.temps_univers = float(ev_j[0])
	v._touchait.clear()
	v._accroches.clear()
	courant = j
	changements += 1
	_regler_gravite(v, t_m)


func _regler_gravite(v, t_m: float) -> void:
	if a_la_maison():
		if not _maison.is_empty():
			v.gm = _maison["gm"]
			v.rayon_planete = _maison["rayon_planete"]
			v.relief = _maison["relief"]
			v.omega_planete = _maison["omega_planete"]
			v.autres_astres = _maison["autres_astres"]
			v.angle_planete = fposmod(_angle_depart + _omega_maison * (t_m - _t_depart), TAU)
		return
	# Ailleurs : l'étoile principale au centre, les autres étoiles immobiles autour (pas de sol).
	var etoiles: Array = systemes[courant]["etoiles"]
	v.gm = etoiles[0]["gm"]
	v.rayon_planete = 0.0
	v.relief = Callable()
	v.omega_planete = 0.0
	v.angle_planete = 0.0
	var autres := []
	for k in range(1, etoiles.size()):
		var p: PackedFloat64Array = etoiles[k]["p"]
		autres.append({"nom": etoiles[k]["nom"], "gm": etoiles[k]["gm"], "x": p[0], "y": p[1], "z": p[2]})
	v.autres_astres = autres


## Einstein C : arrivée par un trou de ver dans le système j, à la position p avec la vitesse propre u
## (déjà dans le repère de j). Pas de transformation de Lorentz : la bouche d'arrivée est immobile dans
## son système, le vaisseau en sort avec la vitesse qu'il a par rapport à elle. Même heure de l'univers.
func sauter(v, j: int, p: PackedFloat64Array, u: PackedFloat64Array) -> void:
	if a_la_maison() and j != 0:
		_maison = {"gm": v.gm, "rayon_planete": v.rayon_planete, "relief": v.relief, "omega_planete": v.omega_planete,
			"autres_astres": v.autres_astres}
		_angle_depart = v.angle_planete
		_omega_maison = v.omega_planete
		_t_depart = heure_maison(v)
	courant = j
	v.px = p[0]
	v.py = p[1]
	v.pz = p[2]
	v.ux = u[0]
	v.uy = u[1]
	v.uz = u[2]
	v._ecrire_vitesse()
	v._touchait.clear()
	v._accroches.clear()
	changements += 1
	_regler_gravite(v, heure_maison(v))


## Retour immédiat à la maison (touche « remettre en orbite ») : gravité de la maison remise.
func revenir_maison(v) -> void:
	if a_la_maison():
		return
	courant = 0
	_regler_gravite(v, _t_depart)


# =====================================================================
# LA LUMIÈRE (système de lumière du jeu)
# =====================================================================
## Place les deux étoiles éclairantes du système de lumière (emplacements « Soleil » et « compagne »)
## selon le système où l'on est, et redessine dans le ciel les étoiles de nos systèmes qui n'y sont pas,
## à leur vraie direction et à leur vrai éclat vus d'où l'on est. oeil_m = l'œil dans le repère de la
## maison (64 bits), t_m = heure de la maison.
func regler_lumiere(lumiere, oeil_m: PackedFloat64Array, t_m: float) -> void:
	if _compagne_maison.is_empty():
		_compagne_maison = {"position": lumiere.compagne.position, "rayon": lumiere.compagne.rayon,
			"temperature": lumiere.compagne.temperature, "nom": lumiere.compagne.nom}
		_trouver_catalogue(lumiere)
	var s: Dictionary = systemes[courant]
	var dans_emplacement := {}
	# emplacement « Soleil » : la lumière y est celle du Soleil (même éclat par m² de surface). Une
	# étoile plus grande y est mise plus loin (même taille et même éclairement vus de l'œil).
	var i_s: int = s["lumiere_soleil"]
	if i_s < 0:
		lumiere.soleil.position = systemes[0]["etoiles"][0]["p"]
	else:
		var e: Dictionary = s["etoiles"][i_s]
		var p := position_etoile_maison(courant, i_s, t_m)
		var k: float = RAYON_SOLEIL / float(e["rayon"])
		lumiere.soleil.position = PackedFloat64Array([oeil_m[0] + (p[0] - oeil_m[0]) * k,
			oeil_m[1] + (p[1] - oeil_m[1]) * k, oeil_m[2] + (p[2] - oeil_m[2]) * k])
		dans_emplacement[str(courant) + ":" + str(i_s)] = true
	var i_c: int = s["lumiere_compagne"]
	if i_c < 0:
		# pas de seconde étoile ici : notre Soleil, à sa vraie place (de très loin, un point très faible)
		lumiere.compagne.position = systemes[0]["etoiles"][0]["p"]
		lumiere.compagne.rayon = RAYON_SOLEIL
		lumiere.compagne.temperature = 5772.0
		lumiere.compagne.nom = "Soleil"
	elif s["maison"]:
		lumiere.compagne.position = _compagne_maison["position"]
		lumiere.compagne.rayon = _compagne_maison["rayon"]
		lumiere.compagne.temperature = _compagne_maison["temperature"]
		lumiere.compagne.nom = _compagne_maison["nom"]
	else:
		var e2: Dictionary = s["etoiles"][i_c]
		lumiere.compagne.position = position_etoile_maison(courant, i_c, t_m)
		lumiere.compagne.rayon = e2["rayon"]
		lumiere.compagne.temperature = e2["temperature"]
		lumiere.compagne.nom = e2["nom"]
		dans_emplacement[str(courant) + ":" + str(i_c)] = true
	# étoiles du catalogue (ciel) qui appartiennent à nos systèmes
	if lumiere.noeud_etoiles == null:
		return
	var mm: MultiMesh = lumiere.noeud_etoiles.multimesh
	for y in _yale:
		var cle := str(y["systeme"]) + ":" + str(y["etoile"])
		var donnee: Color = y["donnee"]
		if dans_emplacement.has(cle):
			y["lg"] = LUX_EFFACE
			mm.set_instance_custom_data(y["indice"], Color(LUX_EFFACE, donnee.g, 0.0, 0.0))
			continue
		var p := position_etoile_maison(y["systeme"], y["etoile"], t_m)
		var dx := p[0] - oeil_m[0]
		var dy := p[1] - oeil_m[1]
		var dz := p[2] - oeil_m[2]
		var d := sqrt(dx * dx + dy * dy + dz * dz)
		# éclat : 1/distance² (magnitude + 5 log10(d / d0))
		var lg: float = donnee.r - 2.0 * log(d / float(y["d0"])) / log(10.0)
		y["lg"] = lg
		mm.set_instance_transform(y["indice"], Transform3D(Basis.IDENTITY, Vector3(dx / d, dy / d, dz / d)))
		mm.set_instance_custom_data(y["indice"], Color(lg, donnee.g, 0.0, 0.0))


## Retrouve dans le catalogue de Yale les étoiles de nos systèmes (la plus brillante près de la bonne place).
func _trouver_catalogue(lumiere) -> void:
	_yale.clear()
	var cat = lumiere.etoiles
	if lumiere.noeud_etoiles == null or cat.nombre == 0:
		return
	var pris := {}
	for i in systemes.size():
		var ets: Array = systemes[i]["etoiles"]
		for k in ets.size():
			if not ets[k].has("catalogue"):
				continue
			var c: Array = ets[k]["catalogue"]
			var n := Etoiles.direction_ciel_degres(c[0], c[1])
			var trouve := -1
			var ecart := INF
			for j in cat.nombre:
				if pris.has(j) or cat.magnitude[j] > float(c[2]) + 1.0:
					continue
				var a := Etoiles.direction_ciel(cat.ascension[j], cat.declinaison[j]).angle_to(n)
				if a < deg_to_rad(0.2) and absf(cat.magnitude[j] - float(c[2])) < ecart:
					ecart = absf(cat.magnitude[j] - float(c[2]))
					trouve = j
			if trouve < 0:
				continue
			pris[trouve] = true
			var p := position_etoile_maison(i, k, 0.0)
			var s0: PackedFloat64Array = systemes[0]["etoiles"][0]["p"]
			var d0 := sqrt((p[0] - s0[0]) ** 2 + (p[1] - s0[1]) ** 2 + (p[2] - s0[2]) ** 2)
			# éclat (log10 des lux) et température, comme etoiles.gd les range dans le nœud du ciel
			var donnee := Color(log(Etoiles.lux(cat.magnitude[trouve])) / log(10.0),
				Etoiles.temperature(cat.couleur_bv[trouve]) / 10000.0, 0.0, 0.0)
			_yale.append({"systeme": i, "etoile": k, "indice": trouve, "donnee": donnee, "d0": d0, "lg": donnee.r})


# =====================================================================
# EINSTEIN B : LE TROU NOIR
# =====================================================================
## Indice du système de Gaia BH1.
func systeme_trou_noir() -> int:
	for i in systemes.size():
		for e in systemes[i]["etoiles"]:
			if e.get("trou_noir", false):
				return i
	return -1


## Saut d'essai (touche M), comme « remettre en orbite » : ce n'est pas un voyage (il faudrait
## 1 560 ans de l'univers, même à la vitesse de la lumière). Le vaisseau est posé en orbite circulaire
## autour de Gaia BH1, à la distance demandée (centre du trou noir), nez pointé vers lui.
func aller_trou_noir(v, distance_m: float) -> void:
	var j := systeme_trou_noir()
	if j < 0:
		return
	if courant != j:
		passer(v, j)
	v.placer_en_orbite(distance_m)
	v.orientation = Quaternion(Vector3.UP, PI * 0.5)   # l'avant (-Z) regarde vers -X : vers le trou noir


## Trou noir du système actuel : [indice de l'étoile, G·M] ou [] s'il n'y en a pas.
func trou_noir_courant() -> Array:
	var ets: Array = systemes[courant]["etoiles"]
	for k in ets.size():
		if ets[k].get("trou_noir", false):
			return [k, float(ets[k]["gm"])]
	return []


## Lumière courbée : donne au système de lumière la direction du trou noir vue de l'œil (repère de la
## maison, comme le ciel) et sa distance (rayon de Schwarzschild), ou coupe la lentille s'il n'y en a pas.
## oeil = l'œil dans le repère du système (physique).
func regler_lentille(lumiere, oeil: PackedFloat64Array) -> void:
	var t := trou_noir_courant()
	if t.is_empty():
		lumiere.regler_lentille(Vector3.ZERO, 0.0, 0.0)
		return
	var p: PackedFloat64Array = systemes[courant]["etoiles"][t[0]]["p"]
	var r := sqrt((oeil[0] - p[0]) ** 2 + (oeil[1] - p[1]) ** 2 + (oeil[2] - p[2]) ** 2)
	var m: float = float(t[1]) / (C * C)
	var r_s := r * (1.0 + 0.5 * m / r) ** 2   # isotrope → Schwarzschild
	# direction comptée dans le repère du système (nombres petits, donc précis) : les axes sont les mêmes
	# que ceux de la maison (l'écart d'aberration, 50 km/s, fait 0,01° : invisible)
	var d := Vector3(p[0] - oeil[0], p[1] - oeil[1], p[2] - oeil[2]).normalized()
	lumiere.regler_lentille(d, 2.0 * m, r_s)
