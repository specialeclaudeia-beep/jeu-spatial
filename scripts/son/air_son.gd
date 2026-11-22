extends RefCounted
## L'air en détail (moteur audio, phase 5) : ce que l'air fait entendre en plus du souffle de la coque.
##
## Comme pour tout le son : on n'entend que le cockpit. Chaque source fait trembler la pression sur une paroi ;
## la paroi (fluides_son.gd, loi de masse) laisse passer surtout les graves ; le cockpit (plein d'air) les rend au
## pilote. Ce fichier ne lit que la photo de la physique (capteurs.gd) : il n'écrit jamais dans le vaisseau.
##
##  1. Le train qui siffle (« son éolien », comme un fil électrique dans le vent). Derrière une jambe de train,
##     l'air se détache en tourbillons, un coup à gauche, un coup à droite, à la fréquence f = St × U / D
##     (nombre de Strouhal St ≈ 0,2 : une jambe de 17 cm à 80 m/s siffle à 94 Hz). Chaque tourbillon pousse la jambe
##     de côté : cette force qui va et vient (coefficient C'ℓ, mesuré en soufflerie, qui dépend du nombre de Reynolds
##     U D / ν) rayonne comme un petit haut-parleur à deux faces (loi de Curle : p ∝ ω F / (4π c r)). À petite
##     vitesse le sifflement est pur ; au-delà de Re ≈ 300 000 (« crise de traînée »), les tourbillons se
##     brouillent : le son devient un souffle grave, plus faible ; très vite, il redevient un peu plus net.
##     Les roues (36 cm) font un souffle plus grave. On ne les entend que train sorti.
##  2. Les trappes ouvertes qui grondent (formule de Rossiter, 1964). Au-dessus d'un puits de train ouvert, la
##     couche d'air qui glisse ondule, frappe le bord arrière, et l'onde de pression remonte vers l'avant et relance
##     l'ondulation : une boucle qui ne garde que certaines fréquences, f_m = (U / L) (m − 0,25) / (M + 1 / 0,57).
##     Un puits de 1 m à 100 m/s gronde à 37 Hz et 85 Hz. La pression qui tremble dans le puits est mesurée en
##     soufflerie : environ 0,5 % de la pression du vent à petite vitesse, jusqu'à 3 % vers Mach 0,6 et plus.
##     Le puits est dans le ventre : son tremblement passe par ses parois jusqu'au cockpit.
##  3. Le tremblement transsonique (« buffeting », Mach 0,75 à 1,3). Sur des ailes qui portent, une onde de choc
##     se forme sur le dessus et fait décoller l'air derrière elle ; le choc se met à aller et venir sur l'aile,
##     environ St = f × corde / U ≈ 0,07 (7 à 10 fois par seconde : il se sent plus qu'il ne s'entend). On entend
##     le grondement irrégulier qu'il fait dans la structure : il passe par l'emplanture de l'aile, donc il vient
##     du côté de l'aile qui tremble.
##  4. Le décrochage. Au-delà d'environ 15° d'angle d'attaque, l'air ne suit plus le dessus de l'aile : il s'en
##     détache en gros tourbillons (pression qui tremble de ~10 % de la pression du vent sur la partie décollée,
##     fréquence 0,2 × U / (corde × sin α)). Chaque bande de chaque aile est calculée avec SON air (le roulis et le
##     lacet comptent : en dérapage, une seule aile peut décrocher, et on l'entend de son côté).
##  5. L'onde de choc devant la verrière (vol au-delà du son, et surtout la rentrée). La verrière fait une bosse :
##     au-delà de Mach 1,1, un choc s'y pose, fait décoller la couche d'air collée à la coque, et ce petit décollement
##     bat sans arrêt (St ≈ 0,03 sur sa longueur, environ 4 fois l'épaisseur de la couche limite). La verrière est une
##     pente douce (choc faible) : la pression y tremble de ~0,6 % de la pression du vent, sur une bande d'une dizaine
##     de centimètres, juste sur la verrière : c'est le grondement de la rentrée. Le flux de
##     chaleur y entre par la couche limite : une coque chaude l'épaissit (méthode d'Eckert, fluides_son.gd), le
##     décollement s'allonge et gronde plus grave.
##  6. Le fondu vers le silence. Quand l'air devient si rare que les molécules arrivent une par une (nombre de
##     Knudsen), il n'y a plus de tourbillon, plus de choc, plus d'onde : tout s'efface avec la part « fluide » de
##     l'air, la même que la physique (aerodynamique.gd) et que le souffle. Les molécules isolées, elles, ne font pas
##     de bruit qu'on entende : calcul fait, à 150 km et 7,8 km/s, leurs chocs secouent un mètre carré de coque d'à
##     peine 10⁻⁸ N (bruit de grenaille), des milliards de fois trop peu (voir le test « fondu »).
##
## Les sons purs (sifflement, trappes) vont dans les « raies » de la voix air (sinusoïdes qui tremblent un peu ; un
## vrai sifflement n'est jamais parfaitement stable) ; le reste en bruit coloré (30 tiers d'octave).
## Les nombres mesurés en soufflerie (C'ℓ, Strouhal, part de la pression du vent) sont ceux des livres ; les
## dimensions viennent du modèle 3D (v27). Les distances et les parois du chemin jusqu'au pilote sont des estimations.

const Capteurs = preload("res://scripts/son/capteurs.gd")
const Fluides = preload("res://scripts/son/fluides_son.gd")
const Resonances = preload("res://scripts/son/resonances.gd")
const CoteSon = preload("res://scripts/son/cote_son.gd")

const P_REF := 2.0e-5
const COUCHES := ["sifflement", "cavites", "tremblement", "choc_verriere"]
const STROUHAL_JAMBE := 0.2
const PART_TRAPPES := 0.3          # comme modele_vaisseau.gd : les trappes s'ouvrent pendant les premiers 30 % du train
## Jambes et roues du train sorti (modèle v27, repère du vaisseau) : point, diamètre D (m), longueur L (m), raie
## (−1 = pas de son pur : une roue est trop « épaisse » pour siffler net).
const JAMBES := [
	[Vector3(0.0, -1.0, -4.4), 0.09, 0.6, 0],     # jambe avant (piston)
	[Vector3(-0.8, -1.2, 2.4), 0.17, 1.0, 1],     # jambes arrière (les deux sifflent à la même fréquence)
	[Vector3(0.8, -1.2, 2.4), 0.17, 1.0, 1],
	[Vector3(0.0, -1.6, -4.4), 0.36, 0.13, -1],   # roues
	[Vector3(-1.18, -1.6, 2.4), 0.36, 0.13, -1],
	[Vector3(1.18, -1.6, 2.4), 0.36, 0.13, -1],
]
## Puits sous les trappes (modèle v27) : centre, longueur dans le sens du vent L (m), largeur (m), trappes de quoi,
## première raie (2 modes de Rossiter chacun, −1 = pas de son pur), part du son (un puits profond et étroit, comme
## ceux des moteurs de levage, résonne moins bien en Rossiter).
const PUITS := [
	[Vector3(0.0, -0.3, -3.65), 1.74, 0.28, "train", 2, 1.0],
	[Vector3(-0.5, -0.8, 1.86), 1.39, 0.57, "train", 4, 1.0],
	[Vector3(0.5, -0.8, 1.86), 1.39, 0.57, "train", 4, 1.0],
	[Vector3(-0.27, -0.25, -3.0), 0.24, 0.20, "levage", 6, 0.5],
	[Vector3(0.27, -0.25, -3.0), 0.24, 0.20, "levage", 6, 0.5],
]
const ROSSITER_ALPHA := 0.25
const ROSSITER_KAPPA := 0.57
const MODES_ROSSITER := [[1, 0.5], [2, 0.35]]   # [m, part de la pression tonale]
const VERRIERE := Vector3(0.0, 0.7, 0.6)        # m : bord avant de la verrière (où le choc se pose)
const PART_VERRIERE := 0.05                     # part de la verrière couverte par le décollement qui bat (bande de ~10 cm)
const CP_VERRIERE := 0.006
const CP_TREMBLEMENT := 0.04
const CP_DECROCHAGE := 0.10
const DECROCHAGE_DEBUT := deg_to_rad(12.0)
const DECROCHAGE_PLEIN := deg_to_rad(20.0)
const STROUHAL_TREMBLEMENT := 0.07
const EMPLANTURE_DB := 6.0     # comme moteurs_son.gd : dB perdus au passage d'une emplanture d'aile
## La vibration d'une peau d'aile doit traverser le longeron, l'emplanture et les cadres du fuselage avant d'atteindre
## le plancher du cockpit : chaque jonction en garde une part. Ordre de grandeur des mesures de transmission « par la
## structure » dans les avions : 20 à 30 dB. Réglage à valider à l'écoute.
const STRUCTURE_AILE_DB := 25.0
## Le train et ses puits sont sous le ventre : leur son traverse la coque PUIS le plancher du cockpit (double paroi,
## avec de l'air et des équipements entre les deux) : ~15 dB de plus qu'une seule paroi. Réglage à valider à l'écoute.
const DOUBLE_PAROI_DB := 15.0
const ATTENUATION := 1.0       # dB par mètre de structure
const PAROI_OREILLE := 0.8     # m : de l'oreille du pilote à la paroi du cockpit
## Le tremblement « va et vient » : son énergie est modulée par un balancement au hasard autour de la fréquence du
## choc (écart relatif MODULATION ; moyenne de l'énergie gardée).
const MODULATION := 0.6

## Ce que le chef d'orchestre lit : niveau (dB dans le cockpit), forme (30 tiers d'octave, somme 1, partie « bruit »),
## raies [[n° de raie de la voix, Hz, part de l'énergie de la couche]], côté (cote_son.gd) du tremblement.
var niveaux := {"sifflement": -INF, "cavites": -INF, "tremblement": -INF, "choc_verriere": -INF}
var formes := {}
var raies := {"sifflement": [], "cavites": [], "tremblement": [], "choc_verriere": []}
var cote_tremblement := CoteSon.milieu()
var facteur_tremblement := 1.0      # énergie × ce facteur (moyenne 1), mis à jour à chaque image
var tete := Basis.IDENTITY
## Pour les tests et l'affichage : dernières valeurs calculées.
var f_jambe_arriere := 0.0
var f_rossiter := PackedFloat64Array([0.0, 0.0])   # puits arrière, modes 1 et 2
var f_tremblement := 0.0
var p_decolle := PackedFloat64Array()            # Pa efficaces sur chaque plaque (tremblement + décrochage)
var decroche := PackedFloat64Array()             # 0..1 : part décrochée de chaque plaque
var fluide := 0.0

var _rng := RandomNumberGenerator.new()
var _cotes_plaques := []        # tables de côté de chaque plaque (refaites quand elles bougent ou que la tête tourne)
var _points_connus := PackedVector3Array()
var _tete_connue := Basis.IDENTITY


func _init() -> void:
	_rng.seed = 505
	for nom in COUCHES:
		formes[nom] = _bosse_seule(200.0, 0.5)
	p_decolle.resize(14)
	decroche.resize(14)


static func _db(x: float) -> float:
	return 10.0 * log(x) / log(10.0) if x > 0.0 else -INF


## Forme d'une bosse en échelle logarithmique, centrée sur fc, largeur s (en octaves) : part de chaque tiers d'octave.
static func _bosse_seule(fc: float, s: float) -> PackedFloat64Array:
	var e := PackedFloat64Array()
	e.resize(30)
	var tot := 0.0
	for j in 30:
		var l := log(Resonances.centre(j) / fc) / log(2.0)
		e[j] = exp(-l * l / (2.0 * s * s))
		tot += e[j]
	for j in 30:
		e[j] /= maxf(tot, 1e-30)
	return e


## Coefficient de la force de côté d'un cylindre (valeur efficace C'ℓ), longueur de corrélation (en diamètres),
## part du son pur et largeur de la bosse (octaves), selon le nombre de Reynolds (mesures de Norberg, 2003, et
## de Schewe, 1983).
static func cylindre(re: float) -> Array:
	var lg := log(maxf(re, 1.0)) / log(10.0)
	if lg < 5.3:            # sous-critique : tourbillons réguliers
		return [0.45, 4.0, 0.8, 0.08]
	if lg < 5.7:            # crise de traînée : tout se brouille
		var t := (lg - 5.3) / 0.4
		return [lerpf(0.45, 0.1, t), lerpf(4.0, 1.5, t), lerpf(0.8, 0.2, t), lerpf(0.08, 0.35, t)]
	if lg < 6.5:            # supercritique
		return [0.1, 1.5, 0.2, 0.35]
	var t2 := clampf((lg - 6.5) / 0.5, 0.0, 1.0)   # transcritique : le sifflement revient un peu
	return [lerpf(0.1, 0.2, t2), lerpf(1.5, 2.0, t2), lerpf(0.2, 0.5, t2), lerpf(0.35, 0.2, t2)]


## Fréquences de Rossiter d'un puits de longueur l, à la vitesse u et au nombre de Mach m.
static func rossiter(mode: int, u: float, l: float, m: float) -> float:
	return u / l * (mode - ROSSITER_ALPHA) / (m + 1.0 / ROSSITER_KAPPA)


## Part du tremblement transsonique selon le nombre de Mach (0 hors de 0,75 à 1,3).
static func zone_transsonique(m: float) -> float:
	return smoothstep(0.75, 0.88, m) * (1.0 - smoothstep(1.05, 1.3, m))


## Les sons de l'air, à chaque image. oreille : tête du pilote (repère du modèle) ; transm : Fluides.transmissions()
## pour l'air du dehors (passage par la paroi, 30 tiers d'octave) ; dt : temps réel depuis l'image précédente.
func calculer(c: Capteurs, oreille: Vector3, transm: PackedFloat64Array, dt: float) -> void:
	for nom in COUCHES:
		niveaux[nom] = -INF
		raies[nom] = []
	f_jambe_arriere = 0.0
	f_rossiter[0] = 0.0
	f_rossiter[1] = 0.0
	p_decolle.fill(0.0)
	decroche.fill(0.0)
	fluide = Fluides.part_fluide(c.densite) if c.densite > 0.0 else 0.0
	_balancer(dt)
	f_tremblement = 0.0
	if c.densite <= 0.0 or fluide <= 0.0 or c.vitesse_air < 1.0 or transm.size() != 30:
		return
	_transm = transm
	var rho := c.densite
	var son := Fluides.vitesse_son(c.temperature)
	var u := c.vitesse_air
	var m := u / son
	var q := 0.5 * rho * u * u
	var nu := Fluides.viscosite(c.temperature) / rho
	# tout ce qui suit naît d'un air qui se comporte en fluide : s'efface avec lui (Knudsen)
	var cabine := pow(10.0, Fluides.GAIN_CABINE_DB / 10.0) * fluide
	_sifflement(c, oreille, u, son, q, nu, cabine)
	_cavites(c, oreille, u, m, q, cabine)
	_tremblement(c, oreille, son, rho, cabine)
	_choc_verriere(c, u, m, q, cabine)


var _transm := PackedFloat64Array()


## Rapport (au carré) pression dans le cockpit / pression qui pousse la paroi, au tiers d'octave de f.
func _t2(f: float) -> float:
	var j := clampi(roundi(3.0 * log(maxf(f, 1.0) / 31.25) / log(2.0)) + 1, 0, 29)
	return _transm[j]


## Ajoute à e30 (Pa² dans le cockpit, par tiers d'octave) une énergie p2 (Pa² sur la paroi) répartie en bosse autour
## de fc (largeur s octaves), passée par la paroi et multipliée par k (chemin, cabine).
func _repartir(e30: PackedFloat64Array, p2: float, fc: float, s: float, k: float) -> void:
	if p2 <= 0.0:
		return
	var forme := _bosse_seule(fc, s)
	for j in 30:
		e30[j] += p2 * forme[j] * _transm[j] * k


## Range une couche : niveau, forme du bruit, part de chaque son pur.
func _ranger(nom: String, e30: PackedFloat64Array, sons_purs: Array) -> void:
	var bruit := 0.0
	for e in e30:
		bruit += e
	var purs := 0.0
	for r in sons_purs:
		purs += float(r[2])
	var total := bruit + purs
	if total <= 0.0:
		return
	niveaux[nom] = _db(total / (P_REF * P_REF))
	if bruit > 0.0:
		var forme := PackedFloat64Array()
		forme.resize(30)
		for j in 30:
			forme[j] = e30[j] / bruit
		formes[nom] = forme
	var liste := []
	for r in sons_purs:
		liste.append([int(r[0]), float(r[1]), float(r[2]) / total])
	raies[nom] = liste


## Moyenne de fréquences en échelle logarithmique, pesée par l'énergie : [Σ e ln f, Σ e] → f.
static func _f_moyenne(acc: Vector2) -> float:
	return exp(acc.x / acc.y) if acc.y > 0.0 else 100.0


## 1. Jambes et roues du train sorti.
func _sifflement(c: Capteurs, oreille: Vector3, u: float, son: float, q: float, nu: float, cabine: float) -> void:
	var jambe := clampf((c.train_sorti - PART_TRAPPES) / (1.0 - PART_TRAPPES), 0.0, 1.0)
	if jambe <= 0.0:
		return
	cabine *= pow(10.0, -DOUBLE_PAROI_DB / 10.0)
	var purs := {}   # n° de raie → [n°, Hz, Pa² dans le cockpit]
	# le bruit des jambes et celui des roues : chacun une bosse (fréquence moyenne, énergie sur la paroi)
	var acc_j := Vector2.ZERO
	var acc_r := Vector2.ZERO
	var larg_j := 0.0
	for jb in JAMBES:
		var d: float = jb[1]
		var l: float = float(jb[2]) * jambe
		var cy := cylindre(u * d / nu)
		var cl: float = cy[0]
		var lc: float = minf(float(cy[1]) * d, l)
		var st := STROUHAL_JAMBE if float(cy[2]) > 0.3 else 0.25
		var f := st * u / d
		# force de côté qui va et vient : chaque tronçon long de lc tire à sa façon (énergies qui s'ajoutent)
		var f2 := pow(cl * q * d, 2.0) * lc * l
		# Curle : dipôle compact, moyenne sur les directions (1/3), pression doublée contre la coque (× 4)
		var r := maxf(((jb[0] as Vector3) - oreille).length() - PAROI_OREILLE, 0.5)
		var w := TAU * f
		var p2 := w * w * f2 / 3.0 / pow(4.0 * PI * son * r, 2.0) * 4.0
		var k := int(jb[3])
		var pur := float(cy[2]) if k >= 0 else 0.0
		if k >= 0:
			acc_j += Vector2(p2 * (1.0 - pur) * log(f), p2 * (1.0 - pur))
			larg_j = float(cy[3])
			var e := p2 * pur * _t2(f) * cabine
			if purs.has(k):
				purs[k][2] += e
			else:
				purs[k] = [k, f, e]
			if k == 1:
				f_jambe_arriere = f
		else:
			acc_r += Vector2(p2 * log(f), p2)
	var e30 := PackedFloat64Array()
	e30.resize(30)
	_repartir(e30, acc_j.y, _f_moyenne(acc_j), larg_j + 0.1, cabine)
	_repartir(e30, acc_r.y, _f_moyenne(acc_r), 0.6, cabine)
	_ranger("sifflement", e30, purs.values())


## 2. Puits de train (et des moteurs de levage) ouverts : Rossiter.
func _cavites(c: Capteurs, oreille: Vector3, u: float, m: float, q: float, cabine: float) -> void:
	var porte_train := clampf(c.train_sorti / PART_TRAPPES, 0.0, 1.0)
	var porte_levage := clampf(c.sortie_levage / PART_TRAPPES, 0.0, 1.0)
	if porte_train <= 0.0 and porte_levage <= 0.0:
		return
	cabine *= pow(10.0, -DOUBLE_PAROI_DB / 10.0)
	var purs := {}
	# pression qui tremble dans le puits, en part de la pression du vent (mesures en soufflerie)
	var cp_ton := 0.004 + 0.026 * smoothstep(0.15, 0.6, m)
	var cp_bruit := 0.012
	var acc := Vector2.ZERO
	for p in PUITS:
		var ouvert := porte_train if p[3] == "train" else porte_levage
		if ouvert <= 0.0:
			continue
		var l: float = p[1]
		var s := l * float(p[2]) * ouvert   # ouverture vue par l'air
		var r := maxf(((p[0] as Vector3) - oreille).length(), 0.5)
		var k := minf(1.0, s / (TAU * r * r)) * cabine * float(p[5])   # du puits jusqu'au pilote, par ses parois
		var e_b := pow(cp_bruit * q, 2.0) * k
		acc += Vector2(e_b * log(rossiter(2, u, l, m)), e_b)
		var n := int(p[4])
		for md in MODES_ROSSITER:
			var f := rossiter(int(md[0]), u, l, m)
			var e: float = pow(cp_ton * q, 2.0) * float(md[1]) * _t2(f) * k
			var i_raie := n + int(md[0]) - 1
			if purs.has(i_raie):
				purs[i_raie][2] += e
			else:
				purs[i_raie] = [i_raie, f, e]
			if n == 4:
				f_rossiter[int(md[0]) - 1] = f
	var e30 := PackedFloat64Array()
	e30.resize(30)
	_repartir(e30, acc.y, _f_moyenne(acc), 1.0, 1.0)
	_ranger("cavites", e30, purs.values())


## 3 et 4. Tremblement transsonique et décrochage, plaque par plaque (passe par l'emplanture : structure).
func _tremblement(c: Capteurs, oreille: Vector3, son: float, rho: float, cabine: float) -> void:
	var n := c.plaques_v.size()
	if n == 0:
		return
	var acc := CoteSon.vide()
	var acc_t := Vector2.ZERO   # tremblement : [Σ e ln f, Σ e] (énergie sur la paroi × chemin)
	var acc_d := Vector2.ZERO   # décrochage
	var f_pond := 0.0
	var p_pond := 0.0
	var cotes_prets := false
	for i in n:
		var v := c.plaques_v[i]
		if v < 1.0:
			continue
		var mi := v / son
		var qi := 0.5 * rho * v * v
		var alpha := c.plaques_alpha[i]
		var corde := maxf(c.plaques_corde[i], 0.1)
		# tremblement : choc qui va et vient sur une aile qui porte
		var porte := 0.2 + 0.8 * smoothstep(0.02, 0.1, alpha)
		var cp_t := CP_TREMBLEMENT * zone_transsonique(mi) * porte
		# décrochage : l'air décolle du dessus (en dessous du son seulement ; au-delà, c'est le choc qui décolle)
		var dec := smoothstep(DECROCHAGE_DEBUT, DECROCHAGE_PLEIN, alpha) * (1.0 - smoothstep(0.85, 1.1, mi))
		decroche[i] = dec
		var p2_t := pow(cp_t * qi, 2.0)
		var p2_d := pow(CP_DECROCHAGE * dec * qi, 2.0)
		if p2_t + p2_d <= 0.0:
			continue
		if not cotes_prets:
			_preparer_cotes(c, oreille)
			cotes_prets = true
		p_decolle[i] = sqrt(p2_t + p2_d)
		var r := ((c.plaques_point[i] as Vector3) - oreille).length()
		# chemin : la plaque rayonne dans l'aile, puis l'emplanture et la structure jusqu'au pilote
		var chemin := pow(10.0, -(EMPLANTURE_DB + STRUCTURE_AILE_DB + ATTENUATION * r) / 10.0)
		var k := minf(1.0, c.plaques_surface[i] / (TAU * r * r)) * chemin * cabine
		if p2_t > 0.0:
			var ft := STROUHAL_TREMBLEMENT * v / corde
			# le choc bat à quelques Hz (on le sent) ; ce qu'on entend, c'est sa « queue » vers les aigus
			acc_t += Vector2(p2_t * k * log(maxf(ft * 4.0, 30.0)), p2_t * k)
			f_pond += ft * p2_t
			p_pond += p2_t
		if p2_d > 0.0:
			var fd := 0.2 * v / (corde * maxf(sin(alpha), 0.2))
			acc_d += Vector2(p2_d * k * log(maxf(fd * 3.0, 30.0)), p2_d * k)
		# côté : pesé par l'énergie de la plaque (la paroi filtre de la même façon toutes les plaques)
		CoteSon.cumuler(acc, _cotes_plaques[i], (p2_t + p2_d) * k)
	if acc_t.y + acc_d.y <= 0.0:
		return
	f_tremblement = f_pond / p_pond if p_pond > 0.0 else 0.0
	cote_tremblement = CoteSon.finir(acc, acc_t.y + acc_d.y)
	var e30 := PackedFloat64Array()
	e30.resize(30)
	_repartir(e30, acc_t.y, _f_moyenne(acc_t), 1.4, 1.0)
	_repartir(e30, acc_d.y, _f_moyenne(acc_d), 1.3, 1.0)
	_ranger("tremblement", e30, [])


func _preparer_cotes(c: Capteurs, oreille: Vector3) -> void:
	var change := _cotes_plaques.size() != c.plaques_point.size() \
		or Quaternion(_tete_connue.inverse() * tete).get_angle() > deg_to_rad(2.0)
	if not change:
		for i in c.plaques_point.size():
			if (c.plaques_point[i] - _points_connus[i]).length_squared() > 0.01:
				change = true
				break
	if not change:
		return
	_cotes_plaques.clear()
	for p in c.plaques_point:
		_cotes_plaques.append(CoteSon.table(p, oreille, tete, CoteSon.PROCHE_STRUCTURE_DB))
	_points_connus = c.plaques_point.duplicate()
	_tete_connue = tete


## 5. L'onde de choc qui bat devant la verrière (au-delà de Mach 1,1 ; la rentrée).
func _choc_verriere(c: Capteurs, u: float, m: float, q: float, cabine: float) -> void:
	var part := smoothstep(1.1, 1.6, m)
	if part <= 0.0:
		return
	var cl := Fluides.couche_limite(c.densite, c.temperature, u, m, c.temperature_coque)
	var l_dec := 4.0 * float(cl[1])                  # longueur du décollement : ~4 épaisseurs de couche limite
	longueur_decollement = l_dec
	var fc := 0.03 * u / maxf(l_dec, 0.02)
	var p2 := pow(CP_VERRIERE * part * q, 2.0) * PART_VERRIERE
	var e30 := PackedFloat64Array()
	e30.resize(30)
	_repartir(e30, p2, fc, 1.2, cabine)
	_ranger("choc_verriere", e30, [])


var longueur_decollement := 0.0


## Le choc qui va et vient : un balancement au hasard (processus d'Ornstein-Uhlenbeck, temps de mémoire 1 / (π f),
## f = fréquence du choc), de valeur efficace 1 ; l'énergie du tremblement est multipliée par (1 + MODULATION x)²,
## divisée par sa moyenne (le niveau moyen ne change pas).
func _balancer(dt: float) -> void:
	if dt <= 0.0:
		return
	var f := clampf(f_tremblement if f_tremblement > 0.0 else 8.0, 2.0, 14.0)
	var a := exp(-dt * PI * f)
	_x = a * _x + sqrt(1.0 - a * a) * _rng.randfn(0.0, 1.0)
	var g := maxf(1.0 + MODULATION * clampf(_x, -3.0, 3.0), 0.0)
	facteur_tremblement = g * g / (1.0 + MODULATION * MODULATION)


var _x := 0.0
