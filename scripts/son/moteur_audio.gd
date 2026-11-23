extends Node
## Moteur audio (phase 1) : le « chef d'orchestre ». Il écoute la physique et fait le son du cockpit.
## Il ne modifie JAMAIS la physique : il la lit (capteurs.gd), calcule ce que le pilote entend
## (moteurs_son.gd, fluides_son.gd), puis décide quoi jouer et à quel volume.
##
## Règles (plan du 21/11, réponses de Gwenaël) :
##  - on n'entend que le cockpit, jamais l'espace : l'oreille est toujours celle du pilote, même en vue
##    extérieure ; dans le vide, seul ce qui passe par la structure arrive (le cockpit, lui, est plein d'air) ;
##  - temps accéléré : son normal jusqu'à x10, silence au-delà (sauf les alarmes, quand il y en aura) ;
##  - pause, écran des touches, vaisseau écrasé : fondu au silence en 0,1 s ;
##  - 24 voix au plus : 8 couches continues + 16 sons brefs (16 lecteurs créés une fois pour toutes) ;
##  - priorités : alarmes > chocs > moteurs > air > tension > ambiance ;
##  - un son trop faible (sous −60 dB) ou caché par un autre (20 dB plus fort dans les mêmes fréquences)
##    n'est pas joué ;
##  - volume : on calcule d'abord le vrai niveau dans le cockpit (dB), puis on le ramène à ce qu'un
##    haut-parleur peut rendre. Au-delà de 95 dB, le volume monte 4 fois moins vite (sinon un réglage de
##    poussée x100 000 ferait exploser les oreilles).
##
## Bus de mixage (créés au démarrage) : Structure (vibrations) et Exterieur (passé par la verrière) vont
## dans Cockpit (petite réverbération), qui va dans Master (limiteur). Le souffle a un égaliseur à
## 10 octaves : on lui donne, bande par bande, le spectre calculé par la physique (egaliseur.gd calcule
## exactement ce qui en sort). Les jets n'en ont pas besoin : la forme de leur bruit ne change pas.
##
## Phase 6 : l'intérieur des moteurs ioniques (ionique_son.gd, modèle inventé pour le son seulement). Le réacteur
## bourdonne (110 Hz et ses harmoniques, plus fort et un peu plus grave quand il est chargé), les bobines de chaque
## moteur sifflent (le sifflement monte avec √poussée, part avant la poussée, redescend en glissant après la coupure),
## la chambre à plasma gronde (vagues d'ionisation vers 190 Hz, plus aiguës quand les parois chauffent). Les contacteurs
## claquent. Les sons purs (bobines, réacteur) sont des raies de la voix « structure », chacune de son côté
## (SyntheSon.regler_raies) ; le grondement de la chambre a le côté des moteurs.
##
## Phase 2 : les sons continus sont fabriqués EN DIRECT par la partie C++ (classe SyntheSon,
## labo-lumiere/cpp/src/synthe_son.cpp), dans le fil audio de Godot. Deux « voix » :
##  - structure (bus Structure) : grondement des moteurs + souffle des petits propulseurs, qui arrivent par les
##    panneaux du cockpit ; en grave, ces panneaux résonnent à leurs fréquences propres (resonances.gd) ;
##  - air (bus Exterieur) : souffle de l'air + bruit des jets, à travers la verrière.
## Ce fichier leur donne, 60 fois par seconde, l'énergie voulue dans 30 tiers d'octave (le spectre calculé par
## la physique, sans égaliseur ni boucle) ; le C++ y glisse doucement par blocs de 5 ms. Le niveau qui sort est
## exactement le niveau calculé. Sans la partie C++, ou avec l'option `-- --son-boucles`, on garde les
## boucles de la phase 1.
##
## Phase 3 : le sol et les mécanismes (sol_son.gd). Les sons BREFS (chocs, vannes, verrous, pneus) sont eux
## aussi fabriqués en direct : chocs.gd écrit la recette de chaque choc (modes de la pièce frappée), la classe C++
## ChocsSon la fait sonner (16 chocs à la fois au plus). Les sons continus du sol (roulement, frein, dérapage,
## raclage) et des vérins s'ajoutent aux voix C++ : roulement et vérins dans la voix « structure » (ils passent par
## les panneaux qui résonnent), dérapage, frein et raclage dans une 3e voix « sol » dont les sons purs tremblent
## plus (un pneu qui crisse n'est jamais stable). Sans la partie C++, pas de sons brefs ni de sons du sol.
##
## Phase 4 : la tension des pièces et la poussière de l'espace. charges.gd calcule 120 fois par seconde la charge
## exacte de chaque attache (ailes, réacteurs, moteur central, dérives, jambes du train, verrière, nez : principe de
## d'Alembert) ; tension_son.gd en tire les craquements (émission acoustique, effet Kaiser), les relâchements, les
## tics de la coque qui chauffe ou refroidit, et le « chant » de la structure (couche « tension », voix structure :
## elle passe par les panneaux du cockpit qui résonnent). poussiere_son.gd fait frapper les grains et le gaz de
## l'espace (rares « tic » en orbite, pluie puis souffle continu près de la vitesse de la lumière : couche
## « poussiere », voix air, et les plus gros grains un par un). Un son bref qui traverse la structure perd ses aigus
## en route (« trajet », chocs.gd).
##
## Côté (phase 4, demande de Gwenaël) : chaque moteur, chaque petit propulseur et chaque pièce qui chante a sa place
## dans le cockpit. cote_son.gd calcule, octave par octave, la part qui arrive à l'oreille gauche (parois de son côté,
## ombre de la tête dans les aigus, aigus perdus si le son vient de derrière) ; la partie C++ donne à chaque tiers
## d'octave sa part à gauche. Tout est dans le repère de la tête : si le pilote tourne la tête, le son reste à sa
## place dans le cockpit. Les sons brefs font de même (Chocs.panoramique).
##
## Phase 5 : l'air en détail (air_son.gd). Le train sorti siffle (tourbillons de Strouhal derrière les jambes), les
## puits de train ouverts grondent (Rossiter), les ailes tremblent autour de Mach 1 (choc qui va et vient) et quand
## elles décrochent, l'onde de choc bat devant la verrière au-delà du son (rentrée). Tout s'efface quand l'air devient
## trop rare pour être un fluide. Le sifflement et les trappes sont des sons purs (raies de la voix air) ; le
## tremblement passe par l'emplanture des ailes (voix structure, du côté de l'aile qui tremble).

const Capteurs = preload("res://scripts/son/capteurs.gd")
const MoteursSon = preload("res://scripts/son/moteurs_son.gd")
const Fluides = preload("res://scripts/son/fluides_son.gd")
const Egaliseur = preload("res://scripts/son/egaliseur.gd")
const Synthese = preload("res://scripts/son/synthese.gd")
const Resonances = preload("res://scripts/son/resonances.gd")
const SolSon = preload("res://scripts/son/sol_son.gd")
const Chocs = preload("res://scripts/son/chocs.gd")
const TensionSon = preload("res://scripts/son/tension_son.gd")
const PoussiereSon = preload("res://scripts/son/poussiere_son.gd")
const CoteSon = preload("res://scripts/son/cote_son.gd")
const AirSon = preload("res://scripts/son/air_son.gd")
const IoniqueSon = preload("res://scripts/son/ionique_son.gd")

const CATALOGUE := "res://sons/sons.json"
const COUCHES_MAX := 8
const LECTEURS := 16            # chocs à la fois (partie C++ ChocsSon)
const VOIX_MAX := COUCHES_MAX + LECTEURS
const SEUIL_DB := -60.0          # dB pleine échelle : en dessous, on ne joue pas
const MASQUAGE_DB := 20.0
const FONDU_SILENCE := 0.1       # s
const TEMPS_MAX_SON := 10        # au-delà de x10, silence
## Échelle du volume : 107 dB dans le cockpit = pleine échelle (0 dB). Au-delà de 95 dB, compression 4:1 ;
## jamais plus fort que −2 dB pleine échelle (le limiteur du bus Master garde encore 1 dB de marge).
const ZERO_DBFS := 107.0
const GENOU := 95.0
const TAUX_COMPRESSION := 4.0
const PLAFOND := -2.0
const ATTAQUE := 0.02            # s : la compression réagit vite quand ça monte…
const RELACHE := 0.3             # s : … et revient doucement
const RELACHE_COUCHE := 0.06     # s : une couche qui baisse (jet de gaz coupé) s'éteint en ~60 ms
## Phase 2 : les voix fabriquées en direct, et les couches qu'elles regroupent (bus, graine du hasard).
const VOIX_DIRECTES := {
	"structure": {"bus": "Structure", "couches": ["structure", "rcs", "roulage", "verins", "tension", "tremblement",
		"plasma", "bobines", "reacteur"], "graine": 21},
	"air": {"bus": "Exterieur", "couches": ["souffle", "jet", "jet_rcs", "poussiere", "sifflement", "cavites", "choc_verriere"],
		"graine": 22, "instabilite": 0.012, "instabilite_temps": 0.15},
	"sol": {"bus": "Structure", "couches": ["derapage", "frein", "raclage"], "graine": 23, "instabilite": 0.03, "instabilite_temps": 0.02},
}
## Couches de la phase 3 (sol et vérins) : elles n'ont pas de boucle de la phase 1.
const COUCHES_SOL := ["roulage", "verins", "derapage", "frein", "raclage"]
## Couches de la phase 4 (tension des pièces, poussière de l'espace).
const COUCHES_PHASE4 := ["tension", "poussiere"]
## Couches de la phase 5 (l'air en détail).
const COUCHES_PHASE5 := ["sifflement", "cavites", "tremblement", "choc_verriere"]
## Couches de la phase 6 (l'intérieur des moteurs ioniques).
const COUCHES_PHASE6 := ["plasma", "bobines", "reacteur"]
const RAIES_VOIX := 24           # sons purs de chaque voix C++ (SyntheSon.RAIES)
## Priorité de chaque famille de sons brefs.
const PRIORITE_CHOC := {"pneu_toucher": 4, "coque_choc": 4, "train_butee": 4, "amortisseur_detente": 4, "pneu_crissement": 4,
	"gravier": 1, "frein_serrage": 3, "verin_depart": 3, "verin_arret": 3, "verrouillage": 3,
	"craquement_composite": 1, "craquement_metal": 1, "craquement_verre": 1, "tic_thermique": 1,
	"relachement_composite": 2, "relachement_metal": 2, "relachement_verre": 2, "poussiere_verre": 2, "poussiere_coque": 1,
	"contacteur_fermeture": 3, "contacteur_ouverture": 3}
const BOUCLE_DE := {"structure": "structure", "rcs": "rcs", "jet": "jet_moteur", "jet_rcs": "jet_rcs", "souffle": "souffle"}
const LISSAGE_DIRECT := 0.01     # s : les cibles changent 60 fois par seconde, le C++ les rejoint en ~10 ms
const OCTAVE_DE := [0, 0, 0, 1, 1, 1, 2, 2, 2, 3, 3, 3, 4, 4, 4, 5, 5, 5, 6, 6, 6, 7, 7, 7, 8, 8, 8, 9, 9, 9]
const BATTEMENT := 0.18          # léger battement du grondement des moteurs (le même que la boucle de la phase 1)

enum { AMBIANCE, TENSION, AIR, MOTEUR, CHOC, ALARME }

# --- branchements ---
var vaisseau = null
var pilote: Node3D = null              # nœud qui suit le vaisseau (centre de gravité à l'origine)
var camera: Camera3D = null
var oreille_scene := Vector3.ZERO      # tête du pilote dans le nœud « pilote »
var oreille := Vector3.ZERO            # la même, repère du modèle (comme la physique)
var tete := Basis.IDENTITY             # orientation de la tête du pilote (repère du modèle), pour le côté des sons
var capteurs := Capteurs.new()
var moteurs := MoteursSon.new()
var sol := SolSon.new()
var tension := TensionSon.new()
var poussiere := PoussiereSon.new()
var air := AirSon.new()
var ionique := IoniqueSon.new()
var _amorcages: Array = []             # allumages qui attendent le champ des bobines : [demande, n° du moteur, heure limite]
var ecoute: AudioListener3D = null
var actif := false

# --- état du jeu (donné par jeu.gd à chaque image) ---
var pause := false
var acc_temps := 1
var vue_interieure := true

# --- phase 2 : sons fabriqués en direct (C++) ---
var forcer_boucles := false      # à mettre avant installer() : garder les boucles de la phase 1
var hors_ligne := false          # tests : les voix ne jouent pas en vrai (le test calcule leur son lui-même)
## Mode --mesure : les deux voix C++ calculent à pleine charge (30 bandes et 32 résonances), à −80 dB (inaudible),
## pour mesurer leur coût dans le fil audio pendant que le jeu dessine.
var banc := false
var synthese_directe := false
var voix_directes := {}          # nom → {lecteur, flux (SyntheSon), couches, bandes}
var resonances = null
var _formes := {}                # couche → part de son énergie dans chaque tiers d'octave (somme = 1)
var _regime_forme := -1.0
var _battement := []             # [fréquence, phase, poids] des 6 ondes lentes du battement
var _norme_battement := 1.0

# --- mixage ---
var couches := {}       # nom → {lecteur, ref_dbfs, parts (énergie par octave de la boucle), eq, niveau, lisse, priorite}
## Phase 3 : sons brefs fabriqués en direct (partie C++ ChocsSon) ; chocs en cours, vus d'ici : [fin (s), priorité]
var chocs = null              # ChocsSon
var lecteur_chocs: AudioStreamPlayer = null
var _chocs_en_cours: Array = []
var _demandes: Array = []   # sons brefs en attente : [nom, niveau (dB), position, priorite, âge, intensité, trajet (m)]
var fondu := 0.0        # 0 = silence, 1 = son normal
var gain := 0.0         # dB : réduction de la compression (≤ 0)
var souffle := {}       # dernier calcul du souffle (fluides_son.gd)
var _transm := PackedFloat64Array()
var _z_ext := -1.0
var _rng := RandomNumberGenerator.new()
var ms_par_image := 0.0     # temps de calcul du son par image (moyenne glissante)
var _us_physique := 0
var joues := 0              # sons brefs lancés depuis le début
var oublies := 0            # sons brefs écartés (trop faibles, cachés, pas de lecteur)


## À appeler une fois, après la création du vaisseau et du nœud « pilote ».
## oeil : position de la tête du pilote dans le nœud « pilote » (comme la caméra du cockpit).
func installer(v, noeud_pilote: Node3D, cam: Camera3D, oeil: Vector3) -> void:
	vaisseau = v
	pilote = noeud_pilote
	camera = cam
	oreille_scene = oeil
	capteurs.lire(vaisseau, 0.0)
	oreille = oeil + capteurs.centre_gravite
	_rng.seed = 7
	preparer_bus()
	air_cabine_db = 0.0
	if AudioServer.get_bus_index("Cockpit") >= 0:
		AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Cockpit"), 0.0)
	synthese_directe = ClassDB.class_exists("SyntheSon") and not forcer_boucles \
		and not OS.get_cmdline_user_args().has("--son-boucles")
	_charger_sons()
	ecoute = AudioListener3D.new()
	ecoute.name = "OreillePilote"
	pilote.add_child(ecoute)
	ecoute.position = oreille_scene
	ecoute.make_current()
	actif = true


## Atelier, étape 8 : l'air de la cabine porte le son jusqu'à l'oreille. Une paroi qui vibre pousse l'air
## avec une pression proportionnelle à la densité de cet air (impédance ρ·c) : à moitié de la pression,
## −6 dB ; à un dixième, −20 dB. Il reste au moins −30 dB : ce qui passe par le siège et le casque (os du
## crâne). Les alarmes (casque) ne changent pas. Le bus « Cockpit » est remis à 0 dB à chaque partie.
const AIR_CABINE_MIN_DB := -30.0
var air_cabine_db := 0.0


func _air_cabine() -> void:
	var p := capteurs.pression_cabine
	var db := clampf(20.0 * log(maxf(p, 1.0) / 101325.0) / log(10.0), AIR_CABINE_MIN_DB, 0.0)
	if absf(db - air_cabine_db) < 0.1 and not (db == 0.0 and air_cabine_db != 0.0):
		return
	air_cabine_db = db
	var i := AudioServer.get_bus_index("Cockpit")
	if i >= 0:
		AudioServer.set_bus_volume_db(i, db)


## Bus de mixage (une seule fois par partie : ils restent d'une scène à l'autre).
static func preparer_bus() -> void:
	if AudioServer.get_bus_index("Cockpit") >= 0:
		return
	var master := AudioServer.get_bus_index("Master")
	var limiteur := AudioEffectHardLimiter.new()
	limiteur.ceiling_db = -1.0
	AudioServer.add_bus_effect(master, limiteur)
	var cockpit := _nouveau_bus("Cockpit", "Master")
	# petite pièce, parois dures et garnitures : réverbération courte (~0,15 s), discrète
	var reverb := AudioEffectReverb.new()
	reverb.room_size = 0.08
	reverb.damping = 0.7
	reverb.spread = 1.0
	reverb.hipass = 0.15
	reverb.dry = 1.0
	reverb.wet = 0.08
	reverb.predelay_msec = 4.0
	reverb.predelay_feedback = 0.0
	AudioServer.add_bus_effect(cockpit, reverb)
	_nouveau_bus("Structure", "Cockpit")
	_nouveau_bus("Exterieur", "Cockpit")
	AudioServer.add_bus_effect(_nouveau_bus("Souffle", "Exterieur"), AudioEffectEQ10.new())
	_nouveau_bus("Jet", "Exterieur")
	_nouveau_bus("Alarmes", "Master")


static func _nouveau_bus(nom: String, vers: String) -> int:
	var i := AudioServer.bus_count
	AudioServer.add_bus(i)
	AudioServer.set_bus_name(i, nom)
	AudioServer.set_bus_send(i, vers)
	return i


func _charger_sons() -> void:
	var f := FileAccess.open(CATALOGUE, FileAccess.READ)
	if f == null:
		push_warning("Son : catalogue %s introuvable" % CATALOGUE)
		return
	var cat = JSON.parse_string(f.get_as_text())
	if not (cat is Dictionary):
		return
	var b: Dictionary = cat["boucles"]
	if synthese_directe:
		_preparer_voix_directes(b)
	else:
		_couche("structure", "structure", b, "Structure", MOTEUR)
		_couche("rcs", "rcs", b, "Structure", MOTEUR)
		_couche("jet", "jet_moteur", b, "Jet", MOTEUR)
		_couche("jet_rcs", "jet_rcs", b, "Jet", MOTEUR)
		_couche("souffle", "souffle", b, "Souffle", AIR)
	if synthese_directe and ClassDB.class_exists("ChocsSon"):
		chocs = ClassDB.instantiate("ChocsSon")
		lecteur_chocs = AudioStreamPlayer.new()
		lecteur_chocs.name = "Voix_chocs"
		lecteur_chocs.stream = chocs
		lecteur_chocs.bus = "Structure"
		add_child(lecteur_chocs)


func _couche(nom: String, boucle: String, catalogue: Dictionary, bus: String, priorite: int) -> void:
	if couches.size() >= COUCHES_MAX or not catalogue.has(boucle):
		return
	var infos: Dictionary = catalogue[boucle]
	var l := AudioStreamPlayer.new()
	l.name = "Couche_" + nom
	l.stream = load(infos["fichier"])
	l.bus = bus
	add_child(l)
	var eq: AudioEffectEQ10 = null
	var m_eq := PackedFloat64Array()
	var i_bus := AudioServer.get_bus_index(bus)
	if i_bus >= 0 and AudioServer.get_bus_effect_count(i_bus) > 0:
		eq = AudioServer.get_bus_effect(i_bus, 0) as AudioEffectEQ10
	if eq != null:
		# ce que l'égaliseur de Godot fait vraiment à cette boucle (une fois pour toutes)
		var forme: String = Synthese.BOUCLES[boucle]["spectre"]
		m_eq = Egaliseur.matrice(func(f: float) -> float: return Synthese.spectre(forme, f), AudioServer.get_mix_rate())
	couches[nom] = {"lecteur": l, "ref_dbfs": float(infos["rms_dbfs"]), "parts": PackedFloat64Array(infos["bandes"]),
		"eq": eq, "m_eq": m_eq, "niveau": -INF, "lisse": -INF, "priorite": priorite, "bandes_db": PackedFloat64Array(),
		"volume": -80.0}


## Phase 2 : les deux voix fabriquées en direct par la partie C++.
func _preparer_voix_directes(catalogue: Dictionary) -> void:
	resonances = Resonances.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 1303
	_battement.clear()
	var somme := 0.0
	for k in 6:
		var poids := rng.randf_range(0.5, 1.0)
		_battement.append([rng.randf_range(2.0, 10.0), rng.randf() * TAU, poids])
		somme += poids * poids
	_norme_battement = 1.0 / sqrt(somme * 0.5)   # le battement a une valeur efficace de 1 (× BATTEMENT)
	for nv in VOIX_DIRECTES:
		var d: Dictionary = VOIX_DIRECTES[nv]
		var flux = ClassDB.instantiate("SyntheSon")
		flux.graine = int(d["graine"])
		flux.lissage = LISSAGE_DIRECT
		if d.has("instabilite"):
			flux.instabilite = float(d["instabilite"])
			flux.instabilite_temps = float(d["instabilite_temps"])
		if nv == "structure":
			flux.regler_modes(resonances.frequences, resonances.pertes)
			if flux.has_method("lier_raies"):
				flux.lier_raies(IoniqueSon.liens())   # les harmoniques tremblent avec leur fondamentale (phase 6)
			ionique.resonances = resonances
		# les filtres sont calculés une fois ici (quelques ms), jamais pendant le jeu
		flux.instantiate_playback().start(0.0)
		var l := AudioStreamPlayer.new()
		l.name = "Voix_" + nv
		l.stream = flux
		l.bus = d["bus"]
		add_child(l)
		var bandes := PackedFloat32Array()
		bandes.resize(30)
		var ecarts := PackedFloat64Array()
		ecarts.resize(30)
		var parts_gauche := PackedFloat32Array()
		parts_gauche.resize(30)
		parts_gauche.fill(0.5)
		voix_directes[nv] = {"lecteur": l, "flux": flux, "couches": d["couches"], "bandes": bandes, "ecarts": ecarts,
			"parts_gauche": parts_gauche}
		for nom in d["couches"]:
			var parts := PackedFloat64Array()
			var priorite := AIR if nom == "souffle" or nom in COUCHES_SOL else MOTEUR
			if BOUCLE_DE.has(nom):
				parts = PackedFloat64Array(catalogue[BOUCLE_DE[nom]]["bandes"])
			elif nom in COUCHES_PHASE4:
				parts = SolSon.octaves(_forme(nom))
				priorite = TENSION if nom == "tension" else AMBIANCE
			elif nom in COUCHES_PHASE5:
				parts = SolSon.octaves(_forme(nom))
				priorite = AIR
			elif nom in COUCHES_PHASE6:
				parts = SolSon.octaves(_forme(nom))
				priorite = AMBIANCE if nom == "reacteur" else MOTEUR
			else:
				parts = SolSon.octaves(sol.formes.get(nom, SolSon.forme_roulage(10.0)))
			couches[nom] = {"lecteur": l, "ref_dbfs": 0.0, "parts": parts,
				"eq": null, "m_eq": PackedFloat64Array(), "niveau": -INF, "lisse": -INF,
				"priorite": priorite, "bandes_db": PackedFloat64Array(), "volume": -80.0,
				"voix": nv, "energie": 0.0}
	_formes["rcs"] = _forme_fixe("rcs", 1.0)


## Part de chaque tiers d'octave dans une boucle de la phase 1 (même couleur de son), fréquences ÷ p.
func _forme_fixe(nom: String, p: float) -> PackedFloat64Array:
	var forme := PackedFloat64Array()
	forme.resize(30)
	var tot := 0.0
	for j in 30:
		var f := Resonances.centre(j)
		var e: float = Synthese.spectre(nom, f / p) * f * Fluides.LARGEUR_TIERS
		forme[j] = e
		tot += e
	for j in 30:
		forme[j] /= maxf(tot, 1e-30)
	return forme


## Forme du spectre d'une couche (30 tiers d'octave, somme = 1), d'après le dernier calcul de la physique.
func _forme(nom: String) -> PackedFloat64Array:
	var source := PackedFloat64Array()
	match nom:
		"structure":
			# le grondement « monte en régime » (phase 6) : il suit la respiration de la chambre à plasma, plus
			# aiguë quand les parois ont chauffé (ionique_son.gd) ; toutes ses fréquences × p ; les résonances,
			# elles, restent celles des panneaux
			var p := ionique.facteur_regime
			if absf(p - _regime_forme) > 0.003 or not _formes.has("structure"):
				_formes["structure"] = _forme_fixe("structure", p)
				_regime_forme = p
			return _formes["structure"]
		"rcs":
			return _formes["rcs"]
		"souffle":
			source = souffle.get("tiers", PackedFloat64Array())
		"jet":
			source = moteurs.tiers_jet
		"jet_rcs":
			source = moteurs.tiers_jet_rcs
		"tension":
			return tension.forme
		"poussiere":
			return poussiere.forme
		"sifflement", "cavites", "tremblement", "choc_verriere":
			return air.formes[nom]
		"plasma", "bobines", "reacteur":
			return ionique.formes[nom]
		_:
			if sol.formes.has(nom):
				return sol.formes[nom]
	var tot := 0.0
	for e in source:
		tot += e
	if tot > 0.0 and source.size() == 30:
		var forme := PackedFloat64Array()
		forme.resize(30)
		for j in 30:
			forme[j] = source[j] / tot
		_formes[nom] = forme
	return _formes.get(nom, PackedFloat64Array())


## Côté d'une couche (cote_son.gd) ; vide = au milieu.
func _cote(nom: String) -> PackedFloat64Array:
	match nom:
		"structure":
			return moteurs.cote_structure
		"rcs":
			return moteurs.cote_rcs
		"jet":
			return moteurs.cote_jet
		"jet_rcs":
			return moteurs.cote_jet_rcs
		"tension":
			return tension.cote
		"tremblement":
			return air.cote_tremblement
		"plasma":
			return moteurs.cote_structure   # même poids que le grondement de chaque moteur (∝ force², même chemin)
	return PackedFloat64Array()


## Sons purs d'une couche : [[n° de raie, Hz, part de l'énergie de la couche (, part à gauche)]].
func _raies_de(nom: String) -> Array:
	if sol.raies.has(nom):
		return sol.raies[nom]
	if air.raies.has(nom):
		return air.raies[nom]
	return ionique.raies.get(nom, [])


## Battement du grondement : énergie × (1 + 0,18 s(t))² / (1 + 0,18²), s = 6 ondes lentes de 2 à 10 Hz
## (valeur efficace 1, moyenne 0 : le niveau moyen ne change pas).
func _facteur_battement(t: float) -> float:
	var s := 0.0
	for o in _battement:
		s += float(o[2]) * sin(TAU * float(o[0]) * t + float(o[1]))
	var m := 1.0 + BATTEMENT * s * _norme_battement
	return m * m / (1.0 + BATTEMENT * BATTEMENT)


## Donne aux voix C++ l'énergie voulue dans chaque tiers d'octave ; les démarre et les arrête.
func _envoyer_voix() -> void:
	if banc:
		_envoyer_banc()
		return
	for nv in voix_directes:
		var vd: Dictionary = voix_directes[nv]
		var e30: PackedFloat32Array = vd["bandes"]
		e30.fill(0.0)
		var d30: PackedFloat64Array = vd["ecarts"]   # énergie à gauche en plus de la moitié (couches de côté)
		var de_cote := false
		var total := 0.0
		if not vd.has("e_raies"):
			for cle in ["e_raies", "f_raies", "g_raies"]:
				var a := PackedFloat32Array()
				a.resize(RAIES_VOIX)
				vd[cle] = a
		var e_raies: PackedFloat32Array = vd["e_raies"]
		var f_raies: PackedFloat32Array = vd["f_raies"]
		var g_raies: PackedFloat32Array = vd["g_raies"]
		var utilisees := false
		if vd.get("raies_utilisees", false):
			e_raies.fill(0.0)
			f_raies.fill(0.0)
			g_raies.fill(0.5)
		for nom in vd["couches"]:
			var en: float = couches[nom]["energie"]
			if en <= 0.0:
				continue
			if nom == "structure":
				en *= _facteur_battement(capteurs.temps)
			elif nom == "tremblement":
				en *= air.facteur_tremblement   # le choc qui va et vient (phase 5)
			elif nom == "plasma":
				en *= ionique.facteur_respiration   # l'ionisation se fait par vagues irrégulières (phase 6)
			var forme := _forme(nom)
			if forme.size() != 30:
				continue
			# sons purs de la couche (sifflement de la pompe, pneu qui crisse, bobines) : leur part de l'énergie
			var reste := 1.0
			for r in _raies_de(nom):
				var n := int(r[0])
				if n < 0 or n >= RAIES_VOIX:
					continue
				e_raies[n] += en * float(r[2])
				f_raies[n] = float(r[1])
				utilisees = utilisees or en * float(r[2]) > 0.0
				if r.size() > 3:
					g_raies[n] = float(r[3])   # phase 6 : chaque son pur a son côté
				reste -= float(r[2])
			reste = maxf(reste, 0.0)
			var cote := _cote(nom)
			if cote.is_empty():
				for j in 30:
					e30[j] += en * reste * forme[j]
			else:
				if not de_cote:
					d30.fill(0.0)
				de_cote = true
				for j in 30:
					var b: int = OCTAVE_DE[j]
					var e := en * reste * forme[j] * cote[CoteSon.OCTAVES + b]
					e30[j] += e
					d30[j] += e * (cote[b] - 0.5)
			total += en
		var flux = vd["flux"]
		if utilisees or vd.get("raies_utilisees", false):
			if flux.has_method("regler_raies"):
				flux.regler_raies(f_raies, e_raies, g_raies)   # les 24 sons purs en un appel
			else:
				for r in 8:
					flux.regler_raie(r, f_raies[r] if f_raies[r] > 0.0 else 1000.0, e_raies[r])
		vd["raies_utilisees"] = utilisees
		if (de_cote or vd.get("de_cote", false)) and flux.has_method("regler_gauche"):
			# un côté n'est renvoyé que s'il a bougé d'au moins 1 % (0,2 dB) : entre deux, la partie C++ garde le sien
			# et n'a pas de rampe à suivre (boucle plus légère)
			var parts: PackedFloat32Array = vd["parts_gauche"]
			var change := false
			for j in 30:
				var w := 0.5 + d30[j] / e30[j] if de_cote and e30[j] > 0.0 else 0.5
				if absf(w - 0.5) <= 0.02:
					w = 0.5   # au milieu : moins de 0,35 dB d'écart, l'oreille ne fait pas la différence (≈ 0,5 dB)
				if absf(w - parts[j]) > 0.01 or (w == 0.5 and parts[j] != 0.5):
					parts[j] = w
					change = true
			if change:
				flux.regler_gauche(parts)
				vd["parts_gauche"] = parts   # (un PackedFloat32Array se copie : on le range de nouveau)
		vd["de_cote"] = de_cote
		if nv == "structure":
			var r: Array = resonances.partager(e30)
			flux.regler_bandes(r[0])
			flux.regler_energie_modes(r[1])
		else:
			flux.regler_bandes(e30)
		var l := vd["lecteur"] as AudioStreamPlayer
		if hors_ligne:
			continue
		if total > 0.0:
			if not l.playing:
				l.play()   # le C++ part du silence et monte en ~10 ms : pas de clic
		elif l.playing and (fondu <= 0.0 or flux.est_silencieux()):
			l.stop()       # seulement quand tout s'est tu (résonances comprises) ou que le silence est demandé


func _envoyer_banc() -> void:
	# 16 chocs à la fois (coque qui tape, 20 modes et des grains), calculés à −30 dB mais joués à −80 dB (inaudibles)
	if chocs != null:
		lecteur_chocs.volume_db = -80.0
		var t := capteurs.temps
		_chocs_en_cours = _chocs_en_cours.filter(func(ch): return float(ch[0]) > t)
		while _chocs_en_cours.size() < LECTEURS:
			var r := Chocs.recette("coque_choc", 0.9, 1e-3, _rng)
			if not lecteur_chocs.playing and not hors_ligne:
				lecteur_chocs.play()
			chocs.frapper(r["modes"], r["options"])
			_chocs_en_cours.append([t + float(r["duree"]), 0])
	for nv in voix_directes:
		var vd: Dictionary = voix_directes[nv]
		var e30 := PackedFloat32Array()
		e30.resize(30)
		e30.fill(0.01)
		vd["flux"].regler_bandes(e30)
		if nv == "structure":
			var em := PackedFloat32Array()
			em.resize(resonances.frequences.size())
			em.fill(0.01)
			vd["flux"].regler_energie_modes(em)
		if vd["flux"].has_method("regler_raies"):
			# les 24 sons purs, chacun de son côté (le cas le plus cher)
			var f := PackedFloat32Array()
			var e := PackedFloat32Array()
			var g := PackedFloat32Array()
			for r in RAIES_VOIX:
				f.append(150.0 * (r + 1))
				e.append(0.01 / RAIES_VOIX)
				g.append(0.3 if r % 2 == 0 else 0.7)
			vd["flux"].regler_raies(f, e, g)
		else:
			for r in 2:
				vd["flux"].regler_raie(r, 400.0 * (r + 1), 0.01)
		var l := vd["lecteur"] as AudioStreamPlayer
		l.volume_db = -80.0
		if not l.playing and not hors_ligne:
			l.play()


## Part d'un cœur du processeur prise par les voix C++ (fil audio) depuis la dernière remise à zéro.
func charge_fil_audio() -> float:
	var ch := 0.0
	for nv in voix_directes:
		ch += float(voix_directes[nv]["flux"].mesures()["charge"])
	if chocs != null:
		ch += float(chocs.mesures()["charge"])
	return ch


func remettre_mesures_fil_audio() -> void:
	for nv in voix_directes:
		voix_directes[nv]["flux"].remettre_mesures()
	if chocs != null:
		chocs.remettre_mesures()


## L'état du jeu, à donner à chaque image.
func regler(en_pause: bool, acceleration: int, vue_cockpit: bool) -> void:
	pause = en_pause
	acc_temps = acceleration
	vue_interieure = vue_cockpit


## Le son est-il permis maintenant ? (sinon : fondu au silence)
func son_permis() -> bool:
	return not pause and acc_temps <= TEMPS_MAX_SON and not capteurs.ecrase


func _physics_process(delta: float) -> void:
	if not actif:
		return
	var t0 := Time.get_ticks_usec()
	capteurs.lire(vaisseau, delta)
	if son_permis():
		moteurs.detecter(capteurs, oreille)
		for e in moteurs.evenements:
			var d := [e[0], e[1], e[2], MOTEUR, 0.0, float(e[4]) if e.size() > 4 else 0.5]
			if e[0] == "moteur_allumage":
				# phase 6 : le plasma s'amorce quand le champ des bobines est là (le « clac » du contacteur d'abord)
				_amorcages.append([d, int(e[3]), capteurs.temps + IoniqueSon.ATTENTE_AMORCAGE])
			else:
				_demandes.append(d)
		sol.detecter(capteurs, oreille, delta)
		for e in sol.evenements:
			_demandes.append([e[0], e[1], e[2], PRIORITE_CHOC.get(e[0], CHOC), 0.0, float(e[4])])
		tension.detecter(capteurs, oreille, delta)
		poussiere.detecter(capteurs, oreille, delta)
		for e in tension.evenements + poussiere.evenements:
			_demandes.append([e[0], e[1], e[2], PRIORITE_CHOC.get(e[0], TENSION), 0.0, float(e[4]), float(e[6])])
	else:
		sol.detecter(capteurs, oreille, delta)   # garde son état à jour (pas de vieux choc au retour du son)
		tension.detecter(capteurs, oreille, delta)   # la mémoire des charges (effet Kaiser) continue
	moteurs.evenements.clear()
	sol.evenements.clear()
	tension.evenements.clear()
	poussiere.evenements.clear()
	# phase 6 : l'intérieur des moteurs avance au rythme de la physique (temps de l'univers depuis la photo précédente :
	# rien en pause, × le temps accéléré), comme la poussée qu'il accompagne ; il claque ses contacteurs
	ionique.avancer(capteurs, oreille, capteurs.temps_physique, son_permis(), moteurs.attenuation)
	for e in ionique.evenements:
		_demandes.append([e[0], e[1], e[2], PRIORITE_CHOC.get(e[0], MOTEUR), 0.0, float(e[4]), float(e[6])])
	ionique.evenements.clear()
	if not son_permis():
		_amorcages.clear()
	elif not _amorcages.is_empty():
		var restent := []
		for a in _amorcages:
			if ionique.amorce(int(a[1])) or capteurs.temps >= float(a[2]):
				_demandes.append(a[0])
			else:
				restent.append(a)
		_amorcages = restent
	_us_physique += Time.get_ticks_usec() - t0


func _process(delta: float) -> void:
	if not actif:
		return
	var t0 := Time.get_ticks_usec()
	mettre_a_jour(delta)
	var us := Time.get_ticks_usec() - t0 + _us_physique
	_us_physique = 0
	ms_par_image = lerpf(ms_par_image, us / 1000.0, 0.05)


## Une image du chef d'orchestre (60 fois par seconde).
func mettre_a_jour(delta: float) -> void:
	# 1. silence demandé ? fondu de 0,1 s
	fondu = move_toward(fondu, 1.0 if son_permis() else 0.0, delta / FONDU_SILENCE)
	var fondu_db := 20.0 * log(maxf(fondu, 1e-4)) / log(10.0)
	_air_cabine()
	# 2. ce que le pilote entend, en dB dans le cockpit
	var c := capteurs
	var z_ext := c.densite * Fluides.vitesse_son(c.temperature) if c.densite > 0.0 else 0.0
	if c.densite <= 0.0:
		_transm = PackedFloat64Array()
		_z_ext = -1.0
	elif absf(z_ext - _z_ext) > 0.002 * z_ext or _transm.is_empty():
		# passage par la paroi : il dépend un peu de l'air du dehors (refait quand il change de 0,2 %)
		_transm = Fluides.transmissions(z_ext)
		_z_ext = z_ext
	# la tête du pilote : en vue cockpit, celle de la caméra ; dehors, droite (l'oreille reste celle du pilote)
	tete = camera.transform.basis.orthonormalized() if vue_interieure and camera != null and camera.get_parent() == pilote \
		else Basis.IDENTITY
	moteurs.tete = tete
	tension.tete = tete
	moteurs.calculer(c, oreille, _transm)
	var mach := c.vitesse_air / Fluides.vitesse_son(c.temperature) if c.densite > 0.0 else 0.0
	souffle = Fluides.souffle(c.densite, c.temperature, c.vitesse_air, mach, c.temperature_coque, _transm) if c.densite > 0.0 \
		else {"niveau": -INF, "bandes": PackedFloat64Array(), "q": 0.0, "p_paroi": 0.0, "turbulent": 0.0, "fluide": 0.0}
	_poser("structure", moteurs.niveau_structure, delta)
	_poser("rcs", moteurs.niveau_rcs, delta)
	_poser("jet", moteurs.niveau_jet, delta)
	_poser("jet_rcs", moteurs.niveau_jet_rcs, delta)
	_poser("souffle", float(souffle["niveau"]), delta)
	sol.calculer(c, oreille)
	for nom in COUCHES_SOL:
		_poser(nom, float(sol.niveaux[nom]), delta)
	tension.calculer(c)
	_poser("tension", tension.niveau, delta)
	poussiere.calculer(c)
	_poser("poussiere", poussiere.niveau, delta)
	air.tete = tete
	air.calculer(c, oreille, _transm, delta)
	for nom in COUCHES_PHASE5:
		_poser(nom, float(air.niveaux[nom]), delta)
	ionique.tete = tete
	ionique.calculer(c, oreille, moteurs.attenuation, delta)
	for nom in COUCHES_PHASE6:
		_poser(nom, float(ionique.niveaux[nom]), delta)
	# 3. compression : du vrai niveau total au volume des haut-parleurs
	var total := _somme_db(couches.values().map(func(k): return float(k["lisse"])))
	var cible := 0.0
	if total > -INF:
		cible = minf(sortie(total), PLAFOND) - (total - ZERO_DBFS)
		cible = minf(cible, 0.0)
	var tau := ATTAQUE if cible < gain else RELACHE
	gain += (cible - gain) * clampf(delta / tau, 0.0, 1.0)
	# 4. chaque couche : volume, égaliseur, silence si trop faible ou cachée
	_preparer_masquage()
	for nom in couches:
		_jouer_couche(nom, fondu_db)
	if synthese_directe:
		_envoyer_voix()
	elif couches.has("structure"):
		# le grondement « monte en régime » : il suit la chambre à plasma (phase 6, ionique_son.gd)
		(couches["structure"]["lecteur"] as AudioStreamPlayer).pitch_scale = ionique.facteur_regime
	# 5. sons brefs
	_servir_demandes(delta, fondu_db)
	# 6. l'oreille suit la tête du pilote en vue cockpit ; dehors, elle reste à sa place, tête droite
	if ecoute:
		if vue_interieure and camera != null and camera.get_parent() == pilote:
			ecoute.transform = camera.transform
		else:
			ecoute.transform = Transform3D(Basis.IDENTITY, oreille_scene)


## Niveau de sortie (dB pleine échelle) pour un niveau x (dB dans le cockpit), avant le plafond.
static func sortie(x: float) -> float:
	if x <= GENOU:
		return x - ZERO_DBFS
	return GENOU - ZERO_DBFS + (x - GENOU) / TAUX_COMPRESSION


## Niveau cible d'une couche ; il monte tout de suite, il descend en ~60 ms (pas de marches audibles).
func _poser(nom: String, niveau: float, delta: float) -> void:
	if not couches.has(nom):
		return
	var k: Dictionary = couches[nom]
	k["niveau"] = niveau
	var l: float = k["lisse"]
	if niveau >= l or l == -INF:
		l = niveau
	else:
		var bas := maxf(niveau, -40.0)
		l = l + (bas - l) * clampf(delta / RELACHE_COUCHE, 0.0, 1.0)
		if niveau == -INF and l < -30.0:
			l = -INF
	k["lisse"] = l
	# part de chaque octave (pour le masquage et l'égaliseur)
	var bdb := PackedFloat64Array()
	bdb.resize(10)
	var parts: PackedFloat64Array = k["parts"]
	var spectre := PackedFloat64Array()
	if nom == "souffle":
		spectre = souffle.get("bandes", PackedFloat64Array())
	elif nom == "jet":
		spectre = moteurs.bandes_jet
	elif nom == "jet_rcs":
		spectre = moteurs.bandes_jet_rcs
	elif sol.formes.has(nom):
		spectre = SolSon.octaves(sol.formes[nom])
	elif nom in COUCHES_PHASE6:
		# la forme ne change que quand ionique_son.gd refait la couche : octaves gardées tant qu'elle ne bouge pas
		var forme := _forme(nom)
		if not is_same(k.get("forme_vue"), forme):
			k["forme_vue"] = forme
			k["octaves_vues"] = SolSon.octaves(forme)
		spectre = k["octaves_vues"]
	elif nom in COUCHES_PHASE4 or nom in COUCHES_PHASE5:
		spectre = SolSon.octaves(_forme(nom))
	var tot := 0.0
	for e in spectre:
		tot += e
	for b in 10:
		var part: float = spectre[b] / tot if tot > 0.0 else parts[b]
		bdb[b] = l + 10.0 * log(maxf(part, 1e-12)) / log(10.0) if l > -INF else -INF
	k["bandes_db"] = bdb


func _jouer_couche(nom: String, fondu_db: float) -> void:
	var k: Dictionary = couches[nom]
	var l := k["lecteur"] as AudioStreamPlayer
	var niveau: float = k["lisse"]
	var dbfs := niveau - ZERO_DBFS + gain + fondu_db
	var audible := niveau > -INF and dbfs > SEUIL_DB and not _masquee(nom)
	if k.has("voix"):
		# phase 2 : la couche ne fait que donner son énergie (pleine échelle) ; sa voix C++ la joue
		k["energie"] = pow(10.0, dbfs / 10.0) if audible else 0.0
		k["volume"] = dbfs if audible else -80.0
		return
	if not audible:
		if l.playing:
			l.stop()
		k["volume"] = -80.0
		return
	var realise: float = k["ref_dbfs"]
	var eq: AudioEffectEQ10 = k["eq"]
	if eq != null:
		# égaliseur : chaque octave reçoit l'écart entre le spectre voulu et celui de la boucle
		var bdb: PackedFloat64Array = k["bandes_db"]
		var parts: PackedFloat64Array = k["parts"]
		var g_max := -INF
		var g := PackedFloat64Array()
		g.resize(10)
		for b in 10:
			g[b] = bdb[b] - (niveau + 10.0 * log(maxf(parts[b], 1e-12)) / log(10.0))
			g_max = maxf(g_max, g[b])
		for b in 10:
			var gb := clampf(g[b] - g_max, -60.0, 0.0)
			eq.set_band_gain_db(b, gb)
			g[b] = pow(10.0, gb / 20.0)
		# ce qui sort vraiment (les bandes de Godot se recouvrent : egaliseur.gd)
		realise += 10.0 * log(maxf(Egaliseur.energie(k["m_eq"], g), 1e-12)) / log(10.0)
	var vol := dbfs - realise
	k["volume"] = vol
	l.volume_db = vol
	if not l.playing:
		var d := (l.stream as AudioStreamWAV).get_length() if l.stream is AudioStreamWAV else 0.0
		l.play(_rng.randf() * d)   # départ au hasard dans la boucle


## Les deux couches les plus fortes de chaque octave (une fois par image : la plus forte des AUTRES couches s'en déduit).
func _preparer_masquage() -> void:
	_fort1.fill(-INF)
	_fort2.fill(-INF)
	_qui1.fill(-1)
	var n := 0
	for nom in couches:
		var o: PackedFloat64Array = couches[nom]["bandes_db"]
		if o.size() == 10:
			for b in 10:
				var x := o[b]
				if x > _fort1[b]:
					_fort2[b] = _fort1[b]
					_fort1[b] = x
					_qui1[b] = n
				elif x > _fort2[b]:
					_fort2[b] = x
		couches[nom]["rang"] = n
		n += 1


var _fort1 := PackedFloat64Array([-INF, -INF, -INF, -INF, -INF, -INF, -INF, -INF, -INF, -INF])
var _fort2 := PackedFloat64Array([-INF, -INF, -INF, -INF, -INF, -INF, -INF, -INF, -INF, -INF])
var _qui1 := PackedInt32Array([-1, -1, -1, -1, -1, -1, -1, -1, -1, -1])


## Une couche est cachée si, dans toutes les octaves où elle compte, une autre est 20 dB plus forte.
func _masquee(nom: String) -> bool:
	var k: Dictionary = couches[nom]
	var a: PackedFloat64Array = k["bandes_db"]
	var lvl: float = k["lisse"]
	if a.size() != 10:
		return false
	if not k.has("rang"):
		_preparer_masquage()
	var rang: int = k["rang"]
	for b in 10:
		if a[b] < lvl - 10.0:
			continue   # octave qui compte peu pour cette couche
		var autre := _fort2[b] if _qui1[b] == rang else _fort1[b]   # la plus forte des autres couches
		if not autre > a[b] + MASQUAGE_DB:
			return false
	return true


func _servir_demandes(delta: float, fondu_db: float) -> void:
	var t := capteurs.temps
	# chocs finis (d'après leur durée calculée) ; silence demandé : tout s'éteint en 30 ms
	var restent_chocs := []
	for ch in _chocs_en_cours:
		if float(ch[0]) > t and fondu > 0.0:
			restent_chocs.append(ch)
	if fondu <= 0.0 and not _chocs_en_cours.is_empty() and chocs != null:
		chocs.couper()
	_chocs_en_cours = restent_chocs
	for d in _demandes:
		var nom: String = d[0]
		if chocs == null or not Chocs.existe(nom) or fondu < 0.999:
			oublies += 1
			continue
		var niveau: float = d[1]
		var dbfs := niveau - ZERO_DBFS + gain + fondu_db + _rng.randf_range(-1.0, 1.0)
		if dbfs < SEUIL_DB:
			oublies += 1
			continue
		var g := Chocs.panoramique(oreille + tete.inverse() * (d[2] - oreille), oreille)
		var r := Chocs.recette(nom, float(d[5]), pow(10.0, dbfs / 10.0), _rng, g.x, g.y, float(d[3]), float(d[6]) if d.size() > 6 else 0.0)
		if _coup_cache(niveau, r["parts"]):
			oublies += 1
			continue
		# 16 chocs à la fois : sinon le moins important (puis le plus ancien) laisse la place, s'il l'est moins
		if _chocs_en_cours.size() >= LECTEURS:
			var victime := -1
			for k in _chocs_en_cours.size():
				var p := int(_chocs_en_cours[k][1])
				if p <= int(d[3]) and (victime < 0 or p < int(_chocs_en_cours[victime][1])):
					victime = k
			if victime < 0:
				oublies += 1
				continue
			_chocs_en_cours.remove_at(victime)
		if hors_ligne or lecteur_chocs.playing or _demarrer_chocs():
			chocs.frapper(r["modes"], r["options"])
		_chocs_en_cours.append([t + float(r["duree"]), int(d[3])])
		joues += 1
	_demandes.clear()


func _demarrer_chocs() -> bool:
	if lecteur_chocs == null:
		return false
	lecteur_chocs.play()
	return true


## Un son bref est caché si, dans sa plus forte octave, les couches continues sont 20 dB plus fortes.
func _coup_cache(niveau: float, parts: PackedFloat64Array) -> bool:
	var b_max := 0
	for b in 10:
		if parts[b] > parts[b_max]:
			b_max = b
	var e := 0.0
	for nom in couches:
		var o: PackedFloat64Array = couches[nom]["bandes_db"]
		if o.size() == 10 and o[b_max] > -INF:
			e += pow(10.0, o[b_max] / 10.0)
	if e <= 0.0 or parts[b_max] <= 0.0:
		return false
	return niveau + 10.0 * log(parts[b_max]) / log(10.0) < 10.0 * log(e) / log(10.0) - MASQUAGE_DB


## Nombre de voix qui jouent en ce moment (couches + sons brefs ; une voix C++ compte une fois).
func voix_actives() -> int:
	var n := 0
	var vus := {}
	for nom in couches:
		var l := couches[nom]["lecteur"] as AudioStreamPlayer
		if l.playing and not vus.has(l):
			vus[l] = true
			n += 1
	return n + _chocs_en_cours.size()


static func _somme_db(niveaux: Array) -> float:
	var e := 0.0
	for x in niveaux:
		if x > -INF:
			e += pow(10.0, x / 10.0)
	return 10.0 * log(e) / log(10.0) if e > 0.0 else -INF
