extends RefCounted
## Ce que la tension des pièces fait entendre (moteur audio, phase 4) : craquements, relâchements, tics de la
## coque qui chauffe ou refroidit, et « chant » de la structure quand les charges bougent.
##
## Tout part de charges.gd (la charge exacte de chaque attache, et son taux : 0 à 1, 1 = rupture). Comme pour les
## chocs du sol (idée de Gwenaël), le NIVEAU vient d'une énergie : l'énergie élastique que la pièce garde
## (½ k x², elle grandit comme taux²) ; la MATIÈRE donne le timbre (chocs.gd) ; le CHEMIN jusqu'au pilote enlève
## 1 dB par mètre de structure (et 6 dB au passage d'une emplanture d'aile) et assourdit les aigus.
##
##  - Craquements (émission acoustique, mesurée sur les vraies structures) : sous charge, la matière lâche de
##    minuscules ruptures (fibres, résine, rivets qui glissent d'un micron). Leur nombre grimpe très vite avec la
##    charge : N(taux) = 200 × taux⁶ du début à la rupture (0,8 à 40 % ; 4,6 à 53 % ; 18 à 67 %), tirés au hasard
##    (loi de Poisson). Effet Kaiser (observé en vrai) : une pièce ne recraque pas tant qu'on ne dépasse pas la plus
##    forte charge déjà vue ; le composite très chargé (effet Felicity) recommence un peu avant (jusqu'à 92 % de
##    cette charge, au-delà de 40 % de la rupture). Chaque pièce a été « éprouvée » à sa charge limite (0,67 de la
##    rupture) avant son premier vol, comme les vraies : un vaisseau en bon état ne craque donc que quand on le
##    pousse au-delà (virage trop serré, atterrissage dur, air trop dense à trop grande vitesse, poussée x2…).
##    Après une surcharge, la mémoire redescend vers l'épreuve en quelques minutes.
##    La force de chaque craquement suit la loi de Gutenberg-Richter (comme les séismes) : beaucoup de petits,
##    quelques gros (énergie de 1 à 100 fois la plus petite, 10 fois moins souvent par facteur 10).
##  - Relâchement : la charge chute de plus de 30 % en moins de 50 ms (roue qui décolle, rebond) : la pièce
##    « revient » et sonne avec ses grands modes. Énergie : une part de l'énergie élastique libérée.
##  - Tics thermiques : la coque qui chauffe ou refroidit se dilate par petits coups (une tôle qui « saute » d'un
##    appui à l'autre) : un tic tous les 1,5 degré gagné ou perdu, au hasard (après une rentrée : tic… tic…).
##  - Chant de la structure : une charge fixe ne fait aucun bruit ; quand elle bouge, les assemblages frottent et
##    les panneaux vibrent. Puissance = une part de la variation de l'énergie élastique (U × d(taux²)/dt).
## Les nombres « 200 », « 10⁻⁴ » sont des réglages à l'oreille (à valider à l'écoute sur le PC) ; les lois
## (énergie, Kaiser, Gutenberg-Richter, chemin) sont celles de la physique.

const Capteurs = preload("res://scripts/son/capteurs.gd")
const Charges = preload("res://scripts/son/charges.gd")
const Pieces = preload("res://scripts/son/pieces_sonores.gd")
const SolSon = preload("res://scripts/son/sol_son.gd")
const Fluides = preload("res://scripts/son/fluides_son.gd")
const Resonances = preload("res://scripts/son/resonances.gd")
const CoteSon = preload("res://scripts/son/cote_son.gd")

const N_RUPTURE := 200.0          # craquements d'une pièce chargée de 0 jusqu'à la rupture
const EXPOSANT := 6.0
const TAUX_MAX := 1.2             # au-delà (le jeu ne casse rien), on ne compte plus
const OUBLI := 300.0             # s : la mémoire d'une surcharge s'efface en quelques minutes…
const EPREUVE := 1.0 / 1.5        # … jusqu'à celle de l'épreuve (chaque pièce a été chargée à sa limite avant le 1er vol)
const PART_CRAQUEMENT := 1.0e-4   # part de l'énergie élastique gardée qui part dans un petit craquement
const GROS_MAX := 100.0           # le plus gros craquement : 100 fois l'énergie du plus petit
const ECART_CRAQUEMENTS := 0.03   # s : une pièce ne craque pas plus de ~30 fois par seconde
const CRAQUEMENTS_MAX := 30.0     # craquements par seconde pour tout le vaisseau (au-delà : cachés de toute façon)
const ATTENTE_MAX := 2.0         # craquements en attente au plus, par pièce
const CHUTE := 0.3                # relâchement : la charge perd plus de 30 %…
const FENETRE_CHUTE := 0.05       # … en moins de 50 ms…
const CHUTE_MIN := 0.06           # … et au moins 0,06 de taux (pas pour un frémissement)
const PART_RELACHEMENT := 2.0e-3  # part de l'énergie libérée qui part en son
const ECART_RELACHEMENT := 0.3    # s
const DEGRES_TIC := 1.5           # K gagnés ou perdus par tic de la coque
const TICS_MAX := 8.0             # par seconde
const DT_MIN := 0.02              # K/s : en dessous, la coque se repose (pas de tic)
const E_TIC := 3.0e-3             # J : un petit tic (jusqu'à 10 fois plus)
const L_TIC_J := 74.0             # dB dans le cockpit pour 1 J (tôle d'aluminium, comme les chocs du sol)
const PART_CHANT := 3.0e-4        # part de la variation de l'énergie élastique qui part en son continu
const ANNEAU := 8                 # photos gardées (50 ms à 120 photos par seconde : 6)
const FENETRE := 0.1              # s : comme chocs.gd (le niveau d'un son bref = moyenne sur 100 ms)
## Points de la coque qui tiquent (repère du modèle) : nez (le plus chaud), dessus, dessous, flancs, arrière.
const COQUE_TICS := [Vector3(0.0, 0.0, -5.4), Vector3(0.0, 0.2, -4.0), Vector3(0.0, 0.6, 1.5), Vector3(0.0, -0.9, -1.0),
	Vector3(-0.9, 0.0, -2.0), Vector3(0.9, 0.0, -2.0), Vector3(0.0, -0.8, 2.5), Vector3(0.0, 0.3, 4.5)]
## Couleur du chant de chaque matière (bosse en échelle logarithmique : fréquence centrale, largeur).
const COULEURS := {"composite": [600.0, 0.7], "titane": [1500.0, 0.8], "acier": [1200.0, 0.8], "verre": [2500.0, 0.6],
	"aluminium": [1300.0, 0.8]}

var charges := Charges.new()
var _memoire := PackedFloat64Array()      # plus forte charge récente de chaque pièce (effet Kaiser)
var _attente := PackedFloat64Array()      # craquements « dus » pas encore joués
var _dernier := PackedFloat64Array()      # s : dernier craquement de chaque pièce
var _avant := PackedFloat64Array()        # taux de la photo précédente
var _anneau := PackedFloat64Array()       # taux des ANNEAU dernières photos de chaque pièce (relâchements)
var _anneau_t := PackedFloat64Array()     # s : heure de chacune de ces photos
var _case := 0
var _felicite := PackedFloat64Array()
var _l_j := PackedFloat64Array()
var _familles := PackedStringArray()
var _relache := PackedFloat64Array()
var _chemins := PackedFloat64Array()      # dB : chemin de l'attache jusqu'au pilote
var _distances := PackedFloat64Array()    # m de structure
var _geo := -1
var _seau := CRAQUEMENTS_MAX              # « seau » de craquements permis (se remplit de 30 par seconde)
var _t_coque := NAN
var _tic := 0.0                           # degrés accumulés depuis le dernier tic
var _rng := RandomNumberGenerator.new()
var _formes_matiere := {}

## Sons brefs depuis la dernière lecture : [famille, niveau (dB), position, n°, intensité, priorité, trajet (m)]
var evenements: Array = []
## Chant de la structure : niveau (dB dans le cockpit) et forme (30 tiers d'octave, somme 1).
var niveau := -INF
var forme := PackedFloat64Array()
var cote := CoteSon.milieu()     # d'où vient le chant (les pièces qui chantent le plus fort), par octave
var tete := Basis.IDENTITY       # orientation de la tête du pilote, donnée par le chef d'orchestre
var _tete_connue := Basis.IDENTITY
var _t_pieces: Array = []        # table de côté de chaque attache (cote_son.gd)
var _oreille := Vector3.ZERO
var _compte_cote := 0
var craquements := 0                      # depuis le début (tests) : joués
var craquements_dus := 0                  # tirés (certains se perdent dans les autres quand il y en a trop)
var relachements := 0
var tics := 0


func _init() -> void:
	_rng.seed = 47
	var n := charges.n
	for a in [_memoire, _attente, _relache, _chemins, _distances]:
		a.resize(n)
		a.fill(0.0)
	_memoire.fill(EPREUVE)
	_dernier.resize(n)
	_dernier.fill(-1.0)
	_avant.resize(n)
	_avant.fill(NAN)
	_anneau.resize(n * ANNEAU)
	_anneau.fill(0.0)
	_anneau_t.resize(ANNEAU)
	_anneau_t.fill(-INF)
	for i in n:
		var mat: String = charges.matieres[i]
		_felicite.append(float(Pieces.MATIERES[mat]["felicite"]))
		_l_j.append(float(Pieces.MATIERES[mat]["l_j"]))
		_familles.append(_famille(mat))
	for mat in COULEURS:
		var cl: Array = COULEURS[mat]
		_formes_matiere[mat] = SolSon._forme(func(f: float) -> float: return SolSon._cloche(f, float(cl[0]), float(cl[1])))
	forme = _formes_matiere["composite"]


static func _db(x: float) -> float:
	return 10.0 * log(x) / log(10.0) if x > 0.0 else -INF


func _chemin(oreille: Vector3) -> void:
	_geo = charges._geo
	for i in charges.n:
		var d := (charges.attaches_modele[i] - oreille).length()
		_distances[i] = d
		_chemins[i] = Pieces.ATTENUATION * d + charges.jonctions[i]
	_oreille = oreille
	_cotes()


func _cotes() -> void:
	_tete_connue = tete
	_t_pieces.resize(charges.n)
	for i in charges.n:
		_t_pieces[i] = CoteSon.table(charges.attaches_modele[i], _oreille, tete, CoteSon.PROCHE_STRUCTURE_DB)


## Après chaque photo (120 fois par seconde) : charges, puis craquements, relâchements et tics.
func detecter(c: Capteurs, oreille: Vector3, dt: float) -> void:
	charges.calculer(c, dt)
	if _geo != charges._geo:
		_chemin(oreille)
	var t := c.temps
	_seau = minf(_seau + CRAQUEMENTS_MAX * dt, CRAQUEMENTS_MAX)
	var oubli := exp(-dt / OUBLI)
	# photos des 50 dernières ms (relâchements)
	_case = (_case + 1) % ANNEAU
	_anneau_t[_case] = t
	var cases := PackedInt32Array()
	for j in ANNEAU:
		if t - _anneau_t[j] <= FENETRE_CHUTE:
			cases.append(j)
	for i in charges.n:
		var tau := minf(charges.taux[i], TAUX_MAX)
		# --- craquements : seulement quand on dépasse ce que la pièce a déjà connu (Kaiser-Felicity) ---
		var mem := _memoire[i]
		var seuil := (1.0 - (1.0 - _felicite[i]) * clampf((mem - 0.4) / 0.6, 0.0, 1.0)) * mem
		var avant := _avant[i] if not is_nan(_avant[i]) else tau
		_avant[i] = tau
		if tau > seuil and tau > avant:
			# nombre de craquements de ce pas : tiré au hasard (loi de Poisson) autour du nombre attendu
			var k := _poisson(N_RUPTURE * (pow(tau, EXPOSANT) - pow(maxf(seuil, avant), EXPOSANT)))
			# au plus 2 en attente : des craquements trop serrés se fondent en un seul (sinon ils joueraient encore
			# longtemps après la surcharge, alors qu'ils se produisent pendant qu'elle monte)
			_attente[i] = minf(_attente[i] + k, ATTENTE_MAX)
			craquements_dus += int(k)
		_memoire[i] = maxf(EPREUVE + (mem - EPREUVE) * oubli, tau)
		while _attente[i] >= 1.0:
			if t - _dernier[i] < ECART_CRAQUEMENTS:
				break
			_attente[i] -= 1.0
			_dernier[i] = t
			if _seau < 1.0:
				continue   # trop de craquements à la fois : celui-ci se perd dans les autres
			_seau -= 1.0
			_craquer(i, tau)
		# --- relâchement : chute brutale de la charge ---
		var base := i * ANNEAU
		_anneau[base + _case] = tau
		var haut := 0.0
		for j in cases:
			haut = maxf(haut, _anneau[base + j])
		if haut - tau >= CHUTE_MIN and tau < (1.0 - CHUTE) * haut and t - _relache[i] > ECART_RELACHEMENT:
			_relache[i] = t
			var e_lib := charges.energie_rupture[i] * (haut * haut - tau * tau) * PART_RELACHEMENT
			evenements.append(["relachement_" + _familles[i], _l_j[i] + _db(e_lib) - _chemins[i], charges.attaches_modele[i], i,
				clampf(sqrt(haut * haut - tau * tau) / 0.6, 0.0, 1.0), 2, _distances[i]])
			relachements += 1
			for j in ANNEAU:
				_anneau[base + j] = tau   # on repart de la charge d'après la chute
	_tics(c, oreille, dt)


func _craquer(i: int, tau: float) -> void:
	# Gutenberg-Richter : énergie de 1 à 100 fois la plus petite, P(> x) ∝ 1/x
	var x := 1.0 / (1.0 - _rng.randf() * (1.0 - 1.0 / GROS_MAX))
	var e := charges.energie_rupture[i] * tau * tau * PART_CRAQUEMENT * x
	var l := _l_j[i] + _db(e) - _chemins[i]
	# un peu plus loin ou plus près de l'attache (le craquement naît quelque part dans la pièce)
	var pos: Vector3 = charges.attaches_modele[i] + (charges.centres[i] - charges.attaches[i]) * _rng.randf_range(0.0, 0.6)
	evenements.append(["craquement_" + _familles[i], l, pos, i, clampf(_db(x) / 20.0, 0.0, 1.0), 1, _distances[i]])
	craquements += 1


## Loi de Poisson : nombre d'événements pour une moyenne m (tirage exact, au plus 60).
func _poisson(m: float) -> float:
	if m <= 0.0:
		return 0.0
	var k := 0
	var p := exp(-minf(m, 60.0))
	var s := p
	var u := _rng.randf()
	while u > s and k < 60:
		k += 1
		p *= m / k
		s += p
	return float(k)


static func _famille(mat: String) -> String:
	return "verre" if mat == "verre" else ("composite" if mat == "composite" else "metal")


## La coque qui chauffe ou refroidit (température du nez, la plus chaude).
func _tics(c: Capteurs, oreille: Vector3, dt: float) -> void:
	var tc := c.temperature_coque
	if tc <= 0.0 or dt <= 0.0:
		return
	if is_nan(_t_coque):
		_t_coque = tc
		return
	var vitesse := absf(tc - _t_coque) / maxf(c.temps_physique, 1e-9) if c.temps_physique > 0.0 else 0.0
	var dtemp := absf(tc - _t_coque)
	_t_coque = tc
	if vitesse < DT_MIN:
		return
	# loi de Poisson : un tic tous les DEGRES_TIC en moyenne, pas plus de TICS_MAX par seconde
	var attendu := minf(dtemp / DEGRES_TIC, TICS_MAX * dt)
	if _rng.randf() < attendu:
		var pos: Vector3 = COQUE_TICS[_rng.randi() % COQUE_TICS.size()] if _rng.randf() < 0.6 else COQUE_TICS[0]
		var x := 1.0 / (1.0 - _rng.randf() * 0.9)   # 1 à 10 fois
		var oreille_d := (pos - oreille).length()
		evenements.append(["tic_thermique", L_TIC_J + _db(E_TIC * x) - Pieces.ATTENUATION * oreille_d, pos, -1,
			clampf(_db(x) / 10.0, 0.0, 1.0), 1, oreille_d])
		tics += 1


## Chant de la structure (60 fois par seconde) : puissance = PART_CHANT × U × |d(taux²)/dt| de chaque pièce.
func calculer(_c: Capteurs) -> void:
	var e30 := PackedFloat64Array()
	e30.resize(30)
	var total := 0.0
	if _t_pieces.size() == charges.n and Quaternion(_tete_connue.inverse() * tete).get_angle() > deg_to_rad(2.0):
		_cotes()
	_compte_cote = (_compte_cote + 1) % 4   # le côté du chant : 15 fois par seconde suffit
	var refaire := _compte_cote == 0
	var acc := CoteSon.vide()
	for i in charges.n:
		if charges.taux[i] >= TAUX_MAX:
			continue   # pièce « cassée » (le jeu ne casse rien) : ses craquements disent déjà tout
		var tau := charges.taux[i]
		var p := PART_CHANT * charges.energie_rupture[i] * 2.0 * tau * absf(charges.variation[i])
		if p <= 0.0:
			continue
		var mat: String = charges.matieres[i]
		var l := float(Pieces.MATIERES[mat]["l_j"]) + _db(p * FENETRE) - _chemins[i]
		var e := pow(10.0, l / 10.0)
		var fm: PackedFloat64Array = _formes_matiere[mat]
		for j in 30:
			e30[j] += e * fm[j]
		total += e
		if refaire and i < _t_pieces.size():
			CoteSon.cumuler(acc, _t_pieces[i], e)
	if refaire:
		cote = CoteSon.finir(acc, total) if total > 0.0 else CoteSon.milieu()
	niveau = _db(total)
	if total > 0.0:
		var f := PackedFloat64Array()
		f.resize(30)
		for j in 30:
			f[j] = e30[j] / total
		forme = f
