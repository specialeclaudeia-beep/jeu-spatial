extends RefCounted
## Les étoiles (étape 6) : le vrai ciel, le catalogue de Yale jusqu'à la magnitude 6,5
## (9 096 étoiles, domaine public), la lueur de la Voie lactée, la couleur des étoiles
## (corps noir), et ce que voit un œil qui va très vite : aberration et effet Doppler.
## Ce fichier fait partie du système : il ne dépend de rien d'autre que de son dossier.
##
## Repère : celui du labo, FIXE (qui ne tourne pas avec la planète). L'axe Y est le pôle nord du ciel
## (l'axe de rotation de la planète, comme pour la Terre), l'axe X l'ascension droite 0 h.
## Le labo fait tourner tout le ciel avec le jour (le ciel tourne autour de l'axe Y).
##
## Lois utilisées :
## - éclat : une étoile de magnitude 0 donne 2,54 millionièmes de lux (hors atmosphère),
##   chaque magnitude de plus divise par 2,512 ;
## - couleur : indice B-V → température (formule de Ballesteros, 2012), puis lumière d'un corps noir
##   (loi de Planck) vue par l'œil (fonctions colorées de la CIE 1931, approchées par Wyman 2013) ;
## - grande vitesse (relativité restreinte) : la direction d'une étoile se penche vers l'avant
##   (aberration), sa lumière change de couleur et d'éclat (Doppler) : un corps noir de température T
##   se voit comme un corps noir de température D × T, et l'éclat d'une étoile est multiplié par
##   D² × (efficacité à D·T) / (efficacité à T). D = γ (1 + β cos θ), θ = angle avec la vitesse.

const CATALOGUE := "res://scripts/lumiere/etoiles_yale.bin"
const LUX_MAGNITUDE_0 := 2.54e-6       # lux d'une étoile de magnitude 0
const C := 299792458.0                 # vitesse de la lumière, m/s
const T_SOLEIL := 5772.0               # K
## Table des corps noirs envoyée aux shaders (etoiles.gdshaderinc) : 256 températures, de 500 K à
## 2 millions de K (de quoi suivre le Doppler jusqu'à 0,99 c), espacées « en multipliant ».
const T_MIN := 500.0
const T_MAX := 2.0e6
const TAILLE_TABLE := 256

## Voie lactée : pôle nord et centre de la galaxie (coordonnées J2000), et sa lueur (cd/m²).
## Mesures du ciel vu de l'espace : fond entre les étoiles faibles et la lumière zodiacale
## ≈ 23 mag/arcsec² (7e-5 cd/m²), bande de la Voie lactée ≈ 21 (4e-4), centre ≈ 20 (1e-3).
const POLE_GALAXIE_AD := 192.859508
const POLE_GALAXIE_DEC := 27.128336
const CENTRE_GALAXIE_AD := 266.404989
const CENTRE_GALAXIE_DEC := -28.936172
const FOND_MIN := 7.0e-5
const FOND_BANDE := 3.6e-4
const FOND_CENTRE := 7.0e-4

static var _efficacite_soleil := -1.0

var nombre := 0
const PLACES_EN_PLUS := 2               # planète et lune vues de loin (lumiere_jeu.gd)
var ascension := PackedFloat32Array()  # rad
var declinaison := PackedFloat32Array()
var magnitude := PackedFloat32Array()
var couleur_bv := PackedFloat32Array()


## Lit le catalogue (les plus brillantes d'abord). Faux si le fichier manque.
func charger() -> bool:
	var f := FileAccess.open(CATALOGUE, FileAccess.READ)
	if f == null:
		return false
	if f.get_buffer(4).get_string_from_ascii() != "YALE":
		return false
	nombre = f.get_32()
	var octets := f.get_buffer(nombre * 16)
	f.close()
	var tout := octets.to_float32_array()
	ascension.resize(nombre)
	declinaison.resize(nombre)
	magnitude.resize(nombre)
	couleur_bv.resize(nombre)
	for i in nombre:
		ascension[i] = tout[i * 4]
		declinaison[i] = tout[i * 4 + 1]
		magnitude[i] = tout[i * 4 + 2]
		couleur_bv[i] = tout[i * 4 + 3]
	return nombre > 0


## Direction (repère fixe du labo) d'un point du ciel donné en ascension droite et déclinaison (rad).
static func direction_ciel(ad: float, dec: float) -> Vector3:
	return Vector3(cos(dec) * cos(ad), sin(dec), -cos(dec) * sin(ad))


static func direction_ciel_degres(ad: float, dec: float) -> Vector3:
	return direction_ciel(deg_to_rad(ad), deg_to_rad(dec))


## Lux reçus d'une étoile de magnitude m.
static func lux(m: float) -> float:
	return LUX_MAGNITUDE_0 * pow(10.0, -0.4 * m)


## Température de surface (K) d'après l'indice de couleur B-V (Ballesteros 2012).
static func temperature(bv: float) -> float:
	bv = clampf(bv, -0.4, 2.2)
	return 4600.0 * (1.0 / (0.92 * bv + 1.7) + 1.0 / (0.92 * bv + 0.62))


## Fonctions colorées de la CIE 1931 (approximation de Wyman, Sloan et Shirley, 2013), λ en nm.
static func _g(x: float, mu: float, s1: float, s2: float) -> float:
	var t := (x - mu) / (s1 if x < mu else s2)
	return exp(-0.5 * t * t)


static func cie_xyz(l: float) -> Vector3:
	return Vector3(
		1.056 * _g(l, 599.8, 37.9, 31.0) + 0.362 * _g(l, 442.0, 16.0, 26.7) - 0.065 * _g(l, 501.1, 20.4, 26.2),
		0.821 * _g(l, 568.8, 46.9, 40.5) + 0.286 * _g(l, 530.9, 16.3, 31.1),
		1.217 * _g(l, 437.0, 11.8, 36.0) + 0.681 * _g(l, 459.0, 26.0, 13.8))


## Lumière d'un corps noir à la température t : couleur (rouge, vert, bleu linéaires, luminance 1)
## et efficacité = part de son énergie que l'œil voit (sans unité, 1 pour le Soleil).
static func corps_noir(t: float) -> Color:
	var xyz := Vector3.ZERO
	var c2 := 0.014388                       # m·K (constante de Planck × c / constante de Boltzmann)
	var l := 360.0
	while l <= 830.0:
		var lm := l * 1e-9
		var x := c2 / (lm * t)
		var b := 0.0 if x > 700.0 else 1.0 / (pow(lm, 5.0) * (exp(x) - 1.0))
		xyz += cie_xyz(l) * b * 5e-9
		l += 5.0
	var energie := pow(t / c2, 4.0) * pow(PI, 4.0) / 15.0   # ∫ λ⁻⁵ / (exp(c2/λT) − 1) dλ
	var efficacite := xyz.y / energie
	var y := maxf(xyz.y, 1e-300)
	var r := 3.2406 * xyz.x - 1.5372 * xyz.y - 0.4986 * xyz.z
	var g := -0.9689 * xyz.x + 1.8758 * xyz.y + 0.0415 * xyz.z
	var bl := 0.0557 * xyz.x - 0.2040 * xyz.y + 1.0570 * xyz.z
	var rgb := Vector3(maxf(r, 0.0), maxf(g, 0.0), maxf(bl, 0.0)) / y
	# On garde une luminance de 1 après avoir retiré les couleurs hors de l'écran.
	rgb /= maxf(rgb.dot(Vector3(0.2126, 0.7152, 0.0722)), 1e-9)
	return Color(rgb.x, rgb.y, rgb.z, efficacite / efficacite_soleil())


static func efficacite_soleil() -> float:
	if _efficacite_soleil < 0.0:
		_efficacite_soleil = 1.0
		_efficacite_soleil = corps_noir(T_SOLEIL).a
	return _efficacite_soleil


## Efficacité relative (1 pour le Soleil) d'un corps noir.
static func efficacite(t: float) -> float:
	return corps_noir(t).a


## La table des corps noirs pour les shaders : 256 × 1, RGBA flottants (couleur, efficacité relative).
static func table_corps_noir() -> ImageTexture:
	var img := Image.create(TAILLE_TABLE, 1, false, Image.FORMAT_RGBAF)
	for i in TAILLE_TABLE:
		var t := T_MIN * pow(T_MAX / T_MIN, float(i) / (TAILLE_TABLE - 1))
		img.set_pixel(i, 0, corps_noir(t))
	return ImageTexture.create_from_image(img)


## Aberration de la lumière (relativité restreinte). n = direction d'une étoile vue au repos
## (longueur 1), beta = vitesse de l'œil en fraction de c. Renvoie [direction vue, D] où D est le
## facteur Doppler (D > 1 : vers le bleu, en avant ; D < 1 : vers le rouge, en arrière).
static func aberration(n: Vector3, beta: Vector3) -> Array:
	var b := beta.length()
	if b < 1e-12:
		return [n, 1.0]
	b = minf(b, 0.999999)
	var u := beta.normalized()
	var g := 1.0 / sqrt(1.0 - b * b)
	var c := n.dot(u)
	var vue := (n + u * (g * b + (g - 1.0) * c)) / (g * (1.0 + b * c))
	return [vue.normalized(), g * (1.0 + b * c)]


## Facteur sur l'éclat d'une étoile (corps noir à t) vue avec le facteur Doppler d.
static func facteur_eclat(d: float, t: float) -> float:
	return d * d * efficacite(d * t) / efficacite(t)


## Facteur sur la luminance d'une surface (disque du Soleil, ciel) : d⁴ au lieu de d².
static func facteur_luminance(d: float, t: float) -> float:
	return d * d * d * d * efficacite(d * t) / efficacite(t)


static func pole_galaxie() -> Vector3:
	return direction_ciel_degres(POLE_GALAXIE_AD, POLE_GALAXIE_DEC)


static func centre_galaxie() -> Vector3:
	return direction_ciel_degres(CENTRE_GALAXIE_AD, CENTRE_GALAXIE_DEC)


## Lueur du fond du ciel (cd/m²) dans la direction n (repère fixe) : la Voie lactée, plus forte vers
## son centre, et la lueur faible partout ailleurs. Même formule que etoiles.gdshaderinc.
static func fond(n: Vector3) -> float:
	var p := pole_galaxie()
	var c := centre_galaxie()
	return fond_avec(n, p, c)


static func fond_avec(n: Vector3, p: Vector3, c: Vector3) -> float:
	var b := asin(clampf(n.dot(p), -1.0, 1.0))           # latitude galactique
	var vers_centre := acos(clampf(n.dot(c), -1.0, 1.0))
	var bande := exp(-pow(b / 0.14, 2.0)) * (0.35 + 0.65 * exp(-pow(vers_centre / 1.3, 2.0)))
	var bulbe := exp(-pow(vers_centre / 0.22, 2.0))
	return FOND_MIN + FOND_BANDE * bande + FOND_CENTRE * bulbe


## Le nœud qui dessine les étoiles : un seul MultiMesh, une copie d'un petit carré par étoile.
## Chaque copie garde sa direction (position de la copie, longueur 1), son éclat (log10 des lux) et
## sa température. Le nœud reste à la place de la caméra ; le labo le fait tourner avec le ciel.
func creer_noeud(shader: Shader, table: Texture2D) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	var carre := QuadMesh.new()
	carre.size = Vector2(2.0, 2.0)
	mm.mesh = carre
	# Grandes distances : PLACES_EN_PLUS copies de plus, à la fin, pour les astres vus de loin (planète,
	# lune), éteintes au départ.
	mm.instance_count = nombre + PLACES_EN_PLUS
	for i in PLACES_EN_PLUS:
		mm.set_instance_transform(nombre + i, Transform3D(Basis.IDENTITY, Vector3.BACK))
		mm.set_instance_custom_data(nombre + i, Color(-40.0, 0.5772, 0.0, 0.0))
	for i in nombre:
		var d := direction_ciel(ascension[i], declinaison[i])
		mm.set_instance_transform(i, Transform3D(Basis.IDENTITY, d))
		mm.set_instance_custom_data(i, Color(log(lux(magnitude[i])) / log(10.0), temperature(couleur_bv[i]) / 10000.0, 0.0, 0.0))
	var noeud := MultiMeshInstance3D.new()
	noeud.name = "Etoiles"
	noeud.multimesh = mm
	noeud.custom_aabb = AABB(Vector3.ONE * -1.0e9, Vector3.ONE * 2.0e9)
	noeud.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat := ShaderMaterial.new()
	mat.shader = shader
	mat.set_shader_parameter("corps_noir", table)
	noeud.material_override = mat
	return noeud
