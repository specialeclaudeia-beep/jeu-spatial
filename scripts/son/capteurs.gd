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

# --- phase 4 : mouvement du vaisseau (tension des pièces : scripts/son/charges.gd) ---
var masse := 0.0                                  # kg
var inertie := Vector3.ZERO                       # kg·m² (axes principaux)
var omega := Vector3.ZERO                         # rad/s : rotation, repère du vaisseau
var alpha := Vector3.ZERO                         # rad/s² : variation de la rotation entre deux photos
var acceleration := Vector3.ZERO                  # m/s² : ce que sent le pilote (sans la gravité), repère du vaisseau
var maree_k := 0.0                                # s⁻² : G·M / r³ de l'astre qui étire le plus le vaisseau
var maree_dir := Vector3.ZERO                     # direction de cet astre, repère du vaisseau
var aile_de := PackedInt32Array()                 # n° de l'aile de chaque propulseur (0 à 3, comme ci-dessous ; −1 = aucune)
var poussee_levage := 0.0                         # N : un moteur de levage à pleine puissance
## Les 4 ailes, dans l'ordre haut gauche, haut droit, bas gauche, bas droit : charnière et angle (degrés).
var charnieres := PackedVector3Array()
var angles_ailes := PackedFloat64Array()
var angles_ailes_ouvertes := PackedFloat64Array()
var angle_tuyere := 0.0                           # degrés (vol vertical)
var pivot_tuyere := Vector3.ZERO
var amorti_train := PackedFloat64Array()          # N·s/m : amortisseur de chaque jambe (cas de calcul du train)
## Air : force (N) et couple autour du centre de gravité (N·m) sur chaque surface (repère du vaisseau) :
## 0-3 ailes, 4-5 dérives gauche et droite, 6 fuselage, 7 nez, 8 train.
var air_f := PackedVector3Array()
var air_c := PackedVector3Array()
var sol_f := PackedVector3Array()                 # N : force moyenne du sol sur chaque point qui touche
var pression_dehors := 0.0                        # Pa (0 dans le vide)
var pression_cabine := 101325.0                   # Pa : l'air de la cabine (atelier, étape 8 : il peut fuir)
var temps_physique := 0.0                         # s : temps de l'univers écoulé depuis la photo précédente
# --- phase 4 : où l'on est (poussière et gaz de l'espace : scripts/son/poussiere_son.gd) ---
var vitesse := 0.0                                # m/s, par rapport à l'astre du repère (toujours < c)
var gamma := 1.0                                  # facteur de Lorentz
var direction := Vector3.ZERO                     # sens du mouvement, repère du vaisseau
var dist_etoile := INF                            # m : étoile (ou trou noir) la plus proche
var dist_astre := INF                             # m : centre de la planète ou de la lune la plus proche
var rayon_astre := 0.0                            # m : son rayon

# --- phase 5 : l'air en détail (scripts/son/air_son.gd), lecture seule ---
var mach := 0.0                                   # nombre de Mach du vaisseau
var part_libre := 0.0                             # part « molécules isolées » de l'air (0 = fluide), comme la physique
var sortie_levage := 0.0                          # 0..1 : sortie des moteurs de levage (leurs trappes s'ouvrent d'abord)
## Chaque plaque qui porte (12 bandes d'aile, puis les 2 dérives) : angle d'attaque (rad), vitesse de l'air vue (m/s),
## surface (m²), corde (m), point (repère du vaisseau).
var plaques_alpha := PackedFloat64Array()
var plaques_v := PackedFloat64Array()
var plaques_surface := PackedFloat64Array()
var plaques_corde := PackedFloat64Array()
var plaques_point := PackedVector3Array()

const NOMS_AILES := ["haut_gauche", "haut_droit", "bas_gauche", "bas_droit"]
const GM_ETOILE := 1.0e18                         # m³/s² : au-dessus, c'est une étoile (Soleil : 1,3e20 ; Jupiter : 1,3e17)
const R_AIR := 287.05

var _ailes := -1.0
var _vertical := -1.0
var _omega_avant := Vector3.ZERO
var _t_univers := NAN
var _base_avant := Basis.IDENTITY
var _base_lue := false


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
		aile_de.resize(n)
		centre_gravite = v.centre_gravite
		poussee_reference = v.poussee_moteur_nominale
		poussee_levage = v.poussee_levage_nominale
		pivot_tuyere = v.pivot_tuyere
		amorti_train = PackedFloat64Array(v.amorti_train)
		charnieres.resize(4)
		angles_ailes.resize(4)
		angles_ailes_ouvertes.resize(4)
		for k in 4:
			var a: Dictionary = v.ailes_def[NOMS_AILES[k]]
			charnieres[k] = a["charniere"]
			angles_ailes_ouvertes[k] = float(a["ouvert"])
		_ailes = -1.0
	# positions et directions : seulement quand les ailes ou le vol vertical bougent
	var bouge: bool = v.ailes != _ailes or v.vertical != _vertical
	if bouge:
		_ailes = v.ailes
		_vertical = v.vertical
		geometrie += 1
		for k in 4:
			angles_ailes[k] = v.angle_aile(NOMS_AILES[k])
		angle_tuyere = v.angle_tuyere()
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
			aile_de[i] = NOMS_AILES.find(String(t["aile"]))
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
	_lire_mouvement(v, dt)
	_lire_lieu(v)
	_lire_sol(v)


## Phase 4 : rotation, accélération ressentie, marée, air sur chaque surface (lecture seule).
func _lire_mouvement(v, dt: float) -> void:
	masse = v.masse
	inertie = v.inertie
	var base := Basis(v.orientation)
	omega = v.omega
	# temps de l'univers écoulé depuis la photo précédente (temps accéléré compris)
	if is_nan(_t_univers):
		temps_physique = dt
		_omega_avant = omega
	else:
		temps_physique = maxf(float(v.temps_univers) - _t_univers, 0.0)
	_t_univers = v.temps_univers
	alpha = (omega - _omega_avant) / temps_physique if temps_physique > 0.0 else Vector3.ZERO
	_omega_avant = omega
	# la physique calcule l'accélération ressentie AVANT de tourner le vaisseau pendant le pas : on la lit dans
	# l'orientation du début du pas (celle de la photo précédente), sinon 0,1 % de la poussée partirait de côté
	acceleration = (_base_avant if _base_lue else base).inverse() * v.acceleration_ressentie
	_base_avant = base
	_base_lue = true
	pression_dehors = densite * R_AIR * temperature if densite > 0.0 else 0.0
	var vie = v.get("vie")
	pression_cabine = float(vie.pression_cabine()) if vie != null else 101325.0
	air_f = v.aero.prise_f.duplicate()
	air_c = v.aero.prise_c.duplicate()
	mach = v.aero.mach
	part_libre = v.aero.part_libre
	sortie_levage = v.sortie_levage()
	plaques_alpha = v.aero.prise_alpha.duplicate()
	plaques_v = v.aero.prise_v.duplicate()
	plaques_surface = v.aero.prise_surface.duplicate()
	plaques_corde = v.aero.prise_corde.duplicate()
	plaques_point = v.aero.prise_point.duplicate()
	# marée : l'astre qui étire le plus (G·M / r³ le plus grand)
	maree_k = 0.0
	if v.gm != 0.0:
		var r: float = v.distance_centre()
		maree_k = v.gm / (r * r * r)
		maree_dir = base.inverse() * Vector3(-v.px, -v.py, -v.pz).normalized()
	for a in v.autres_astres:
		var dx: float = float(a["x"]) - v.px
		var dy: float = float(a["y"]) - v.py
		var dz: float = float(a["z"]) - v.pz
		var d := sqrt(dx * dx + dy * dy + dz * dz)
		var k: float = float(a["gm"]) / (d * d * d)
		if k > maree_k:
			maree_k = k
			maree_dir = base.inverse() * Vector3(dx / d, dy / d, dz / d)


## Phase 4 : vitesse et distances aux astres (densité de poussière et de gaz de l'endroit).
func _lire_lieu(v) -> void:
	vitesse = v.vitesse()
	gamma = v.gamma()
	direction = Basis(v.orientation).inverse() * Vector3(v.vx, v.vy, v.vz).normalized() if vitesse > 0.0 else Vector3.ZERO
	dist_etoile = INF
	dist_astre = INF
	rayon_astre = 0.0
	var r_c: float = v.distance_centre()
	if v.gm >= GM_ETOILE:
		dist_etoile = r_c
	elif v.gm > 0.0:
		dist_astre = r_c
		rayon_astre = v.rayon_planete
	for a in v.autres_astres:
		var dx: float = float(a["x"]) - v.px
		var dy: float = float(a["y"]) - v.py
		var dz: float = float(a["z"]) - v.pz
		var d := sqrt(dx * dx + dy * dy + dz * dz)
		if float(a["gm"]) >= GM_ETOILE:
			dist_etoile = minf(dist_etoile, d)
		else:
			var ra: float = float(a.get("rayon", 0.0))
			# la plus proche, rapportée à sa taille
			if ra > 0.0 and (rayon_astre <= 0.0 or d / ra < dist_astre / rayon_astre):
				dist_astre = d
				rayon_astre = ra


## Phase 3 : la prise du sol (moyennes sur les petits pas de physique depuis la photo précédente), puis on
## la vide. C'est la seule chose que le son « écrit » : des compteurs que la physique ne lit jamais.
func _lire_sol(v) -> void:
	var np: int = v.prise_points
	if points_sol.size() != np:
		points_sol.clear()
		for p in v.roues:
			points_sol.append(p)
		for p in v.coque_points:
			points_sol.append(p)
		for a in [sol_choc, sol_choc_cote, sol_fn, sol_glisse]:
			a.resize(np)
		for a in [sol_butee, sol_roule, sol_frein]:
			a.resize(v.roues.size())
		sol_f.resize(np)
	poids = v.masse * 9.81
	var n: int = maxi(v.prise_n, 1)
	for k in np:
		sol_choc[k] = v.prise_choc[k]
		sol_choc_cote[k] = v.prise_choc_cote[k]
		sol_fn[k] = v.prise_fn[k] / n
		sol_glisse[k] = v.prise_glisse[k] / n
		sol_f[k] = v.prise_f_sol[k] / n if v.prise_n > 0 else Vector3.ZERO
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
