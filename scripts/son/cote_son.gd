extends RefCounted
## D'où vient un son continu (phase 4, demande de Gwenaël : « qu'on entende de quel côté vient le propulseur »).
##
## Dans le cockpit, le son d'un propulseur arrive par la coque, depuis son point de fixation : les parois du
## cockpit de son côté vibrent un peu plus fort (PROCHE_DB), puis la tête fait de l'ombre à l'oreille d'en face.
## Cette ombre est forte dans les aigus (la tête est grande devant leur longueur d'onde) et presque nulle dans
## les graves (le son en fait le tour) : 0 dB sous 300 Hz, OMBRE_TETE_DB au-dessus de 3 kHz. Un son venu de
## derrière perd un peu d'aigus (le pavillon de l'oreille le cache : DOS_DB au-dessus de 5,6 kHz).
## Il manque une chose : en vrai, un son venu de gauche arrive aussi un peu plus tôt à l'oreille gauche (jusqu'à
## 0,65 ms), et c'est surtout ce décalage que l'oreille écoute dans les graves. Ici les deux oreilles ne sont pas
## décalées (le cockpit, qui résonne, les rend déjà un peu différentes) : on remplace ce décalage par l'écart de
## volume que l'oreille juge équivalent (environ 1 dB pour 30 à 50 µs), TEMPS_DB, sous 800 Hz, qui s'efface vers
## 3 kHz (au-delà, l'oreille n'écoute plus le décalage).
## Les deux oreilles se partagent l'énergie (gauche + droite = 2 × l'énergie, comme avant) : rien ne devient plus fort.
## Tout est calculé dans le repère de la tête : si le pilote tourne la tête, le son tourne avec le cockpit.
##
## Pour chaque source, une petite table de 20 nombres (10 octaves de Fluides.BANDES) : la part de l'énergie
## à gauche (0,5 = au milieu), puis le facteur d'énergie (1, ou moins pour un son venu de derrière).
## Une couche (tous les moteurs, tous les petits propulseurs…) additionne ses sources avec cumuler(), puis
## finir() donne sa table à elle, que le chef d'orchestre passe à la partie C++ (SyntheSon.regler_gauche).

const Fluides = preload("res://scripts/son/fluides_son.gd")

const OMBRE_TETE_DB := 8.0       # dB : écart des deux oreilles dans les aigus, pour un son tout à fait de côté
const TEMPS_DB := 6.0             # dB : à la place du décalage de temps entre les oreilles (graves et médiums)
const PROCHE_STRUCTURE_DB := 3.0  # dB : les parois de son côté vibrent plus fort (son venu par la coque)
const PROCHE_AIR_DB := 2.0        # dB : la partie de la verrière tournée vers le jet le laisse mieux passer
const DOS_DB := 5.0               # dB perdus dans les aigus par un son venu de derrière
const OCTAVES := 10


## Table de la source en « pos » (repère du modèle), oreille en « oreille », tête tournée de « tete ».
static func table(pos: Vector3, oreille: Vector3, tete: Basis, proche_db: float) -> PackedFloat64Array:
	var t := PackedFloat64Array()
	t.resize(2 * OCTAVES)
	var d := tete.inverse() * (pos - oreille)
	var r := d.length()
	var cote := clampf(d.x / r, -1.0, 1.0) if r > 0.05 else 0.0   # + : à droite
	var dos := clampf(d.z / r, 0.0, 1.0) if r > 0.05 else 0.0     # + : derrière (l'avant est vers −z)
	for b in OCTAVES:
		var f: float = Fluides.BANDES[b]
		var ombre := clampf(log(f / 300.0) / log(10.0), 0.0, 1.0)
		var temps := clampf(1.0 - log(f / 800.0) / log(3000.0 / 800.0), 0.0, 1.0)
		var ecart := cote * (proche_db + TEMPS_DB * temps + OMBRE_TETE_DB * ombre)   # dB : droite − gauche
		t[b] = 1.0 / (1.0 + pow(10.0, ecart / 10.0))
		t[OCTAVES + b] = pow(10.0, -DOS_DB * dos * clampf(log(f / 2000.0) / log(2.0) / 1.5, 0.0, 1.0) / 10.0)
	return t


## Ajoute une source d'énergie e (n'importe quelle unité) à l'accumulateur acc (20 nombres : énergie à gauche,
## puis énergie, par octave).
static func cumuler(acc: PackedFloat64Array, t: PackedFloat64Array, e: float) -> void:
	for b in OCTAVES:
		var eb := e * t[OCTAVES + b]
		acc[b] += eb * t[b]
		acc[OCTAVES + b] += eb


## Table de la couche : part à gauche et facteur d'énergie de chaque octave (total = Σ e des sources).
static func finir(acc: PackedFloat64Array, total: float) -> PackedFloat64Array:
	var t := PackedFloat64Array()
	t.resize(2 * OCTAVES)
	for b in OCTAVES:
		var eb := acc[OCTAVES + b]
		t[b] = acc[b] / eb if eb > 0.0 else 0.5
		t[OCTAVES + b] = eb / total if total > 0.0 else 1.0
	return t


static func vide() -> PackedFloat64Array:
	var a := PackedFloat64Array()
	a.resize(2 * OCTAVES)
	a.fill(0.0)
	return a


## Au milieu, rien de changé (couches qui viennent de partout : souffle de l'air, poussière, sol…).
static func milieu() -> PackedFloat64Array:
	var t := PackedFloat64Array()
	t.resize(2 * OCTAVES)
	for b in OCTAVES:
		t[b] = 0.5
		t[OCTAVES + b] = 1.0
	return t
