extends RefCounted
## Le moteur ionique « façon Star Wars » (moteur audio, phase 6) : ce qu'on entend À L'INTÉRIEUR des moteurs.
##
## C'est une INVENTION assumée (décision du 21/11, pour le son seulement) : la physique du jeu ne connaît que la
## poussée de chaque moteur (elle suit sa consigne en 0,3 s) ; il n'y a ni carburant, ni pompe, ni chambre. On donne ici
## au vaisseau un petit « intérieur » de moteur à plasma, qui suit de vraies lois là où elles existent. Rien dans ce
## fichier ne touche la physique : il lit la photo (capteurs.gd), comme tout le son.
##
## L'idée : un réacteur d'énergie, au cœur du vaisseau (derrière le pilote, avec le moteur central), fabrique
## l'électricité ; chaque moteur s'en sert pour créer un champ magnétique (ses bobines) et pour faire d'un gaz un plasma,
## que le champ pousse dehors à 3 000 m/s (la vitesse de jet choisie le 21/11, pour le son seulement).
##
##  1. Le réacteur qui bourdonne. Son courant passe par des transformateurs : le fer de leurs noyaux s'allonge et se
##     raccourcit deux fois par période (magnétostriction, le « bourdon » de tous les transformateurs) : 110 Hz et ses
##     harmoniques. Un peu même au repos (le réacteur garde le vaisseau en vie), plus fort quand on lui demande de la
##     puissance (vibration ∝ courant²). La puissance est vraie : pousser F avec un jet de 3 000 m/s demande ½ F v
##     divisé par le rendement (65 %) : 460 MW par moteur arrière à fond, 2,3 GW pour les cinq.
##     Comme un vrai groupe électrogène, sa fréquence baisse un peu quand il est chargé (« statisme », −3 % à pleine
##     charge) et creuse un peu plus au moment où l'on remet les gaz, le temps que le réacteur suive (0,6 s) ; elle
##     remonte un instant quand on coupe.
##  2. Les bobines qui sifflent. Pour pousser plus de plasma (plus de poussée, à vitesse de jet fixe), il faut un champ
##     plus fort : la pression du champ (B² / 2μ₀) doit tenir celle du plasma, qui suit la poussée : B ∝ √poussée.
##     Le courant des bobines vient d'un onduleur dont la fréquence suit le courant (comme le sifflement d'un tramway
##     qui suit sa vitesse) ; bobines et supports vibrent au double de cette fréquence (force ∝ courant²) : un
##     sifflement qui monte avec √poussée, jusqu'à 2,4 kHz à fond (et son double, plus faible). Énergie ∝ B⁴.
##     Chaque moteur a son onduleur, réglé à quelques millièmes près : deux moteurs « battent » doucement entre eux,
##     comme les hélices d'un bimoteur.
##     Montée et descente en régime : le champ doit être là AVANT le plasma. Quand on remet les gaz, les bobines se
##     chargent en 0,12 s (le sifflement part un peu avant la poussée). Quand on coupe, le courant d'une bobine ne peut
##     pas s'arrêter d'un coup (elle garde son énergie ½ L I²) : il s'écoule en ~0,9 s (L / R) et le sifflement
##     redescend en glissant après la coupure. Puis le contacteur s'ouvre.
##  3. La chambre à plasma qui gronde. Dans un moteur à plasma, le gaz ne s'ionise pas régulièrement mais par vagues
##     (« mode de respiration », mesuré sur les vrais propulseurs de Hall) : f = √(v_gaz × v_ions) / (2π L), L = longueur
##     de la zone où le gaz s'ionise (0,8 m pour un moteur arrière, 0,35 m pour un moteur de levage), v_ions = 3 000 m/s,
##     v_gaz ≈ 300 m/s quand les parois sont froides : ~190 Hz. Les parois chauffent avec la puissance (jusqu'à 1 200 K,
##     en quelques secondes) ; le gaz en repart plus vite (v ∝ √T) : le grondement monte (×1,4). C'est la vraie montée
##     en régime, lente, après l'allumage ; il redescend quand le moteur refroidit. Une respiration n'est jamais
##     régulière : son énergie tremble au hasard. Le grondement large de la phase 1 (la poussée n'est jamais parfaitement
##     régulière) suit la même fréquence (facteur_regime).
##  4. L'allumage détaillé (sons brefs, chocs.gd) : le contacteur des bobines se ferme (« clac » qui rebondit, comme un
##     vrai contacteur), les bobines se chargent (le sifflement part du grave), puis le plasma s'amorce (« whoomp » grave,
##     étincelles de l'arc, bouffée de gaz : moteurs_son.gd, « moteur_allumage »), quand le champ a atteint 30 % (~43 ms
##     après le « clac » ; le chef d'orchestre retient le « whoomp » jusque-là) ; à la coupure, la structure se relâche,
##     le sifflement redescend, et le contacteur s'ouvre (petit arc qui claque).
##
## Tout arrive au pilote par la structure (même chemin que moteurs_son.gd : 1 dB par mètre, 6 dB de plus au passage d'une
## emplanture d'aile), chacun de son côté (cote_son.gd) : le sifflement d'un moteur d'aile gauche s'entend à gauche ; le
## réacteur, au milieu, derrière. Un son pur qui tombe sur une résonance d'un panneau du cockpit sonne plus fort
## (Resonances.reponse). Le côté de chaque son pur est donné à la partie C++ (SyntheSon.regler_raies).
## Les niveaux sont des réglages « à l'oreille », à valider à l'écoute sur le PC.

const Capteurs = preload("res://scripts/son/capteurs.gd")
const CoteSon = preload("res://scripts/son/cote_son.gd")
const Resonances = preload("res://scripts/son/resonances.gd")
const MoteursSon = preload("res://scripts/son/moteurs_son.gd")

const COUCHES := ["bobines", "plasma", "reacteur"]
const VITESSE_JET := MoteursSon.VITESSE_JET    # 3 000 m/s, pour le son seulement
const RENDEMENT := 0.65                        # part de l'électricité qui finit dans le jet
const MOTEURS_MAX := 7                         # 5 moteurs arrière + 2 de levage (7 × 2 sons purs)

# --- 1. réacteur ---
const POSITION_REACTEUR := Vector3(0.0, 0.0, 3.6)   # avec le cœur du moteur central (modèle v27, Masse_moteur_central)
const F_BOURDON := 110.0                      # Hz : deux fois la fréquence du courant (55 Hz)
const HARMONIQUES := [[1, 0.5], [2, 0.28], [3, 0.14], [4, 0.08]]   # [rang, part de l'énergie]
const STATISME := 0.03                        # −3 % à pleine charge
const CREUX := 0.06                           # creux passager : 6 % de l'écart entre demande et puissance
const TAU_REACTEUR := 0.6                     # s
const VEILLE := 0.03                          # part de la pleine charge au repos (le vaisseau vit)
const REACTEUR_REPOS_DB := 52.0               # dB dans le cockpit, au repos : on l'entend à peine, dans le silence (−55 dB pleine échelle)
const REACTEUR_PLEIN_DB := 70.0               # à pleine charge (les 5 moteurs arrière à fond)
# --- 2. bobines ---
const F_ONDULEUR := 1200.0                    # Hz : onduleur d'un moteur arrière à pleine poussée (sifflement à 2 f)
const F_ONDULEUR_LEVAGE := 1900.0             # moteurs de levage : plus petits, plus aigus
const PART_DOUBLE := 0.3                      # part de l'énergie à 4 f (le reste à 2 f)
const BOBINES_DB := 76.0                      # moteur arrière à fond, au bout d'une structure de longueur nulle
const BOBINES_LEVAGE_DB := 68.0
const TAU_CHARGE := 0.12                      # s : les bobines se chargent
const TAU_DECHARGE := 0.9                     # s : L / R, le courant s'écoule
## Petits écarts de réglage des onduleurs (moteurs dans l'ordre de la physique : 4 d'aile, central, 2 de levage).
const ECARTS_ONDULEURS := [-0.0024, 0.0013, -0.0011, 0.0021, 0.0, 0.0017, -0.0015]
const SEUIL_CONTACTEUR := 0.003               # niveau (ou consigne) au-dessus duquel les bobines sont alimentées
const CHAMP_OUVERTURE := 0.03                 # le contacteur s'ouvre quand le champ est retombé sous 3 %
const CONTACTEUR_DB := 84.0                   # dB : contacteur qui se ferme (au bout d'une structure de longueur nulle)
const CONTACTEUR_OUVERTURE_DB := 80.0
const ECART_CONTACTEUR := 0.3                 # s
const CHAMP_AMORCAGE := 0.3                   # le plasma ne s'amorce qu'avec un champ : ~43 ms après le « clac »
const ATTENTE_AMORCAGE := 0.25                # s : au plus (temps réel)
# --- 3. chambre à plasma ---
const V_GAZ_FROID := 300.0                    # m/s : gaz qui entre, parois à 300 K
const T_FROID := 300.0
const T_CHAUD := 1200.0                       # K : parois à pleine puissance
const TAU_CHAUFFE := 4.0                      # s
const TAU_REFROIDIT := 12.0
const LONGUEUR := 0.8                         # m : zone d'ionisation d'un moteur arrière
const LONGUEUR_LEVAGE := 0.35
const PLASMA_DB := 87.0                       # moteur arrière à 200 kN, au bout d'une structure de longueur nulle
const LARGEUR_RESPIRATION := 0.22             # octave (écart type de la bosse)
const RESPIRATION_ECART := 0.5                # irrégularité de l'énergie (moyenne 1)
const RESPIRATION_TEMPS := 0.06               # s
# --- sons purs dans la voix « structure » (0 et 1 : la pompe des vérins) ---
const RAIE_BOBINES := 2                       # 2 par moteur : 2 à 15
const RAIE_REACTEUR := 16                     # 16 à 19

## Ce que le chef d'orchestre lit (comme air_son.gd) : niveau (dB dans le cockpit), forme (30 tiers d'octave, somme 1 ;
## pour les couches de sons purs, elle sert au masquage), raies [[n°, Hz, part de l'énergie de la couche, part à gauche]].
var niveaux := {"bobines": -INF, "plasma": -INF, "reacteur": -INF}
var formes := {}
var raies := {"bobines": [], "plasma": [], "reacteur": []}
var facteur_regime := 1.0        # fréquences du grondement large × ce facteur (parois chaudes)
var facteur_respiration := 1.0   # énergie du grondement de la chambre × ce facteur (moyenne 1)
## Sons brefs : [nom, niveau (dB), position, n°, intensité, 0, trajet (m)]
var evenements: Array = []
var tete := Basis.IDENTITY
var resonances = null

## État du modèle (un par moteur) et dernières valeurs, pour les tests et l'affichage.
var champ := PackedFloat64Array()        # 0..1 : champ des bobines / champ à pleine poussée
var t_paroi := PackedFloat64Array()      # K
var contacteur := PackedByteArray()
var f_sifflement := PackedFloat64Array() # Hz : 2 f de chaque onduleur
var f_respiration := PackedFloat64Array()
var demande := VEILLE                    # 0..1 (et un peu plus avec les moteurs de levage)
var puissance := VEILLE                  # ce que le réacteur fournit (suit la demande)
var f_bourdon := F_BOURDON
var puissance_mw := 0.0                  # MW demandés par les moteurs
var contacts := 0                        # contacteurs fermés ou ouverts depuis le début

var _n := 0
var _dernier := PackedFloat64Array()
var _tables: Array = []                  # côté de chaque moteur (par la structure)
var _table_reacteur := CoteSon.milieu()
var _geometrie := -1
var _tete_connue := Basis.IDENTITY
var _bosses := {}                        # bosses de respiration déjà calculées (par fréquence arrondie)
var _x := 0.0
var _vu := PackedFloat64Array()          # ce qui a servi au dernier calcul de chaque couche
var _n_att := -1
var _rng := RandomNumberGenerator.new()


func _init() -> void:
	_rng.seed = 606
	for nom in COUCHES:
		formes[nom] = PackedFloat64Array()
		formes[nom].resize(30)
		formes[nom].fill(1.0 / 30.0)


static func _db(x: float) -> float:
	return 10.0 * log(x) / log(10.0) if x > 0.0 else -INF


## Fréquence de respiration d'une chambre de longueur l, parois à t (K).
static func respiration(t: float, l: float) -> float:
	var v_gaz := V_GAZ_FROID * sqrt(maxf(t, 1.0) / T_FROID)
	return sqrt(v_gaz * VITESSE_JET) / (TAU * l)


## Puissance électrique (W) que demande un moteur qui pousse f newtons.
static func puissance_moteur(f: float) -> float:
	return 0.5 * f * VITESSE_JET / RENDEMENT


func _preparer(c: Capteurs, oreille: Vector3) -> void:
	var n := 0
	for i in c.nombre:
		if c.types[i] != Capteurs.TYPE_RCS:
			n += 1
	n = mini(n, MOTEURS_MAX)
	if n != _n:
		_n = n
		for a in [champ, f_sifflement, f_respiration, _dernier]:
			a.resize(n)
			a.fill(0.0)
		_dernier.fill(-1.0e9)
		t_paroi.resize(n)
		t_paroi.fill(T_FROID)
		contacteur.resize(n)
		contacteur.fill(0)
	_geometrie = c.geometrie
	_tete_connue = tete
	_tables.resize(n)
	for k in n:
		_tables[k] = CoteSon.table(c.positions[k], oreille, tete, CoteSon.PROCHE_STRUCTURE_DB)
	_table_reacteur = CoteSon.table(POSITION_REACTEUR, oreille, tete, CoteSon.PROCHE_STRUCTURE_DB)


## Le modèle avance de dt secondes (temps du pilote : 0 en pause, × le temps accéléré). sons : faut-il demander les sons
## brefs (contacteurs) ? Appelé 120 fois par seconde, après les capteurs.
func avancer(c: Capteurs, oreille: Vector3, dt: float, sons: bool, attenuation: PackedFloat64Array) -> void:
	if c.geometrie != _geometrie or _tables.size() != _n or _n == 0:
		_preparer(c, oreille)
	var f_ref := c.poussee_reference
	var d := 0.0
	var p_w := 0.0
	for k in _n:
		var levage := c.types[k] == Capteurs.TYPE_LEVAGE
		var niveau := clampf(c.niveaux[k], 0.0, 1.0)
		var voulu := maxf(clampf(c.consignes[k], 0.0, 1.0), niveau)
		var dispo := c.poussees_max[k] > 0.0       # un moteur de levage rentré ne peut rien faire
		var alimente := dispo and voulu > SEUIL_CONTACTEUR
		var cible := sqrt(voulu) if alimente else 0.0
		if dt > 0.0:
			var tau := TAU_CHARGE if cible > champ[k] else TAU_DECHARGE
			champ[k] = cible + (champ[k] - cible) * exp(-dt / tau)
			if cible == 0.0 and champ[k] < 1e-4:
				champ[k] = 0.0
			var t_cible := T_FROID + (T_CHAUD - T_FROID) * niveau
			var tau_t := TAU_CHAUFFE if t_cible > t_paroi[k] else TAU_REFROIDIT
			t_paroi[k] = t_cible + (t_paroi[k] - t_cible) * exp(-dt / tau_t)
		var f_vrai := (c.poussee_levage if levage else f_ref) * niveau   # poussée des vrais moteurs (sans le réglage x…)
		d += f_vrai / (5.0 * f_ref) if f_ref > 0.0 else 0.0
		p_w += puissance_moteur(f_vrai)
		# contacteurs : il se ferme dès qu'on demande de la poussée ; il s'ouvre quand le champ est retombé
		var ferme := contacteur[k] == 1
		var nom := ""
		if not ferme and alimente:
			contacteur[k] = 1
			nom = "contacteur_fermeture"
		elif ferme and not alimente and champ[k] < CHAMP_OUVERTURE:
			contacteur[k] = 0
			nom = "contacteur_ouverture"
		if nom != "":
			contacts += 1
			if sons and c.temps - _dernier[k] >= ECART_CONTACTEUR:
				_dernier[k] = c.temps
				var att: float = attenuation[k] if k < attenuation.size() else 0.0
				var db := (CONTACTEUR_DB if nom == "contacteur_fermeture" else CONTACTEUR_OUVERTURE_DB) - att
				var trajet: float = (c.positions[k] - oreille).length()
				evenements.append([nom, db, c.positions[k], k, 0.4 if levage else 0.7, 0, trajet])
	demande = VEILLE + (1.0 - VEILLE) * d
	puissance_mw = p_w * 1e-6
	if dt > 0.0:
		puissance = demande + (puissance - demande) * exp(-dt / TAU_REACTEUR)
	f_bourdon = F_BOURDON * clampf(1.0 - STATISME * puissance - CREUX * (demande - puissance), 0.85, 1.1)


## Les sons continus, à chaque image (60 fois par seconde). attenuation : chemin dans la structure de chaque propulseur
## (moteurs_son.gd) ; dt : temps réel depuis l'image précédente (irrégularité de la respiration).
func calculer(c: Capteurs, oreille: Vector3, attenuation: PackedFloat64Array, dt: float) -> void:
	var refait := false
	if c.geometrie != _geometrie or _tables.size() != _n:
		_preparer(c, oreille)
		refait = true
	elif Quaternion(_tete_connue.inverse() * tete).get_angle() > deg_to_rad(2.0):
		_preparer(c, oreille)
		refait = true
	if resonances == null:
		resonances = Resonances.new()
	_balancer(dt)
	# une couche n'est refaite que si ce qui la fait a bougé (en vol tranquille, presque rien à calculer) ; les écarts
	# tolérés sont inaudibles : 1/100 000 du champ (0,02 Hz de sifflement), 0,01 K de paroi
	var vu := _vu
	var n_vu := 3 * _n + 2
	if vu.size() != n_vu or attenuation.size() != _n_att:
		vu.resize(n_vu)
		vu.fill(-1.0)
		_n_att = attenuation.size()
		refait = true
	var bobines := refait
	var plasma := refait
	for k in _n:
		bobines = bobines or absf(champ[k] - vu[k]) > 1e-5
		plasma = plasma or c.forces[k] != vu[_n + k] or absf(t_paroi[k] - vu[2 * _n + k]) > 0.01
	var reacteur := refait or absf(puissance - vu[3 * _n]) > 1e-5 or absf(f_bourdon - vu[3 * _n + 1]) > 1e-4
	if bobines:
		niveaux["bobines"] = -INF
		raies["bobines"] = []
		_bobines(c, attenuation)
		for k in _n:
			vu[k] = champ[k]
	if plasma:
		niveaux["plasma"] = -INF
		_plasma(c, attenuation)
		for k in _n:
			vu[_n + k] = c.forces[k]
			vu[2 * _n + k] = t_paroi[k]
	if reacteur:
		niveaux["reacteur"] = -INF
		raies["reacteur"] = []
		_reacteur()
		vu[3 * _n] = puissance
		vu[3 * _n + 1] = f_bourdon


## Ajoute un son pur à une liste : [n°, Hz, énergie, part à gauche], et son énergie à la forme (30 tiers d'octave).
func _son_pur(liste: Array, forme: PackedFloat64Array, n: int, f: float, e: float, t: PackedFloat64Array) -> float:
	var j := Resonances.bande(f)
	var o := clampi(j / 3, 0, CoteSon.OCTAVES - 1)
	var en: float = e * t[CoteSon.OCTAVES + o] * resonances.reponse(f)
	if en <= 0.0:
		return 0.0
	liste.append([n, f, en, t[o]])
	forme[j] += en
	return en


## Range une couche de sons purs : niveau, forme (somme 1), part de chaque son.
func _ranger(nom: String, liste: Array, forme: PackedFloat64Array, total: float) -> void:
	if total <= 0.0:
		return
	niveaux[nom] = _db(total)
	for j in 30:
		forme[j] /= total
	formes[nom] = forme
	for r in liste:
		r[2] = float(r[2]) / total
	raies[nom] = liste


## 2. Les bobines : deux sons purs par moteur (2 f et 4 f de son onduleur), de son côté.
func _bobines(c: Capteurs, attenuation: PackedFloat64Array) -> void:
	var liste := []
	var forme := PackedFloat64Array()
	forme.resize(30)
	var total := 0.0
	for k in _n:
		var b := champ[k]
		var levage := c.types[k] == Capteurs.TYPE_LEVAGE
		var f_o := (F_ONDULEUR_LEVAGE if levage else F_ONDULEUR) * b * (1.0 + float(ECARTS_ONDULEURS[k]))
		f_sifflement[k] = 2.0 * f_o
		if b <= 1e-3:
			continue
		var att: float = attenuation[k] if k < attenuation.size() else 0.0
		var e := pow(10.0, ((BOBINES_LEVAGE_DB if levage else BOBINES_DB) - att) / 10.0) * b * b * b * b
		total += _son_pur(liste, forme, RAIE_BOBINES + 2 * k, 2.0 * f_o, e * (1.0 - PART_DOUBLE), _tables[k])
		total += _son_pur(liste, forme, RAIE_BOBINES + 2 * k + 1, 4.0 * f_o, e * PART_DOUBLE, _tables[k])
	_ranger("bobines", liste, forme, total)


## 3. La chambre à plasma : une bosse de bruit autour de la fréquence de respiration de chaque moteur qui pousse.
func _plasma(c: Capteurs, attenuation: PackedFloat64Array) -> void:
	var forme := PackedFloat64Array()
	forme.resize(30)
	var total := 0.0
	var regime := 0.0
	var f_ref := c.poussee_reference
	var par_bosse := {}   # moteurs qui respirent à la même fréquence : une seule bosse (moins de calcul)
	for k in _n:
		var levage := c.types[k] == Capteurs.TYPE_LEVAGE
		var l := LONGUEUR_LEVAGE if levage else LONGUEUR
		var fr := respiration(t_paroi[k], l)
		f_respiration[k] = fr
		var f := c.forces[k]
		if f <= 0.0 or f_ref <= 0.0:
			continue
		var att: float = attenuation[k] if k < attenuation.size() else 0.0
		var e := pow(10.0, (PLASMA_DB - att) / 10.0) * (f / f_ref) * (f / f_ref)
		var cle := roundi(log(fr) / log(1.0025))
		par_bosse[cle] = float(par_bosse.get(cle, 0.0)) + e
		total += e
		regime += e * fr / respiration(T_FROID, l)
	if total <= 0.0:
		facteur_regime = 1.0
		return
	for cle in par_bosse:
		var bosse := _bosse_cle(cle)
		var e: float = par_bosse[cle]
		for j in 30:
			forme[j] += e * bosse[j]
	facteur_regime = regime / total
	niveaux["plasma"] = _db(total)
	for j in 30:
		forme[j] /= total
	formes["plasma"] = forme


## Bosse de respiration autour de fr (largeur LARGEUR_RESPIRATION octave), gardée en mémoire par pas de 0,25 %.
func _bosse(fr: float) -> PackedFloat64Array:
	return _bosse_cle(roundi(log(fr) / log(1.0025)))


func _bosse_cle(cle: int) -> PackedFloat64Array:
	if not _bosses.has(cle):
		if _bosses.size() > 512:
			_bosses.clear()
		var f0 := pow(1.0025, cle)
		var e := PackedFloat64Array()
		e.resize(30)
		var tot := 0.0
		for j in 30:
			var x := log(Resonances.centre(j) / f0) / log(2.0) / LARGEUR_RESPIRATION
			e[j] = exp(-0.5 * x * x)
			tot += e[j]
		for j in 30:
			e[j] /= tot
		_bosses[cle] = e
	return _bosses[cle]


## 1. Le réacteur : 4 sons purs (110 Hz et ses harmoniques), au milieu, derrière.
func _reacteur() -> void:
	var liste := []
	var forme := PackedFloat64Array()
	forme.resize(30)
	var charge := clampf((puissance - VEILLE) / (1.0 - VEILLE), 0.0, 1.5)
	var repos := pow(10.0, REACTEUR_REPOS_DB / 10.0)
	var e := repos + (pow(10.0, REACTEUR_PLEIN_DB / 10.0) - repos) * charge * charge
	var total := 0.0
	for h in HARMONIQUES.size():
		var rang: int = HARMONIQUES[h][0]
		total += _son_pur(liste, forme, RAIE_REACTEUR + h, f_bourdon * rang, e * float(HARMONIQUES[h][1]), _table_reacteur)
	_ranger("reacteur", liste, forme, total)


## Respiration irrégulière : énergie × (1 + 0,5 x)² / (1 + 0,5²), x lent et au hasard (Ornstein-Uhlenbeck).
func _balancer(dt: float) -> void:
	if dt <= 0.0:
		return
	var a := exp(-dt / RESPIRATION_TEMPS)
	_x = a * _x + sqrt(1.0 - a * a) * _rng.randfn(0.0, 1.0)
	var g := maxf(1.0 + RESPIRATION_ECART * clampf(_x, -3.0, 3.0), 0.0)
	facteur_respiration = g * g / (1.0 + RESPIRATION_ECART * RESPIRATION_ECART)


## Le plasma du moteur k peut-il s'amorcer (son champ est-il là) ? Le « whoomp » de l'allumage attend ce moment.
func amorce(k: int) -> bool:
	return k < 0 or k >= champ.size() or champ[k] >= CHAMP_AMORCAGE


## Maîtres des sons purs de la voix « structure » : l'harmonique d'un moteur ou du réacteur tremble avec sa fondamentale.
static func liens() -> PackedInt32Array:
	var l := PackedInt32Array()
	l.resize(24)
	l.fill(-1)
	for k in MOTEURS_MAX:
		l[RAIE_BOBINES + 2 * k + 1] = RAIE_BOBINES + 2 * k
	for h in range(1, HARMONIQUES.size()):
		l[RAIE_REACTEUR + h] = RAIE_REACTEUR
	return l
