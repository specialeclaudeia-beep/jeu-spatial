extends RefCounted
## L'égaliseur à 10 bandes de Godot (AudioEffectEQ10), refait en calcul (moteur audio, phase 1).
##
## Pourquoi : cet égaliseur n'est pas parfait. Ses 10 filtres se recouvrent (une bande déborde d'environ
## −7 dB sur ses voisines) et, réglé « à plat », il rend le son environ 2 fois plus fort (+3 dB). Pour que
## ce qui sort des haut-parleurs soit exactement le niveau calculé par la physique, on refait ici le même
## calcul que Godot (fichier eq_filter.cpp de Godot : mêmes formules, mêmes fréquences), et on en déduit
## l'énergie qui sort vraiment pour des réglages donnés.
##
## Calcul : la sortie est la somme des 10 bandes, chacune multipliée par son gain g. Son énergie vaut
## Σ g_j g_k M_jk, où le tableau M (10 × 10) ne dépend que du son d'entrée (la boucle) : on le calcule une
## fois au démarrage. Ensuite, à chaque image, il ne reste que 100 multiplications.

const BANDES := [31.25, 62.5, 125.0, 250.0, 500.0, 1000.0, 2000.0, 4000.0, 8000.0, 16000.0]
const POINTS_PAR_OCTAVE := 24
const F_MIN := 10.0
const F_MAX := 16000.0     # les boucles sont à 32 000 échantillons par seconde : rien au-dessus


## Coefficients [c1, c2, c3] de chaque bande pour un taux d'échantillonnage donné (comme Godot).
static func coefficients(taux: float) -> Array:
	var res := []
	var n := BANDES.size()
	for i in n:
		var frq: float = BANDES[i]
		var octave: float
		if i == 0:
			octave = log(float(BANDES[1]) / frq) / log(2.0)
		elif i == n - 1:
			octave = log(frq / float(BANDES[i - 1])) / log(2.0)
		else:
			octave = (log(float(BANDES[i + 1]) / frq) + log(frq / float(BANDES[i - 1]))) / log(2.0) / 2.0
		var frq_l := roundf(frq / pow(2.0, octave / 2.0))
		var g2 := 0.5                    # gain de côté : −3 dB au bord de la bande
		var th := TAU * frq / taux
		var th_l := TAU * frq_l / taux
		var a := g2 * cos(th) * cos(th) - 2.0 * g2 * cos(th_l) * cos(th) + g2 - sin(th_l) * sin(th_l)
		var b := 2.0 * g2 * cos(th_l) * cos(th_l) + g2 * cos(th) * cos(th) - 2.0 * g2 * cos(th_l) * cos(th) - g2 + sin(th_l) * sin(th_l)
		var c := 0.25 * g2 * cos(th) * cos(th) - 0.5 * g2 * cos(th_l) * cos(th) + 0.25 * g2 - 0.25 * sin(th_l) * sin(th_l)
		var r1 := (-b + sqrt(maxf(b * b - 4.0 * a * c, 0.0))) / (2.0 * a)
		res.append([2.0 * ((0.5 - r1) / 2.0), 2.0 * r1, 2.0 * (0.5 + r1) * cos(th)])
	return res


## Réponse (partie réelle, partie imaginaire) de chaque bande à la fréquence f.
## Bande : y[n] = c1 (x[n] − x[n−2]) + c3 y[n−1] − c2 y[n−2].
static func reponse(coefs: Array, f: float, taux: float) -> PackedFloat64Array:
	var w := TAU * f / taux
	var res := PackedFloat64Array()
	res.resize(2 * coefs.size())
	for j in coefs.size():
		var c1: float = coefs[j][0]
		var c2: float = coefs[j][1]
		var c3: float = coefs[j][2]
		var n_re := c1 * (1.0 - cos(2.0 * w))
		var n_im := c1 * sin(2.0 * w)
		var d_re := 1.0 - c3 * cos(w) + c2 * cos(2.0 * w)
		var d_im := c3 * sin(w) - c2 * sin(2.0 * w)
		var d2 := d_re * d_re + d_im * d_im
		res[2 * j] = (n_re * d_re + n_im * d_im) / d2
		res[2 * j + 1] = (n_im * d_re - n_re * d_im) / d2
	return res


## Le tableau M pour une boucle dont la densité d'énergie est densite(f) (par Hz, à un facteur près).
## Avec les 10 gains g (en amplitude), énergie de sortie / énergie de la boucle seule = Σ g_j g_k M_jk.
static func matrice(densite: Callable, taux: float) -> PackedFloat64Array:
	var coefs := coefficients(taux)
	var m := PackedFloat64Array()
	m.resize(100)
	var n := int(ceil(log(F_MAX / F_MIN) / log(2.0) * POINTS_PAR_OCTAVE))
	var pas := log(F_MAX / F_MIN) / n
	var total := 0.0
	for p in n:
		var f := F_MIN * exp((p + 0.5) * pas)
		var poids := maxf(float(densite.call(f)), 0.0) * f * pas
		if poids <= 0.0:
			continue
		total += poids
		var h := reponse(coefs, f, taux)
		for j in 10:
			for k in range(j, 10):
				var v := poids * (h[2 * j] * h[2 * k] + h[2 * j + 1] * h[2 * k + 1])
				m[j * 10 + k] += v
				if k != j:
					m[k * 10 + j] += v
	if total > 0.0:
		for i in 100:
			m[i] /= total
	return m


## Énergie de sortie / énergie d'entrée pour les gains g (amplitudes).
static func energie(m: PackedFloat64Array, g: PackedFloat64Array) -> float:
	var e := 0.0
	for j in 10:
		var gj := g[j]
		if gj <= 0.0:
			continue
		var s := 0.0
		for k in 10:
			s += m[j * 10 + k] * g[k]
		e += gj * s
	return e
