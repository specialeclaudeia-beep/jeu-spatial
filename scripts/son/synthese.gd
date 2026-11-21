extends RefCounted
## Fabrication des sons par le calcul (moteur audio, phase 1). Rien n'est enregistré : chaque son est
## calculé à partir d'une « graine » (le nombre de départ du hasard). Même graine = même son.
##
## Depuis la phase 3, ce fichier ne fabrique plus que les boucles (secours sans la partie C++) ; les sons brefs sont
## fabriqués en direct (scripts/son/chocs.gd et la classe C++ ChocsSon).
## - des boucles de bruit dont on choisit exactement le spectre (la part de chaque fréquence). Elles sont
##   fabriquées directement en fréquences puis ramenées dans le temps (transformée de Fourier inverse) :
##   la fin rejoint parfaitement le début, la boucle ne « claque » jamais ;
##
## Ce fichier ne sert que hors du jeu : outils/generateur_sons.gd l'appelle dans le cloud et écrit les
## fichiers .wav de res://sons/. Le jeu, lui, ne fait que les lire.

const Fluides = preload("res://scripts/son/fluides_son.gd")
const MoteursSon = preload("res://scripts/son/moteurs_son.gd")

const TAUX := 32000          # échantillons par seconde des fichiers (assez pour entendre jusqu'à 16 kHz)
## Centres des 10 bandes d'octave de l'égaliseur de Godot (AudioEffectEQ10).
const BANDES := [31.25, 62.5, 125.0, 250.0, 500.0, 1000.0, 2000.0, 4000.0, 8000.0, 16000.0]
const RMS_BOUCLES := 0.1     # −20 dB pleine échelle : les crêtes du bruit restent sous −6 dB
const CRETE_COUPS := 0.89    # −1 dB pleine échelle

## Les boucles (sons continus). n = nombre d'échantillons (puissance de 2 : 8,2 s ou 4,1 s).
## - souffle : l'air qui frotte sur la coque, entendu à travers la paroi, pour un vol à 150 m/s au niveau
##   de la mer (calcul de fluides_son.gd). En vol, l'égaliseur du jeu corrige, bande par bande, vers le
##   spectre du moment : comme la boucle est déjà proche, ses corrections restent douces (il les fait bien).
## - jet_moteur, jet_rcs : bruit des jets des moteurs (grave, culmine vers 150 Hz) et des petites buses
##   (vers 1,1 kHz), à travers la paroi (calcul de moteurs_son.gd). Leur forme ne change pas en vol.
## - structure : grondement des moteurs transmis par la structure (graves, avec un léger battement).
## - rcs : souffle d'une vanne et d'une buse de petit propulseur (médiums).
const BOUCLES := {
	"souffle": {"n": 262144, "graine": 1101, "spectre": "souffle", "modulation": 0.0},
	"jet_moteur": {"n": 262144, "graine": 1202, "spectre": "jet_moteur", "modulation": 0.0},
	"jet_rcs": {"n": 131072, "graine": 1505, "spectre": "jet_rcs", "modulation": 0.0},
	"structure": {"n": 131072, "graine": 1303, "spectre": "structure", "modulation": 0.18},
	"rcs": {"n": 131072, "graine": 1404, "spectre": "rcs", "modulation": 0.0},
}
## Spectres des boucles (densité relative à la fréquence f, en Hz).
static var _remous_ref := {}


static func spectre(nom: String, f: float) -> float:
	var passe_haut := pow(f / 20.0, 4.0) / (1.0 + pow(f / 20.0, 4.0))
	var aigus := 1.0 / (1.0 + pow(f / 15000.0, 8.0))
	match nom:
		"souffle":
			if _remous_ref.is_empty():
				_remous_ref = Fluides.remous_reference()
			return passe_haut * aigus * Fluides.forme_souffle(f, _remous_ref)
		"jet_moteur", "jet_rcs":
			var tr := Fluides.transmission(f, 1.225 * 340.3)
			var fp: float = MoteursSon.FP_MOTEUR if nom == "jet_moteur" else MoteursSon.FP_RCS
			return passe_haut * aigus * MoteursSon.forme_jet(f, fp) * tr * tr
		"structure":
			# plat de 25 à 120 Hz, puis −6 dB par octave jusqu'à 1,5 kHz, puis −12
			return passe_haut / (1.0 + pow(f / 120.0, 2.0)) / (1.0 + pow(f / 1500.0, 2.0)) / (1.0 + pow(f / 6000.0, 8.0))
		"rcs":
			# monte jusqu'à 300 Hz, plat jusqu'à 2,5 kHz, puis −12 dB par octave
			var m := pow(f / 300.0, 2.0)
			return passe_haut * m / (1.0 + m) / pow(1.0 + pow(f / 2500.0, 2.0), 2.0) / (1.0 + pow(f / 12000.0, 8.0))
	return 0.0


## Fabrique une boucle. Renvoie [signal, infos].
static func fabriquer_boucle(nom: String) -> Array:
	var b: Dictionary = BOUCLES[nom]
	var forme: String = b["spectre"]
	var r: Array = bruit_spectral(int(b["n"]), func(f: float) -> float: return spectre(forme, f), int(b["graine"]))
	var x: PackedFloat32Array = r[0]
	if float(b["modulation"]) > 0.0:
		var m := modulation(x.size(), float(b["modulation"]), int(b["graine"]) + 7)
		for i in x.size():
			x[i] *= m[i]
	multiplier(x, RMS_BOUCLES / maxf(rms(x), 1e-12))
	return [x, {"fichier": "res://sons/boucles/%s.wav" % nom, "duree": float(x.size()) / TAUX,
		"rms_dbfs": db(rms(x)), "crete_dbfs": db(crete(x)), "bandes": Array(r[1]), "graine": int(b["graine"])}]


## Part de l'énergie d'un signal dans chaque bande d'octave (transformée de Fourier).
static func bandes_octave(x: PackedFloat32Array) -> PackedFloat64Array:
	var n := 1
	while n < x.size():
		n <<= 1
	var re := PackedFloat64Array()
	var im := PackedFloat64Array()
	re.resize(n)
	im.resize(n)
	for i in x.size():
		re[i] = x[i]
	fft(re, im, false)
	var bandes := PackedFloat64Array()
	bandes.resize(BANDES.size())
	var tot := 0.0
	for k in range(1, n / 2):
		var e := re[k] * re[k] + im[k] * im[k]
		bandes[_bande(k * float(TAUX) / n)] += e
		tot += e
	for b in bandes.size():
		bandes[b] /= maxf(tot, 1e-30)
	return bandes


# =====================================================================
# TRANSFORMÉE DE FOURIER (radix 2, sur place)
# =====================================================================
## re, im : parties réelle et imaginaire (taille = puissance de 2). inverse = vers le temps (÷ n).
static func fft(re: PackedFloat64Array, im: PackedFloat64Array, inverse: bool) -> void:
	var n := re.size()
	# permutation « bits inversés »
	var j := 0
	for i in range(1, n):
		var bit := n >> 1
		while j & bit:
			j ^= bit
			bit >>= 1
		j |= bit
		if i < j:
			var t := re[i]
			re[i] = re[j]
			re[j] = t
			t = im[i]
			im[i] = im[j]
			im[j] = t
	var signe := 1.0 if inverse else -1.0
	var taille := 2
	while taille <= n:
		var moitie := taille >> 1
		var pas_angle := signe * TAU / taille
		var wr0 := cos(pas_angle)
		var wi0 := sin(pas_angle)
		var debut := 0
		while debut < n:
			var wr := 1.0
			var wi := 0.0
			for k in moitie:
				var a := debut + k
				var b := a + moitie
				var xr := re[b] * wr - im[b] * wi
				var xi := re[b] * wi + im[b] * wr
				re[b] = re[a] - xr
				im[b] = im[a] - xi
				re[a] += xr
				im[a] += xi
				var nr := wr * wr0 - wi * wi0
				wi = wr * wi0 + wi * wr0
				wr = nr
			debut += taille
		taille <<= 1
	if inverse:
		var inv := 1.0 / n
		for i in n:
			re[i] *= inv
			im[i] *= inv


# =====================================================================
# BOUCLES DE BRUIT AU SPECTRE CHOISI
# =====================================================================
## Bruit de n échantillons (n = puissance de 2) dont la densité spectrale suit spectre(f) (f en Hz,
## valeur relative). Chaque fréquence reçoit un tirage au hasard (loi normale, comme un vrai bruit) :
## le résultat est périodique, donc une boucle parfaite. Renvoie [signal, énergie par bande d'octave].
static func bruit_spectral(n: int, spectre: Callable, graine: int) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = graine
	var re := PackedFloat64Array()
	var im := PackedFloat64Array()
	re.resize(n)
	im.resize(n)
	var bandes := PackedFloat64Array()
	bandes.resize(BANDES.size())
	var df := float(TAUX) / n
	for k in range(1, n / 2):
		var f := k * df
		var a := sqrt(maxf(float(spectre.call(f)), 0.0) * 0.5)
		var r := rng.randfn(0.0, 1.0) * a
		var i := rng.randfn(0.0, 1.0) * a
		re[k] = r
		im[k] = i
		re[n - k] = r      # symétrie : le signal est réel
		im[n - k] = -i
		bandes[_bande(f)] += r * r + i * i
	fft(re, im, true)
	var x := PackedFloat32Array()
	x.resize(n)
	for i in n:
		x[i] = re[i]
	var tot := 0.0
	for e in bandes:
		tot += e
	for b in bandes.size():
		bandes[b] = bandes[b] / maxf(tot, 1e-30)
	return [x, bandes]


## Numéro de la bande d'octave (0 à 9) qui contient la fréquence f.
static func _bande(f: float) -> int:
	return clampi(int(floor(log(f / 31.25) / log(2.0) + 0.5)), 0, BANDES.size() - 1)


## Modulation lente et périodique (même période que la boucle) : quelques ondes de 2 à 10 Hz dont le
## nombre de cycles par boucle est entier. Sert au « battement » d'un grondement de moteur.
static func modulation(n: int, profondeur: float, graine: int) -> PackedFloat32Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = graine
	var duree := float(n) / TAUX
	var comp := []
	for c in 6:
		var cycles := roundi(rng.randf_range(2.0, 10.0) * duree)
		comp.append([cycles, rng.randf() * TAU, rng.randf_range(0.5, 1.0)])
	var m := PackedFloat32Array()
	m.resize(n)
	var somme := 0.0
	for c in comp:
		somme += float(c[2]) * float(c[2])
	var norme := profondeur / sqrt(somme * 0.5)
	for i in n:
		var v := 0.0
		for c in comp:
			v += float(c[2]) * sin(TAU * float(c[0]) * i / n + float(c[1]))
		m[i] = 1.0 + v * norme
	return m


# =====================================================================
# MESURES ET FICHIERS
# =====================================================================
static func rms(x: PackedFloat32Array, debut := 0, fin := -1) -> float:
	if fin < 0:
		fin = x.size()
	var s := 0.0
	for i in range(debut, fin):
		s += x[i] * x[i]
	return sqrt(s / maxi(fin - debut, 1))


static func crete(x: PackedFloat32Array) -> float:
	var c := 0.0
	for v in x:
		c = maxf(c, absf(v))
	return c


static func multiplier(x: PackedFloat32Array, k: float) -> void:
	for i in x.size():
		x[i] *= k


static func db(lin: float) -> float:
	return 20.0 * log(maxf(lin, 1e-12)) / log(10.0)


## Échantillons (−1..1) → entiers 16 bits, avec écrêtage (rare : réglé pour ne presque jamais arriver).
static func en_16_bits(x: PackedFloat32Array) -> PackedByteArray:
	var d := PackedByteArray()
	d.resize(x.size() * 2)
	for i in x.size():
		d.encode_s16(i * 2, clampi(roundi(x[i] * 32767.0), -32768, 32767))
	return d


## Fichier WAV mono 16 bits.
static func ecrire_wav(chemin: String, x: PackedFloat32Array) -> Error:
	var donnees := en_16_bits(x)
	var f := FileAccess.open(chemin, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_buffer("RIFF".to_ascii_buffer())
	f.store_32(36 + donnees.size())
	f.store_buffer("WAVE".to_ascii_buffer())
	f.store_buffer("fmt ".to_ascii_buffer())
	f.store_32(16)
	f.store_16(1)            # PCM
	f.store_16(1)            # mono
	f.store_32(TAUX)
	f.store_32(TAUX * 2)
	f.store_16(2)
	f.store_16(16)
	f.store_buffer("data".to_ascii_buffer())
	f.store_32(donnees.size())
	f.store_buffer(donnees)
	f.close()
	return OK
