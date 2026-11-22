extends RefCounted
## La poussière et le gaz de l'espace qui tapent le vaisseau (moteur audio, phase 4, idée de Gwenaël du 21/11).
##
## On n'entend jamais l'espace (il n'y a pas d'air dehors), mais ce qui TOUCHE le vaisseau s'entend : chaque grain
## de poussière, chaque atome de gaz qui frappe la verrière ou la coque la fait vibrer, et le cockpit, lui, est plein
## d'air. C'est réel : les sondes spatiales enregistrent ces chocs sur leur coque.
##
## Comme pour le sol (idée de Gwenaël) : chaque particule a une MASSE et une VITESSE ; son énergie de choc donne le
## niveau, la paroi frappée donne le timbre (verre : tintement aigu ; coque : « tic » plus sourd, venu de plus loin).
## L'énergie est celle d'Einstein : E = (γ − 1) m c² (= ½ m v² aux vitesses ordinaires ; à 0,9 c, 3 fois plus).
##
## Combien de particules frappent par seconde : densité × vitesse × surface vue dans le sens du vol (le « vent »
## de face), plus les grains qui arrivent de partout à leur propre vitesse (20 km/s). Les densités :
##  - poussière près d'une étoile (nuage zodiacal) : loi mesurée de Grün (1985) à 1 UA, de 10⁻²¹ kg (fumée) à
##    10⁻⁶ kg (grain de sable), qui baisse comme (distance / 1 UA)^−1,3 ;
##  - poussière entre les étoiles : loi de Mathis-Rumpl-Nordsieck (grains de 5 à 250 nm, 1 % de la masse du gaz) ;
##    dans l'héliosphère (à moins de 120 UA d'une étoile), le vent de l'étoile chasse les grains les plus fins ;
##  - gaz : vent de l'étoile (5 millions de particules par m³ à 1 UA, en 1 / distance²), au moins 200 000 par m³
##    (le nuage interstellaire local) ;
##  - près des planètes et des lunes : un nuage de poussière INVENTÉ (débris, poussière soulevée), plus dense
##    près de la surface, réglé pour qu'on entende un « tic » de temps en temps en orbite basse (la vraie densité
##    donnerait un tic audible tous les deux mois). Gwenaël a validé qu'on invente la densité selon l'endroit.
##
## Ce qu'on entend : à vitesse d'orbite, de rares « tic » sur la verrière ; plus on va vite, plus ils sont forts et
## nombreux ; près de la vitesse de la lumière, des centaines par seconde se fondent en un souffle continu (comme la
## pluie : chaque goutte est un choc, leur somme un bruit — théorème de Campbell : puissance = débit × énergie).
## Les grains assez rares et assez forts sont joués un par un (30 par seconde au plus), les autres vont dans la couche
## continue « poussiere ». Dans l'air, les grains brûlent avant d'arriver (étoiles filantes) et l'air couvre tout :
## la couche s'efface quand l'air devient dense.
## Rien ici n'écrit dans la physique.

const Capteurs = preload("res://scripts/son/capteurs.gd")
const SolSon = preload("res://scripts/son/sol_son.gd")
const Pieces = preload("res://scripts/son/pieces_sonores.gd")

const C := 299792458.0
const UA := 1.495978707e11
const M_GAZ := 1.3 * 1.67262192e-27   # kg : particule moyenne du gaz (hydrogène, un peu d'hélium)
const V_GRAINS := 2.0e4               # m/s : les grains vont dans tous les sens, à cette vitesse
const V_VENT := 4.0e5                 # m/s : vent de l'étoile
const V_GAZ_ISM := 2.6e4              # m/s : gaz entre les étoiles
const HELIOSPHERE := 120.0 * UA
const N_VENT := 5.0e6                 # particules par m³ à 1 UA
const N_ISM := 2.0e5                  # particules par m³ entre les étoiles
const PENTE_ZODIACALE := -1.3
const R_MIN := 0.05 * UA              # au plus près de l'étoile (plus près, la poussière s'évapore)
const RHO_GRAIN := 3000.0             # kg/m³ (silicates, carbone)
const A_MIN := 5.0e-9                 # m : grains entre les étoiles
const A_MAX := 2.5e-7
const FILTRE_HELIO := 1.26e-17        # kg (rayon 0,1 µm) : plus fins, chassés par le vent de l'étoile
const PART_GRAIN := 1.0e-3             # part de l'énergie d'un grain qui fait vibrer la paroi (rendement « sismique » des chocs à très grande vitesse, 10⁻⁴ à 10⁻² en laboratoire ; le reste : vapeur, chaleur, éclair)
const PART_GAZ := 1.0e-4              # un atome dépose son énergie sur quelques nanomètres : presque tout en chaleur
const NUAGE := 3.7e5                  # nuage inventé près des planètes : fois la poussière zodiacale à 1 UA…
const H_NUAGE := 1.0e6                # m : … qui diminue de moitié tous les 700 km d'altitude
const RHO_AIR := 1.0e-7               # kg/m³ : dans un air plus dense, les grains brûlent avant d'arriver
const DEBIT_MAX := 30.0               # grains joués un par un, par seconde au plus
const L_SEUL := 40.0                  # dB : un grain plus faible ne s'entend pas seul (il rejoint le souffle)
const FENETRE := 0.1
## Bornes des tranches de masse (kg), une par facteur 10.
const M_MIN_EXP := -21
const M_MAX_EXP := -6

## Parois : [normale, aire (m²), centre (repère du modèle), famille du son, dB pour 1 J, dB perdus en plus (emplanture)]
## La verrière : son verre est tout près de l'oreille. La coque et les ailes : le son vient par la structure.
const PAROIS := [
	[Vector3(0.0, 0.55, -0.835), 0.5, Vector3(0.0, 0.78, -0.75), "poussiere_verre", 72.0, 0.0],
	[Vector3(0.0, 1.0, 0.0), 0.7, Vector3(0.0, 0.95, -0.2), "poussiere_verre", 72.0, 0.0],
	[Vector3(-0.85, 0.53, 0.0), 0.2, Vector3(-0.45, 0.8, -0.3), "poussiere_verre", 72.0, 0.0],
	[Vector3(0.85, 0.53, 0.0), 0.2, Vector3(0.45, 0.8, -0.3), "poussiere_verre", 72.0, 0.0],
	[Vector3(0.0, 0.0, -1.0), 0.8, Vector3(0.0, 0.0, -5.5), "poussiere_coque", 74.0, 0.0],
	[Vector3(0.0, 1.0, 0.0), 2.5, Vector3(0.0, 0.4, -3.0), "poussiere_coque", 74.0, 0.0],
	[Vector3(0.0, 1.0, 0.0), 3.0, Vector3(0.0, 0.6, 2.5), "poussiere_coque", 74.0, 0.0],
	[Vector3(0.0, -1.0, 0.0), 5.0, Vector3(0.0, -0.8, 0.0), "poussiere_coque", 74.0, 0.0],
	[Vector3(-1.0, 0.0, 0.0), 4.0, Vector3(-0.9, 0.0, 0.0), "poussiere_coque", 74.0, 0.0],
	[Vector3(1.0, 0.0, 0.0), 4.0, Vector3(0.9, 0.0, 0.0), "poussiere_coque", 74.0, 0.0],
	[Vector3(0.0, 0.0, 1.0), 1.5, Vector3(0.0, 0.0, 4.6), "poussiere_coque", 74.0, 0.0],
	[Vector3(0.0, 1.0, 0.0), 5.0, Vector3(-3.0, 1.2, 1.5), "poussiere_coque", 70.0, 6.0],
	[Vector3(0.0, 1.0, 0.0), 5.0, Vector3(3.0, 1.2, 1.5), "poussiere_coque", 70.0, 6.0],
	[Vector3(0.0, -1.0, 0.0), 5.0, Vector3(-3.0, -1.2, 1.5), "poussiere_coque", 70.0, 6.0],
	[Vector3(0.0, -1.0, 0.0), 5.0, Vector3(3.0, -1.2, 1.5), "poussiere_coque", 70.0, 6.0],
	[Vector3(0.0, 0.0, -1.0), 0.5, Vector3(-3.0, 0.0, 0.8), "poussiere_coque", 70.0, 6.0],
	[Vector3(0.0, 0.0, -1.0), 0.5, Vector3(3.0, 0.0, 0.8), "poussiere_coque", 70.0, 6.0],
]

var n_zodiacal := PackedFloat64Array()   # grains par m³ dans chaque tranche, à 1 UA
var n_ism := PackedFloat64Array()        # grains par m³ dans chaque tranche, entre les étoiles
var m_bas := PackedFloat64Array()
var m_moyen := PackedFloat64Array()      # masse moyenne d'un grain de la tranche (tirage uniforme en log)
var _chemins := PackedFloat64Array()     # dB : de chaque paroi à l'oreille
var _distances := PackedFloat64Array()
var _oreille := Vector3(INF, INF, INF)
var _s_grains := PackedFloat64Array()    # m³/s : volume balayé par chaque paroi (grains)
var _s_gaz := PackedFloat64Array()
var _p_paroi := PackedFloat64Array()     # W : puissance sonore continue reçue par chaque paroi
var _rng := RandomNumberGenerator.new()
var _forme_verre := PackedFloat64Array()
var _forme_coque := PackedFloat64Array()
var _forme_gaz := PackedFloat64Array()
var _n := PackedFloat64Array()           # densités de l'endroit (refaites quand on a bougé de 0,1 %)
var _lieu := Vector3(-1.0, -1.0, -1.0)

## Sons brefs depuis la dernière lecture : [famille, niveau (dB), position, −1, intensité, priorité, trajet (m)]
var evenements: Array = []
## Souffle continu des particules : niveau (dB dans le cockpit) et forme (30 tiers d'octave, somme 1).
var niveau := -INF
var forme := PackedFloat64Array()
## Pour les tests et l'affichage : par seconde de jeu réel.
var debit_grains := 0.0                  # grains qui touchent le vaisseau
var debit_gaz := 0.0                     # particules de gaz
var puissance_gaz := 0.0                 # W : énergie apportée par le gaz
var densite_grains := 0.0                # grains par m³ (toutes tailles)
var densite_gaz := 0.0
var gamma_moins_un := 0.0
var grains_joues := 0                    # depuis le début


func _init() -> void:
	_rng.seed = 91
	for e in range(M_MIN_EXP, M_MAX_EXP):
		var m1 := pow(10.0, e)
		var m2 := pow(10.0, e + 1)
		m_bas.append(m1)
		m_moyen.append((m2 - m1) / log(10.0))
		n_zodiacal.append(4.0 * (flux_grun(m1) - flux_grun(m2)) / V_GRAINS)
		n_ism.append(_mrn(m1, m2))
	for a in [_chemins, _distances, _s_grains, _s_gaz, _p_paroi]:
		a.resize(PAROIS.size())
		a.fill(0.0)
	_forme_verre = SolSon._forme(func(f: float) -> float: return SolSon._cloche(f, 4500.0, 0.8))
	_forme_coque = SolSon._forme(func(f: float) -> float: return SolSon._cloche(f, 2200.0, 0.9))
	_forme_gaz = SolSon._forme(func(f: float) -> float: return SolSon._cloche(f, 3500.0, 1.4))
	forme = _forme_verre


## Grün et al. (1985) : grains de masse > m (kg) qui frappent 1 m² (une face) par seconde, à 1 UA.
static func flux_grun(m: float) -> float:
	var g := m * 1000.0
	return pow(2.2e3 * pow(g, 0.306) + 15.0, -4.38) + 1.3e-9 * pow(g + 1e11 * g * g + 1e27 * g * g * g * g, -0.36) \
		+ 1.3e-16 * pow(g + 1e6 * g * g, -0.85)


## Mathis-Rumpl-Nordsieck : grains entre les étoiles de masse m1 à m2 (kg), par m³ (n(a) ∝ a^−3,5).
static func _mrn(m1: float, m2: float) -> float:
	var rho_d := 0.01 * N_ISM * 1.4 * 1.67262192e-27
	var k := rho_d / (4.0 / 3.0 * PI * RHO_GRAIN * 2.0 * (sqrt(A_MAX) - sqrt(A_MIN)))
	var a1 := maxf(pow(m1 / (4.0 / 3.0 * PI * RHO_GRAIN), 1.0 / 3.0), A_MIN)
	var a2 := minf(pow(m2 / (4.0 / 3.0 * PI * RHO_GRAIN), 1.0 / 3.0), A_MAX)
	return k / 2.5 * (pow(a1, -2.5) - pow(a2, -2.5)) if a2 > a1 else 0.0


static func _db(x: float) -> float:
	return 10.0 * log(x) / log(10.0) if x > 0.0 else -INF


func _chemin(oreille: Vector3) -> void:
	_oreille = oreille
	for f in PAROIS.size():
		var d := ((PAROIS[f][2] as Vector3) - oreille).length()
		_distances[f] = d
		_chemins[f] = Pieces.ATTENUATION * d + float(PAROIS[f][5])


## Densité de grains de chaque tranche à cet endroit (grains par m³).
func densites(c: Capteurs) -> PackedFloat64Array:
	var r := maxf(c.dist_etoile, R_MIN)
	var dans_helio := r < HELIOSPHERE
	var zod := pow(r / UA, PENTE_ZODIACALE) if dans_helio else 0.0
	if c.dist_astre < INF and c.rayon_astre > 0.0:
		zod += NUAGE * exp(-maxf(c.dist_astre - c.rayon_astre, 0.0) / H_NUAGE)
	var n := PackedFloat64Array()
	n.resize(m_bas.size())
	for k in m_bas.size():
		var ism := n_ism[k] if not dans_helio or m_bas[k] >= FILTRE_HELIO else 0.0
		n[k] = n_zodiacal[k] * zod + ism
	return n


## Après chaque photo (120 fois par seconde) : quels grains frappent, et ceux qu'on joue un par un.
func detecter(c: Capteurs, oreille: Vector3, dt: float) -> void:
	if oreille != _oreille:
		_chemin(oreille)
	_p_paroi.fill(0.0)
	debit_grains = 0.0
	debit_gaz = 0.0
	puissance_gaz = 0.0
	var air := exp(-c.densite / RHO_AIR) if c.densite > 0.0 else 1.0
	if dt <= 0.0 or air < 1e-4:
		return
	# temps de l'univers par seconde réelle (temps accéléré : plus de grains par seconde entendue)
	var k_t := c.temps_physique / dt
	var v := c.vitesse
	var b2 := (v / C) * (v / C)
	var g := c.gamma
	gamma_moins_un = b2 * g * g / (g + 1.0)   # γ − 1 sans perte de précision aux petites vitesses
	var r := maxf(c.dist_etoile, R_MIN)
	var dans_helio := r < HELIOSPHERE
	var v_gaz := V_VENT if dans_helio else V_GAZ_ISM
	densite_gaz = maxf(N_VENT * (UA / r) * (UA / r), N_ISM) if dans_helio else N_ISM
	# volume balayé par seconde par chaque paroi : le vent de face, plus ce qui arrive de partout (¼ de la surface)
	var s_grains := 0.0
	var s_gaz := 0.0
	for f in PAROIS.size():
		var p: Array = PAROIS[f]
		var face := maxf((p[0] as Vector3).dot(c.direction), 0.0) * float(p[1])   # paroi tournée vers l'avant du vol
		_s_grains[f] = v * face + V_GRAINS * float(p[1]) * 0.25
		_s_gaz[f] = v * face + v_gaz * float(p[1]) * 0.25
		s_grains += _s_grains[f]
		s_gaz += _s_gaz[f]
	var e_par_kg := gamma_moins_un * C * C   # J par kg apportés par le vent de face…
	# … plus la vitesse propre des particules (½ v²)
	var e_grain := e_par_kg + 0.5 * V_GRAINS * V_GRAINS
	var e_gaz := M_GAZ * (e_par_kg + 0.5 * v_gaz * v_gaz)
	# le gaz : des milliards d'atomes, chacun bien trop faible : tout va dans le souffle
	debit_gaz = densite_gaz * s_gaz * k_t * air
	puissance_gaz = debit_gaz * e_gaz
	for f in PAROIS.size():
		_p_paroi[f] += densite_gaz * _s_gaz[f] * k_t * air * e_gaz * PART_GAZ
	# les grains, du plus lourd au plus léger : les forts et rares un par un, les autres dans le souffle
	var lieu := Vector3(c.dist_etoile, c.dist_astre - c.rayon_astre, c.rayon_astre)
	if _n.is_empty() or _bouge(lieu.x, _lieu.x, 1e-3 * absf(lieu.x)) or _bouge(lieu.y, _lieu.y, maxf(1e-3 * absf(lieu.y), 100.0)) \
			or lieu.z != _lieu.z:
		_n = densites(c)
		_lieu = lieu
	var n := _n
	densite_grains = 0.0
	var joues := 0.0
	for k in range(m_bas.size() - 1, -1, -1):
		densite_grains += n[k]
		var debit := n[k] * s_grains * k_t * air
		if debit <= 0.0:
			continue
		debit_grains += debit
		var e_son := PART_GRAIN * m_moyen[k] * e_grain
		var l_verre: float = 72.0 + _db(e_son) - _chemins[0]
		if l_verre >= L_SEUL and joues + debit <= DEBIT_MAX:
			joues += debit
			_tirer(k, debit * dt, e_grain, s_grains)
		else:
			for f in PAROIS.size():
				_p_paroi[f] += debit * _s_grains[f] / s_grains * e_son


## Les grains de la tranche k qui frappent pendant ce pas (loi de Poisson : attendu = debit × dt).
func _tirer(k: int, attendu: float, e_grain: float, s_grains: float) -> void:
	var nb := int(floor(attendu))
	if _rng.randf() < attendu - nb:
		nb += 1
	for j in mini(nb, 8):
		# quelle paroi (au prorata de ce qu'elle balaie), quelle masse (au hasard dans la tranche)
		var x := _rng.randf() * s_grains
		var f := 0
		while f < PAROIS.size() - 1 and x > _s_grains[f]:
			x -= _s_grains[f]
			f += 1
		var p: Array = PAROIS[f]
		var m := m_bas[k] * pow(10.0, _rng.randf())
		var e_son := PART_GRAIN * m * e_grain
		var l: float = float(p[4]) + _db(e_son) - _chemins[f]
		var pos: Vector3 = (p[2] as Vector3) + Vector3(_rng.randf_range(-0.2, 0.2), _rng.randf_range(-0.1, 0.1), _rng.randf_range(-0.2, 0.2))
		# plus le grain arrive vite, plus le choc est bref : plus aigu
		var u := sqrt(2.0 * e_grain)
		var intensite := clampf(0.3 + 0.18 * log(u / 1.0e4) / log(10.0), 0.2, 1.0)
		evenements.append([p[3], l, pos, -1, intensite, 2 if f < 4 else 1, _distances[f]])
		grains_joues += 1


## Souffle continu (60 fois par seconde) : la somme de tout ce qui n'est pas joué un par un.
func calculer(_c: Capteurs) -> void:
	var total := 0.0
	var e_verre := 0.0
	var e_coque := 0.0
	for f in PAROIS.size():
		if _p_paroi[f] <= 0.0:
			continue
		var l: float = float(PAROIS[f][4]) + _db(_p_paroi[f] * FENETRE) - _chemins[f]
		var e := pow(10.0, l / 10.0)
		total += e
		if f < 4:
			e_verre += e
		else:
			e_coque += e
	niveau = _db(total)
	if total <= 0.0:
		return
	# couleur : grains fins sur le verre (aigu), sur la coque (plus sourd), et l'atome qui « siffle » (large)
	var part_gaz := clampf(puissance_gaz * PART_GAZ / maxf(_somme(_p_paroi), 1e-30), 0.0, 1.0)
	var f30 := PackedFloat64Array()
	f30.resize(30)
	for j in 30:
		var grains := (_forme_verre[j] * e_verre + _forme_coque[j] * e_coque) / total
		f30[j] = grains * (1.0 - part_gaz) + _forme_gaz[j] * part_gaz
	forme = f30


static func _bouge(a: float, b: float, ecart: float) -> bool:
	if is_inf(a) or is_inf(b):
		return a != b
	return absf(a - b) > ecart


static func _somme(a: PackedFloat64Array) -> float:
	var s := 0.0
	for x in a:
		s += x
	return s
