extends RefCounted
## L'œil du pilote (étape 3) : pupille, adaptation de la rétine, vision de nuit, halo.
## Le processeur fait évoluer l'œil à chaque image ; la carte graphique applique le résultat
## à chaque pixel (oeil.gdshaderinc). Ce fichier fait partie du système : il ne dépend de rien d'autre.
##
## Lois utilisées (vraies mesures sur l'œil humain) :
## - pupille : formule de Moon et Spencer (1944), de 2 mm en plein soleil à 8 mm dans le noir ;
## - lumière reçue par la rétine = luminance × aire de la pupille (en « trolands ») ;
## - réponse des cônes : loi de Naka-Rushton, réponse = T / (T + k × adaptation) ;
## - vision de nuit (bâtonnets) entre 3 et 0,003 cd/m² (vision « mésopique ») ;
## - halo : fonction d'éblouissement de la CIE (2002), la même que dans les shaders.

## Constantes de temps, en secondes.
const PUPILLE_SERRE_S := 0.3          # la pupille se ferme vite…
const PUPILLE_OUVRE_S := 3.0          # … et s'ouvre lentement
const RETINE_CLAIR_S := 0.4           # la rétine s'habitue vite à la lumière…
const RETINE_NOIR_REEL_S := 300.0     # … et très lentement au noir (20 à 30 min pour tout)
const RETINE_NOIR_RAPIDE_S := 8.0     # même chose, accélérée pour les essais (choix par défaut)

const K_ADAPTATION := 4.5             # un objet aussi lumineux que l'adaptation paraît gris moyen
const NOIR_PROPRE_TD := 0.5           # « lumière propre » de la rétine (gris de l'œil fermé), trolands
const NUIT_DEBUT := 3.0               # au-dessus : vision de jour (cd/m²)
const NUIT_PLEINE := 0.003            # en dessous : vision de nuit complète (cd/m²)

var pupille_mm := 3.0                 # diamètre de la pupille
var adaptation_td := 3000.0           # état d'adaptation de la rétine, trolands
var temps_reel := false               # vrai : l'œil s'habitue au noir à la vraie vitesse
var halo := true


## Diamètre de pupille (mm) que l'œil vise pour une luminance moyenne l (cd/m²).
static func pupille_cible(l: float) -> float:
	return clampf(4.9 - 3.0 * tanh(0.4 * log(maxf(l, 1e-9)) / log(10.0)), 2.0, 8.0)


## Aire de la pupille, mm².
func aire_pupille() -> float:
	return PI * 0.25 * pupille_mm * pupille_mm


## Fait évoluer l'œil pendant dt secondes devant une scène de luminance d'adaptation l (cd/m²).
func avancer(l: float, dt: float) -> void:
	l = maxf(l, 1e-9)
	var cible := pupille_cible(l)
	var tau := PUPILLE_SERRE_S if cible < pupille_mm else PUPILLE_OUVRE_S
	pupille_mm = cible + (pupille_mm - cible) * exp(-dt / tau)
	var lc := log(l * aire_pupille())
	var la := log(adaptation_td)
	if lc > la:
		tau = RETINE_CLAIR_S
	else:
		tau = RETINE_NOIR_REEL_S if temps_reel else RETINE_NOIR_RAPIDE_S
	adaptation_td = exp(lc + (la - lc) * exp(-dt / tau))


## Mise directe à l'équilibre (au démarrage, après une téléportation).
func equilibrer(l: float) -> void:
	l = maxf(l, 1e-9)
	pupille_mm = pupille_cible(l)
	adaptation_td = l * aire_pupille()


## Facteur appliqué à chaque luminance (cd/m²) avant la réponse des cônes.
func gain() -> float:
	return aire_pupille() / (K_ADAPTATION * adaptation_td + NOIR_PROPRE_TD)


## Luminance (cd/m²) à laquelle la rétine est habituée.
func luminance_adaptation() -> float:
	return adaptation_td / aire_pupille()


## Part de la vision de nuit : 0 = cônes seuls, 1 = bâtonnets seuls.
func nuit() -> float:
	var t := inverse_lerp(log(NUIT_DEBUT), log(NUIT_PLEINE), log(maxf(luminance_adaptation(), 1e-12)))
	t = clampf(t, 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)


## Couleur d'écran (0 à 1) d'une luminance de jour (sans la vision de nuit) : sert aux tests.
func reponse(l: float) -> float:
	var x := l * gain()
	return x / (x + 1.0)


## Lumière diffusée dans l'œil (cd/m²) à theta_deg degrés d'une source qui donne e lux à l'œil.
## Fonction d'éblouissement de la CIE 146:2002, œil de 25 ans, pigmentation 0,5 (sans les raies).
static func voile(e: float, theta_deg: float) -> float:
	var t := maxf(theta_deg, 0.1)
	return e * (10.0 / (t * t * t) + (5.0 / (t * t) + 0.05 / t) * 1.0256 + 0.00125)


## Part de la lumière d'une source qui entre dans l'œil selon cos(angle avec le regard) :
## 1 droit devant, de moins en moins sur le côté, 0 au-delà de 100° (hors du champ de l'œil).
static func part_dans_le_champ(cos_angle: float) -> float:
	return clampf((cos_angle + 0.17) / 1.17, 0.0, 1.0)


## Luminance d'adaptation d'une scène à partir d'échantillons (cd/m²) et de leurs poids.
## Mélange de moyenne simple (les zones claires comptent beaucoup) et de moyenne « logarithmique »
## (les zones sombres comptent un peu). Comme la rétine s'adapte aussi par endroits, une zone
## noire ne compte pas plus sombre qu'un millième de la zone la plus claire.
## lumiere_en_plus (cd/m² moyens) : une petite source très vive comme le disque du Soleil.
static func luminance_scene(echantillons: PackedFloat32Array, poids: PackedFloat32Array, lumiere_en_plus := 0.0) -> float:
	var plus_clair := 1e-6
	for l in echantillons:
		plus_clair = maxf(plus_clair, l)
	var plancher := plus_clair * 1e-3
	var somme_p := 0.0
	var somme_l := 0.0
	var somme_log := 0.0
	for i in echantillons.size():
		var l := maxf(echantillons[i], plancher)
		somme_p += poids[i]
		somme_l += poids[i] * l
		somme_log += poids[i] * log(l)
	if somme_p <= 0.0:
		return 1e-6
	var moyenne := somme_l / somme_p + lumiere_en_plus
	return exp(0.2 * somme_log / somme_p + 0.8 * log(moyenne))
