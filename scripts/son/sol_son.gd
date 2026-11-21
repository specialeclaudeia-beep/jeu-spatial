extends RefCounted
## Le sol (moteur audio, phase 3) : ce que le pilote entend quand le vaisseau touche, roule, freine, dérape
## ou racle, et le bruit des vérins (train, ailes, roue avant, tuyères).
##
## Chocs : l'idée de Gwenaël (21/11). Chaque chose qui frappe a une MASSE et une VITESSE ; la pièce frappée
## (pneu, jambe d'acier, panneau d'aluminium de la coque) se déforme et absorbe l'énergie ½ m v². Une petite
## part de cette énergie de déformation repart en vibration : c'est le son. Donc :
##   - le niveau suit l'énergie : +10 dB quand l'énergie est 10 fois plus grande ;
##   - la matière frappée donne le timbre : ses fréquences propres et sa durée de résonance (fiches de la
##     bibliothèque, fabriquées par synthèse modale : synthese.gd) et la part d'énergie qui devient du son
##     (caoutchouc : très peu, il amortit ; acier contre acier : beaucoup) ;
##   - la vitesse donne la durée du contact (loi de Hertz : plus c'est rapide, plus c'est bref, plus c'est
##     aigu) : c'est « l'intensité » qui choisit la fiche.
## Les masses : la part du vaisseau que porte la roue ou le point de la coque qui touche (masse « vue » par le
## choc) ; pour un caillou projeté par une roue, sa propre masse (5 à 50 g) et la vitesse que la roue lui donne.
## Plus tard (phase 4), les grains de poussière de l'espace sur la verrière suivront la même règle.
##
## Sons continus (voix C++) : roulement des pneus (le sol rugueux secoue la roue : grave qui monte avec la
## vitesse), pneu qui dérape (crissement vers 1 kHz), frein (frottement des disques), coque qui racle,
## vérins (pompe hydraulique qui siffle, huile qui coule). Tout passe par la structure jusqu'au cockpit
## (1 dB perdu par mètre, comme pour les moteurs).
##
## Les niveaux de référence sont des réglages « à l'oreille » (à valider à l'écoute sur le PC) ; les lois
## (énergie, vitesse, force qui appuie) sont celles de la physique.

const Capteurs = preload("res://scripts/son/capteurs.gd")
const Fluides = preload("res://scripts/son/fluides_son.gd")
const Resonances = preload("res://scripts/son/resonances.gd")

const ATTENUATION := 1.0        # dB par mètre de structure (comme moteurs_son.gd)
## Part du poids portée par chaque roue (centre de gravité près des roues arrière : 86 % derrière) et masse
## « vue » par un point de la coque qui tape (un quart du vaisseau).
const PART_ROUE := [0.14, 0.43, 0.43]
const PART_COQUE := 0.25
## Niveau dans le cockpit (au bout d'une structure de longueur nulle) pour une énergie de choc E_REF (J).
## La matière frappée décide quelle part de l'énergie devient du son.
const E_REF := 1000.0
const CHOC_PNEU_DB := 88.0      # caoutchouc + amortisseur : ils absorbent presque tout
const CHOC_BUTEE_DB := 100.0    # acier contre acier en bout de course
const CHOC_COQUE_DB := 104.0    # panneau d'aluminium sur la roche
const DETENTE_DB := 84.0        # jambe qui se détend jusqu'à sa butée haute
const GRAVIER_DB := 74.0        # caillou contre la coque, pour E_GRAVIER
const E_GRAVIER := 0.1          # J (20 g à 3 m/s)
const CRISSEMENT_DB := 80.0     # pneu qui prend sa vitesse, à 60 m/s
## Sons continus, pour une roue qui porte un tiers du poids (ou un point de la coque qui appuie autant)
const ROULAGE_DB := 70.0        # roulement à 10 m/s (+25 dB par décade de vitesse)
const DERAPAGE_DB := 84.0       # dérapage à 5 m/s
const FREIN_DB := 72.0          # frein qui dissipe 0,8 × (poids / 3) × 10 m/s
const RACLAGE_DB := 92.0        # coque qui racle à 5 m/s
const VERIN_DB := {"train": 66.0, "ailes": 68.0, "direction": 56.0, "vertical": 64.0}
const VERIN_GRADE := {"train": 0.6, "ailes": 0.9, "direction": 0.2, "vertical": 0.6}
const F_POMPE := 400.0          # Hz : sifflement de la pompe hydraulique (et son double)
const F_CRISSEMENT := 1050.0    # Hz
const F_DISQUE := 3200.0        # Hz : le disque de frein qui chante
const ECART_CHOC := 0.08        # s : un même point ne refait pas de choc avant ça
const EN_L_AIR := 0.5           # s : roue restée en l'air assez longtemps pour s'être arrêtée de tourner

var _attenuation := PackedFloat64Array()     # dB, par point qui touche le sol
var _dernier := PackedFloat64Array()         # s : dernier choc de chaque point
var _en_l_air := PackedFloat64Array([9.0, 9.0, 9.0])   # s passées en l'air par chaque roue
var _appuyait := PackedByteArray([0, 0, 0])
var _compression := PackedFloat64Array([0.0, 0.0, 0.0])
var _frein := 0.0
var _parc := false
var _mecanismes := {}                        # nom → [valeur précédente, bouge ?]
var _rng := RandomNumberGenerator.new()
var _caillou := PackedFloat64Array([0.0, 0.0, 0.0])   # s avant le prochain caillou de chaque roue

## Sons brefs depuis la dernière lecture : [famille, niveau (dB), position (repère du modèle), n°, intensité, priorité]
var evenements: Array = []
## Sons continus : niveau (dB dans le cockpit), forme (30 tiers d'octave, somme 1), raies [[n° de raie, Hz, part]]
var niveaux := {"roulage": -INF, "verins": -INF, "derapage": -INF, "frein": -INF, "raclage": -INF}
var formes := {}
var raies := {}
var vitesse_roulage := 0.0
var _v_forme := -1.0


func _init() -> void:
	_rng.seed = 31
	formes["derapage"] = _forme(func(f: float) -> float: return _cloche(f, F_CRISSEMENT, 0.25) + 0.15 * _cloche(f, 300.0, 1.0))
	formes["frein"] = _forme(func(f: float) -> float: return _cloche(f, 1500.0, 0.6))
	formes["raclage"] = _forme(func(f: float) -> float: return _cloche(f, 900.0, 1.1))
	formes["verins"] = _forme(func(f: float) -> float: return _cloche(f, 2000.0, 0.45) + 0.4 * _cloche(f, 150.0, 0.5))
	raies["verins"] = [[0, F_POMPE, 0.3], [1, 2.0 * F_POMPE, 0.1]]
	raies["derapage"] = [[0, F_CRISSEMENT, 0.45]]
	raies["frein"] = [[1, F_DISQUE, 0.2]]
	raies["raclage"] = []
	raies["roulage"] = []


## Énergie par tiers d'octave d'une densité (relative) dens(f), normalisée à 1.
static func _forme(dens: Callable) -> PackedFloat64Array:
	var e := PackedFloat64Array()
	e.resize(30)
	var tot := 0.0
	for j in 30:
		var f := Resonances.centre(j)
		var hp := pow(f / 20.0, 4.0) / (1.0 + pow(f / 20.0, 4.0))
		e[j] = maxf(float(dens.call(f)), 0.0) * hp * f * Fluides.LARGEUR_TIERS
		tot += e[j]
	for j in 30:
		e[j] /= maxf(tot, 1e-30)
	return e


## Bosse en échelle logarithmique (largeur s en logarithme naturel), densité ∝ 1/f × bosse.
static func _cloche(f: float, fc: float, s: float) -> float:
	var l := log(f / fc)
	return exp(-l * l / (2.0 * s * s)) / f


## Roulement : le sol rugueux secoue la roue. Les bosses plus courtes que l'empreinte du pneu (12 cm) sont
## « bues » par le caoutchouc : grave jusqu'à v / 0,12 Hz, puis ça descend. Les pavés du pneu (3 cm) ajoutent
## un petit ronflement vers v / 0,03 Hz.
static func forme_roulage(v: float) -> PackedFloat64Array:
	var fp := maxf(v, 0.5) / 0.12
	var ft := maxf(v, 0.5) / 0.03
	return _forme(func(f: float) -> float: return 1.0 / f / (1.0 + pow(f / fp, 3.0)) + 0.1 * _cloche(f, ft, 0.35))


func _preparer(c: Capteurs, oreille: Vector3) -> void:
	var n := c.points_sol.size()
	_attenuation.resize(n)
	_dernier.resize(n)
	_dernier.fill(-1.0)
	for k in n:
		_attenuation[k] = ATTENUATION * (c.points_sol[k] - oreille).length()


static func _db(x: float) -> float:
	return 10.0 * log(x) / log(10.0) if x > 0.0 else -INF


## Chocs et événements (120 fois par seconde, après chaque photo).
func detecter(c: Capteurs, oreille: Vector3, dt: float) -> void:
	if _attenuation.size() != c.points_sol.size():
		_preparer(c, oreille)
	var t := c.temps
	for k in c.points_sol.size():
		var v := c.sol_choc[k]
		if v > 0.03 and t - _dernier[k] >= ECART_CHOC:
			_dernier[k] = t
			if k < 3:
				# pneu (et jambe) : la part du vaisseau que porte la roue arrive à v
				var e := 0.5 * c.poids / 9.81 * float(PART_ROUE[k]) * v * v
				evenements.append(["pneu_toucher", CHOC_PNEU_DB + _db(e / E_REF) - _attenuation[k], c.points_sol[k], k, clampf(v / 2.0, 0.0, 1.0)])
				var vc := c.sol_choc_cote[k]
				if vc > 3.0 and _en_l_air[k] >= EN_L_AIR:
					# la roue ne tournait pas : elle glisse le temps de prendre sa vitesse
					evenements.append(["pneu_crissement", CRISSEMENT_DB + 10.0 * log(vc / 60.0) / log(10.0) - _attenuation[k], c.points_sol[k], k, clampf(vc / 100.0, 0.0, 1.0)])
			else:
				var e := 0.5 * c.poids / 9.81 * PART_COQUE * v * v
				evenements.append(["coque_choc", CHOC_COQUE_DB + _db(e / E_REF) - _attenuation[k], c.points_sol[k], k, clampf(v / 3.0, 0.0, 1.0)])
	for k in 3:
		var appuie := c.sol_fn[k] > 0.0
		_en_l_air[k] = 0.0 if appuie else _en_l_air[k] + dt
		var vb := c.sol_butee[k]
		if vb > 0.05:
			var e := 0.5 * c.poids / 9.81 * float(PART_ROUE[k]) * vb * vb
			evenements.append(["train_butee", CHOC_BUTEE_DB + _db(e / E_REF) - _attenuation[k], c.points_sol[k], k, clampf(vb / 2.0, 0.0, 1.0)])
		# la roue quitte le sol : l'amortisseur se détend d'un coup jusqu'à sa butée haute (énergie du ressort)
		if _appuyait[k] and not appuie and _compression[k] > 0.02:
			var course: float = [0.15, 0.12, 0.12][k]
			evenements.append(["amortisseur_detente", DETENTE_DB + 20.0 * log(_compression[k] / 0.05) / log(10.0) - _attenuation[k], c.points_sol[k], k, clampf(_compression[k] / course, 0.0, 1.0)])
		_appuyait[k] = 1 if appuie else 0
		_compression[k] = c.compression[k] if k < c.compression.size() else 0.0
		# cailloux projetés par la roue (sol caillouteux) : au hasard, plus souvent quand on roule vite
		var vr := c.sol_roule[k]
		if appuie and vr > 2.0:
			_caillou[k] -= dt
			if _caillou[k] <= 0.0:
				_caillou[k] = -log(maxf(_rng.randf(), 1e-6)) / minf(0.1 * vr, 8.0)   # loi de Poisson : 1 caillou par seconde à 10 m/s
				var m := 0.005 * pow(10.0, _rng.randf())               # 5 à 50 g
				var vc := vr * _rng.randf_range(0.1, 0.4)              # vitesse donnée par le pneu
				var e := 0.5 * m * vc * vc
				evenements.append(["gravier", GRAVIER_DB + _db(e / E_GRAVIER) - _attenuation[k], c.points_sol[k], k,
					clampf(sqrt(e / (4.0 * E_GRAVIER)), 0.0, 1.0), true])
	# freins qui se serrent
	if c.au_sol and ((c.frein > 0.05 and _frein <= 0.05) or (c.frein_parc and not _parc)):
		evenements.append(["frein_serrage", 74.0 - _attenuation[1], c.points_sol[1], 1, 0.3 if c.frein_parc and not _parc else 0.8])
	_frein = c.frein
	_parc = c.frein_parc
	# vérins : départ, arrêt, verrouillage au bout de la course
	_verin("train", c.train_sorti, true, (c.points_sol[0] + c.points_sol[1] + c.points_sol[2]) / 3.0, oreille)
	_verin("ailes", c.ailes, true, Vector3(1.5, 0.0, 1.0), oreille)
	_verin("vertical", c.vertical, false, Vector3(0.0, 0.0, 3.0), oreille)
	_verin("direction", c.braquage, false, c.points_sol[0], oreille, true)


func _verin(nom: String, x: float, verrou: bool, pos: Vector3, oreille: Vector3, silencieux := false) -> void:
	var m: Array = _mecanismes.get(nom, [x, false, 0.0])
	var bouge := absf(x - float(m[0])) > 1e-7
	if not silencieux:
		var att := ATTENUATION * (pos - oreille).length()
		var base: float = VERIN_DB[nom] + 16.0
		if bouge and not m[1]:
			evenements.append(["verin_depart", base - att, pos, -1, VERIN_GRADE[nom]])
		elif m[1] and not bouge:
			evenements.append(["verin_arret", base + 2.0 - att, pos, -1, VERIN_GRADE[nom]])
			if verrou and (x <= 0.0 or x >= 1.0):
				evenements.append(["verrouillage", base + 6.0 - att, pos, -1, VERIN_GRADE[nom]])
	m[0] = x
	m[1] = bouge
	_mecanismes[nom] = m


## Sons continus (60 fois par seconde).
func calculer(c: Capteurs, oreille: Vector3) -> void:
	if _attenuation.size() != c.points_sol.size():
		_preparer(c, oreille)
	var tiers := c.poids / 3.0
	var e_roul := 0.0
	var v_moy := 0.0
	var e_der := 0.0
	var e_frein := 0.0
	var e_racl := 0.0
	for k in c.points_sol.size():
		var fn := c.sol_fn[k]
		if fn <= 0.0:
			continue
		var charge := fn / tiers
		var att := _attenuation[k]
		var g := c.sol_glisse[k]
		if k < 3:
			var vr := c.sol_roule[k]
			if vr > 0.3:
				var e := pow(10.0, (ROULAGE_DB + 25.0 * log(vr / 10.0) / log(10.0) - att) / 10.0) * charge
				e_roul += e
				v_moy += e * vr
				if c.sol_frein[k] > 0.02 and g < 0.3:
					var p := c.sol_frein[k] * 0.8 * fn * vr / (0.8 * tiers * 10.0)
					e_frein += pow(10.0, (FREIN_DB - att) / 10.0) * p
			if g > 0.3:
				e_der += pow(10.0, (DERAPAGE_DB - att) / 10.0) * charge * minf(g, 30.0) / 5.0
		elif g > 0.2:
			e_racl += pow(10.0, (RACLAGE_DB - att) / 10.0) * charge * minf(g, 50.0) / 5.0
	niveaux["roulage"] = _db(e_roul)
	niveaux["derapage"] = _db(e_der)
	niveaux["frein"] = _db(e_frein)
	niveaux["raclage"] = _db(e_racl)
	if e_roul > 0.0:
		vitesse_roulage = v_moy / e_roul
		if absf(vitesse_roulage - _v_forme) > 0.03 * maxf(_v_forme, 1.0) or not formes.has("roulage"):
			formes["roulage"] = forme_roulage(vitesse_roulage)
			_v_forme = vitesse_roulage
	elif not formes.has("roulage"):
		formes["roulage"] = forme_roulage(10.0)
	# vérins qui bougent
	var e_v := 0.0
	for nom in _mecanismes:
		if _mecanismes[nom][1]:
			e_v += pow(10.0, float(VERIN_DB[nom]) / 10.0)
	niveaux["verins"] = _db(e_v)


## Énergie de chaque octave (10 bandes) d'une forme en tiers d'octave.
static func octaves(forme: PackedFloat64Array) -> PackedFloat64Array:
	var o := PackedFloat64Array()
	o.resize(10)
	for j in forme.size():
		o[clampi(j / 3, 0, 9)] += forme[j]
	return o
