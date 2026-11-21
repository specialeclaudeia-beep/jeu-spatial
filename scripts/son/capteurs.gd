extends RefCounted
## Capteurs du moteur audio : une « photo » de la physique, prise après chaque pas (120 fois par seconde).
##
## C'est le SEUL fichier du son qui connaît les noms des variables de la physique (vaisseau_physique.gd).
## Il ne fait que lire : il n'écrit jamais rien dans le vaisseau. Si la physique change de noms, on ne
## retouche que ce fichier ; le reste du moteur audio ne voit que la photo.

const TYPE_MOTEUR := 0     # les 5 moteurs arrière
const TYPE_LEVAGE := 1     # les 2 moteurs de levage (vol vertical)
const TYPE_RCS := 2        # petits propulseurs d'orientation et buses de la coque

# --- propulseurs (moteurs, puis petits propulseurs), repère du modèle (comme la physique) ---
var nombre := 0
var types := PackedInt32Array()
var forces := PackedFloat64Array()        # N : poussée réelle (réglage de puissance compris)
var niveaux := PackedFloat64Array()       # 0..1 : niveau réel
var consignes := PackedFloat64Array()     # 0..1 : niveau demandé (les moteurs le suivent en 0,3 s)
var poussees_max := PackedFloat64Array()  # N à pleine puissance
var positions := PackedVector3Array()     # m : point de poussée
var directions := PackedVector3Array()    # sens de la force (le jet part à l'opposé)
var sur_aile := PackedByteArray()         # 1 = posé sur une aile (le son passe par l'emplanture)
var geometrie := 0                        # augmente quand les positions changent (ailes, vol vertical)
var centre_gravite := Vector3.ZERO
var poussee_reference := 0.0              # N : un moteur arrière à pleine puissance réelle (x1)

# --- air autour du vaisseau ---
var densite := 0.0          # kg/m³ (0 dans le vide)
var temperature := 0.0      # K
var vitesse_air := 0.0      # m/s par rapport à l'air
var vent := Vector3.ZERO    # m/s : vitesse de l'air par rapport au vaisseau, repère du vaisseau
var temperature_coque := -1.0   # K (nez)

# --- état ---
var au_sol := false
var ecrase := false
var temps := 0.0            # s : temps réel écoulé (horloge du son)

# --- sol (phase 3) : la « prise » de _forces_sol, depuis la photo précédente ---
## Points qui touchent le sol : roues 0 à 2 (avant, arrière gauche, arrière droite), puis 6 points de la coque.
var points_sol := PackedVector3Array()
var poids := 0.0                                  # N : masse × 9,81 (référence des forces du sol)
var sol_choc := PackedFloat64Array()              # m/s : vitesse d'arrivée sur le sol d'un point qui touche (0 = rien)
var sol_choc_cote := PackedFloat64Array()         # m/s : vitesse le long du sol à ce moment
var sol_butee := PackedFloat64Array()             # m/s : amortisseur arrivé en bout de course
var sol_fn := PackedFloat64Array()                # N : force moyenne qui appuie sur le sol
var sol_roule := PackedFloat64Array()             # m/s : vitesse de roulement moyenne de chaque roue
var sol_glisse := PackedFloat64Array()            # m/s : vitesse moyenne de glissement (dérapage, raclage)
var sol_frein := PackedFloat64Array()             # 0..1 : serrage moyen des freins d'une roue qui roule
var compression := PackedFloat64Array()           # m : écrasement de chaque amortisseur
var frein_parc := false
var frein := 0.0                                  # 0..1 : freins demandés (Maj)
var train_sorti := 0.0                            # 0 = rentré, 1 = sorti
var train_consigne := 0.0
var ailes := 1.0                                  # 0 = repliées, 1 = ouvertes
var ailes_consigne := 1.0
var braquage := 0.0                               # rad : roue avant
var vertical := 0.0                               # 0 = vol normal, 1 = vol vertical (tuyère tournée)
var vertical_consigne := 0.0

var _ailes := -1.0
var _vertical := -1.0


func lire(v, dt: float) -> void:
	temps += dt
	var n_m: int = v.moteurs.size()
	var n: int = n_m + v.rcs.size()
	if n != nombre:
		nombre = n
		for a in [types, forces, niveaux, consignes, poussees_max]:
			a.resize(n)
		positions.resize(n)
		directions.resize(n)
		sur_aile.resize(n)
		centre_gravite = v.CENTRE_GRAVITE
		poussee_reference = v.POUSSEE_MOTEUR
		_ailes = -1.0
	# positions et directions : seulement quand les ailes ou le vol vertical bougent
	var bouge: bool = v.ailes != _ailes or v.vertical != _vertical
	if bouge:
		_ailes = v.ailes
		_vertical = v.vertical
		geometrie += 1
	var facteur: float = v.facteur_poussee
	for i in n:
		var t: Dictionary = v.moteurs[i] if i < n_m else v.rcs[i - n_m]
		var niveau := float(t["actuel"])
		var pmax := float(t["poussee_max"]) * (facteur if i < n_m else 1.0)
		niveaux[i] = niveau
		consignes[i] = float(t["consigne"]) if i < n_m else niveau
		poussees_max[i] = pmax
		forces[i] = maxf(niveau, 0.0) * pmax
		if bouge:
			var nom: String = t["nom"]
			types[i] = TYPE_RCS if i >= n_m else (TYPE_LEVAGE if nom.begins_with("levage") else TYPE_MOTEUR)
			positions[i] = t["position"]
			directions[i] = t["direction"]
			sur_aile[i] = 1 if String(t["aile"]) != "" else 0
	densite = v.densite_air
	temperature = v.temperature_air
	vitesse_air = v.vitesse_air
	temperature_coque = v.temperature_nez
	if densite > 0.0:
		var v_rel: Vector3 = Vector3(v.vx, v.vy, v.vz) - v.vitesse_sol(v.px, v.py, v.pz)
		vent = Basis(v.orientation).inverse() * (-v_rel)
	else:
		vent = Vector3.ZERO
	au_sol = v.au_sol
	ecrase = v.ecrase
	_lire_sol(v)


## Phase 3 : la prise du sol (moyennes sur les petits pas de physique depuis la photo précédente), puis on
## la vide. C'est la seule chose que le son « écrit » : des compteurs que la physique ne lit jamais.
func _lire_sol(v) -> void:
	var np: int = v.PRISE_POINTS
	if points_sol.size() != np:
		points_sol.clear()
		for p in v.ROUES:
			points_sol.append(p)
		for p in v.COQUE:
			points_sol.append(p)
		for a in [sol_choc, sol_choc_cote, sol_fn, sol_glisse]:
			a.resize(np)
		for a in [sol_butee, sol_roule, sol_frein]:
			a.resize(3)
	poids = v.masse * 9.81
	var n: int = maxi(v.prise_n, 1)
	for k in np:
		sol_choc[k] = v.prise_choc[k]
		sol_choc_cote[k] = v.prise_choc_cote[k]
		sol_fn[k] = v.prise_fn[k] / n
		sol_glisse[k] = v.prise_glisse[k] / n
	for k in 3:
		sol_butee[k] = v.prise_butee[k]
		sol_roule[k] = v.prise_roule[k] / n
		sol_frein[k] = v.prise_frein[k] / n
	if v.prise_n == 0:
		sol_fn.fill(0.0)
	v.vider_prise_sol()
	compression = v.compression_roues
	frein_parc = v.frein_parc
	frein = v.frein
	train_sorti = v.train
	train_consigne = v.train_consigne
	ailes = v.ailes
	ailes_consigne = v.ailes_consigne
	braquage = v.braquage
	vertical = v.vertical
	vertical_consigne = v.vertical_consigne
