extends RefCounted
## Fabrication des sons par le calcul (moteur audio, phase 1). Rien n'est enregistré : chaque son est
## calculé à partir d'une « graine » (le nombre de départ du hasard). Même graine = même son.
##
## Deux sortes de sons :
## - des boucles de bruit dont on choisit exactement le spectre (la part de chaque fréquence). Elles sont
##   fabriquées directement en fréquences puis ramenées dans le temps (transformée de Fourier inverse) :
##   la fin rejoint parfaitement le début, la boucle ne « claque » jamais ;
## - des coups brefs (vanne qui s'ouvre, moteur qui s'allume) : une pièce frappée vibre selon quelques
##   façons propres (ses « modes »), chacune à sa fréquence, et s'éteint plus ou moins vite selon sa
##   matière (synthèse modale).
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
## Les coups brefs, chacun en plusieurs variantes (graines différentes) pour ne jamais rejouer le même.
## perte = facteur de perte (amortissement) de la structure, jonctions comprises ; contact = durée du choc.
const COUPS := {
	# vanne d'un petit propulseur qui s'ouvre : métal contre métal (choc de 0,4 ms) + bouffée de gaz
	"rcs_ouverture": {"variantes": 6, "graine": 2100, "duree": 0.35, "f_min": 180.0, "f_max": 4500.0,
		"modes": 14, "perte": 0.012, "contact": 0.0004, "souffle": 0.5, "souffle_f": 1800.0},
	# la même vanne qui se referme : choc plus bref et plus léger, sans gaz
	"rcs_fermeture": {"variantes": 4, "graine": 2200, "duree": 0.25, "f_min": 400.0, "f_max": 6000.0,
		"modes": 10, "perte": 0.015, "contact": 0.0002},
	# un moteur qui s'allume : la poussée arrive en ~30 ms et fait « sonner » les grandes pièces (graves)
	"moteur_allumage": {"variantes": 3, "graine": 2300, "duree": 1.4, "f_min": 35.0, "f_max": 600.0,
		"modes": 16, "perte": 0.02, "contact": 0.004, "attaque": 0.03},
	# un moteur qui se coupe : la structure, déchargée, se relâche (plus doux, plus lent)
	"moteur_coupure": {"variantes": 3, "graine": 2400, "duree": 1.0, "f_min": 30.0, "f_max": 400.0,
		"modes": 12, "perte": 0.03, "contact": 0.01, "attaque": 0.06},
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


## Fabrique la variante k (0, 1, …) d'un coup. Renvoie [signal, infos].
static func fabriquer_coup(nom: String, k: int) -> Array:
	var c: Dictionary = COUPS[nom]
	var graine := int(c["graine"]) + k
	var x := coup_modal(c, graine)
	multiplier(x, CRETE_COUPS / maxf(crete(x), 1e-12))
	return [x, {"fichier": "res://sons/coups/%s_%d.wav" % [nom, k + 1], "duree": float(x.size()) / TAUX,
		"rms_dbfs": db(rms(x, 0, mini(int(0.1 * TAUX), x.size()))), "crete_dbfs": db(crete(x)),
		"bandes": Array(bandes_octave(x)), "graine": graine}]


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
# COUPS BREFS (SYNTHÈSE MODALE)
# =====================================================================
## Une pièce frappée. p : dictionnaire
##   duree (s), f_min / f_max (Hz) des modes, modes (nombre), perte (facteur de perte de la matière :
##   la durée d'un mode vaut 1 / (π × f × perte)), contact (s : durée du choc, loi de Hertz),
##   souffle (0..1 : part d'un bref bruit de gaz), souffle_f (Hz), attaque (s : montée de la force)
## Renvoie le signal (non normalisé).
static func coup_modal(p: Dictionary, graine: int) -> PackedFloat32Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = graine
	var n := int(float(p["duree"]) * TAUX)
	var x := PackedFloat32Array()
	x.resize(n)
	var nb: int = p["modes"]
	var f_min: float = p["f_min"]
	var f_max: float = p["f_max"]
	var perte: float = p["perte"]
	var contact: float = p.get("contact", 0.0005)
	var attaque: float = p.get("attaque", 0.0)
	var point := rng.randf_range(0.15, 0.85)   # endroit frappé : il change l'importance de chaque mode
	for m in nb:
		# fréquences réparties en échelle logarithmique, chacune décalée de ±2 % (deux pièces ne sont
		# jamais identiques)
		var f := f_min * pow(f_max / f_min, (m + rng.randf_range(0.1, 0.9)) / nb) * rng.randf_range(0.98, 1.02)
		var tau := 1.0 / (PI * f * perte * rng.randf_range(0.8, 1.25))
		# force du mode : forme du mode au point frappé × spectre du choc (impulsion en demi-sinus de durée
		# « contact » : plus le choc est bref, plus il nourrit les aigus) × 1/√f (masse modale)
		var forme := absf(sin(PI * (m + 1) * point))
		var tc := f * contact
		var choc := 1.0 if absf(1.0 - 4.0 * tc * tc) < 1e-6 else absf(cos(PI * tc) / (1.0 - 4.0 * tc * tc))
		# une force qui monte en « attaque » secondes ne nourrit pas les modes plus rapides que ça
		var montee := 1.0 / sqrt(1.0 + pow(TAU * f * attaque, 2.0))
		var amp := forme * choc * montee / sqrt(f) * rng.randf_range(0.6, 1.0)
		var phase := rng.randf() * TAU
		# oscillateur amorti calculé par récurrence (rotation complexe à chaque échantillon)
		var w := TAU * f / TAUX
		var r := exp(-1.0 / (tau * TAUX))
		var cr := r * cos(w)
		var ci := r * sin(w)
		var yr := cos(phase) * amp
		var yi := sin(phase) * amp
		var i0 := int(rng.randf_range(0.0, 0.0006) * TAUX)   # les modes ne démarrent pas tous au même échantillon
		for i in range(i0, n):
			x[i] += yi
			var nr := yr * cr - yi * ci
			yi = yr * ci + yi * cr
			yr = nr
	# montée douce de la force (allumage d'un moteur : la poussée met ~ « attaque » s à arriver)
	if attaque > 0.0:
		var na := int(attaque * TAUX)
		for i in mini(na, n):
			x[i] *= 0.5 - 0.5 * cos(PI * float(i) / na)
	# bref souffle de gaz (vanne qui s'ouvre) : bruit filtré, montée rapide, décroissance de ~30 ms
	var s: float = p.get("souffle", 0.0)
	if s > 0.0:
		var crete := 0.0
		for v in x:
			crete = maxf(crete, absf(v))
		var fs: float = p.get("souffle_f", 1500.0)
		var a := exp(-TAU * fs / TAUX)
		var b := exp(-TAU * fs * 0.25 / TAUX)
		var lp := 0.0
		var lp2 := 0.0
		for i in mini(int(0.15 * TAUX), n):
			var t := float(i) / TAUX
			var env := (1.0 - exp(-t / 0.002)) * exp(-t / 0.03)
			var bruit := rng.randfn(0.0, 1.0)
			lp = a * lp + (1.0 - a) * bruit
			lp2 = b * lp2 + (1.0 - b) * bruit
			x[i] += (lp - lp2) * env * s * crete * 3.0   # bande autour de fs
	# fin en fondu (pas de coupure audible)
	var nf := mini(int(0.02 * TAUX), n)
	for i in nf:
		x[n - 1 - i] *= float(i) / nf
	return x


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
