extends RefCounted
## Résonances du cockpit (moteur audio, phase 2) : par où passe le grondement qui vient de la structure.
##
## Le grondement des moteurs et le souffle des petits propulseurs arrivent au pilote par la structure. Le son
## qu'il entend, ce sont les panneaux d'aluminium du cockpit (plancher, parois, tableau de bord, cloison
## arrière) qui vibrent et font vibrer l'air de la cabine. Or un panneau ne vibre pas pareil à toutes les
## fréquences : il a ses fréquences propres (ses « modes »), comme une peau de tambour.
##  - En grave, les modes sont espacés : chacun s'entend comme un petit « bourdon » qui met du temps à monter
##    et à s'éteindre (durée 1 / (π f η), η = facteur de perte, ici 1 % pour une structure rivetée).
##  - Plus haut, ils deviennent si nombreux qu'ils se chevauchent (« recouvrement modal » M = f η n, n = nombre
##    de modes par hertz) : le son redevient un bruit lisse. Pour ces panneaux, M = 1 vers 300 Hz.
## Ici : fréquences des modes d'une plaque appuyée sur ses bords (formule des plaques de Kirchhoff),
## pour chaque panneau ; on garde les 32 plus graves (la partie C++ en fait vibrer jusqu'à 32).
## Dans chaque tiers d'octave qui contient des modes, la part 1 / (1 + M) de l'énergie passe par eux, le reste
## par le bruit lisse (même énergie au total : le niveau calculé par la physique ne change pas).
##
## Dimensions et épaisseurs : valeurs habituelles d'une cellule d'avion de chasse (peau de 2 à 3 mm entre les
## cadres), à régler à l'oreille. Aucun effet sur la physique.

const E_ALU := 70.0e9           # Pa : module d'Young de l'aluminium
const RHO_ALU := 2700.0         # kg/m³
const NU_ALU := 0.33            # coefficient de Poisson
const PERTE := 0.01             # facteur de perte d'une structure rivetée (0,5 à 2 %)
const MODES_MAX := 32
const ECART_FABRICATION := 0.04 # deux panneaux « pareils » ne sont jamais identiques (±4 %)
## [nom, longueur (m), largeur (m), épaisseur (m), nombre de panneaux pareils]
const PANNEAUX := [
	["plancher", 0.55, 0.40, 0.0025, 4],
	["parois", 0.45, 0.35, 0.0020, 4],
	["tableau de bord", 0.60, 0.25, 0.0030, 2],
	["cloison arrière", 0.55, 0.45, 0.0025, 2],
]
const BANDES := 30

var frequences := PackedFloat32Array()   # Hz, de la plus grave à la plus aiguë
var pertes := PackedFloat32Array()
var bande_du_mode := PackedInt32Array()  # tiers d'octave de chaque mode (0 à 29)
var part_modes := PackedFloat64Array()   # par tiers d'octave : part de l'énergie qui passe par les modes
var modes_par_bande := PackedInt32Array()
var densite := 0.0                       # modes par hertz de tous les panneaux
var noms := PackedStringArray()


func _init() -> void:
	calculer()


## Vitesse « de flexion » √(D / ρh) d'une plaque d'épaisseur h (m²/s).
static func raideur(h: float) -> float:
	return h * sqrt(E_ALU / (12.0 * (1.0 - NU_ALU * NU_ALU) * RHO_ALU))


## Fréquence du mode (m, n) d'une plaque a × b appuyée sur ses bords.
static func frequence_plaque(a: float, b: float, h: float, m: int, n: int) -> float:
	return PI / 2.0 * raideur(h) * (pow(m / a, 2.0) + pow(n / b, 2.0))


## Centre du tiers d'octave j (comme la partie C++ : 31,25 Hz × 2^((j − 1) / 3)).
static func centre(j: int) -> float:
	return 31.25 * pow(2.0, (j - 1) / 3.0)


static func bande(f: float) -> int:
	return clampi(int(floor(3.0 * log(f / 31.25) / log(2.0) + 1.0 + 0.5)), 0, BANDES - 1)


func calculer() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	var tous := []   # [f, nom]
	densite = 0.0
	for p in PANNEAUX:
		var a: float = p[1]
		var b: float = p[2]
		var h: float = p[3]
		# densité de modes d'une plaque : n = A / (2 √(D/ρh)) modes par hertz
		densite += float(p[4]) * a * b / (2.0 * raideur(h))
		for k in int(p[4]):
			var ecart := 1.0 + rng.randf_range(-ECART_FABRICATION, ECART_FABRICATION)
			for m in range(1, 6):
				for n in range(1, 6):
					var f := frequence_plaque(a, b, h, m, n) * ecart
					if f < 2000.0:
						tous.append([f, "%s %d (%d,%d)" % [p[0], k + 1, m, n]])
	tous.sort_custom(func(x, y): return float(x[0]) < float(y[0]))
	var n_modes := mini(MODES_MAX, tous.size())
	frequences.resize(n_modes)
	pertes.resize(n_modes)
	bande_du_mode.resize(n_modes)
	noms.resize(n_modes)
	modes_par_bande.resize(BANDES)
	modes_par_bande.fill(0)
	for i in n_modes:
		frequences[i] = tous[i][0]
		pertes[i] = PERTE
		bande_du_mode[i] = bande(tous[i][0])
		noms[i] = tous[i][1]
		modes_par_bande[bande_du_mode[i]] += 1
	# vrais modes par bande (tous les panneaux) : la part gardée ne porte que la part qui lui revient
	var vrais := PackedInt32Array()
	vrais.resize(BANDES)
	vrais.fill(0)
	for t in tous:
		vrais[bande(float(t[0]))] += 1
	part_modes.resize(BANDES)
	for j in BANDES:
		if modes_par_bande[j] == 0:
			part_modes[j] = 0.0
			continue
		var recouvrement := centre(j) * PERTE * densite
		part_modes[j] = float(modes_par_bande[j]) / float(maxi(vrais[j], modes_par_bande[j])) / (1.0 + recouvrement)


## Fréquence où les modes se chevauchent (M = 1).
func frequence_recouvrement() -> float:
	return 1.0 / (PERTE * densite)


## Partage d'un spectre (énergie par tiers d'octave) entre le bruit lisse et les modes.
## Renvoie [énergies du bruit (30), énergies des modes (n)].
func partager(bandes_e: PackedFloat32Array) -> Array:
	var bruit := bandes_e.duplicate()
	var modes := PackedFloat32Array()
	modes.resize(frequences.size())
	for i in frequences.size():
		var j := bande_du_mode[i]
		modes[i] = bandes_e[j] * part_modes[j] / modes_par_bande[j]
	for j in BANDES:
		bruit[j] = bandes_e[j] * (1.0 - part_modes[j])
	return [bruit, modes]
