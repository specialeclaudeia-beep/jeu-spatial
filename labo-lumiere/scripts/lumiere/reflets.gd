extends RefCounted
## Les reflets (étape 9 du programme du système de lumière) : verrière, visière du casque, métaux.
## Ce fichier fait partie du système : il ne dépend de rien d'autre que de son dossier.
##
## Un reflet suit la loi du miroir (l'angle de départ égale l'angle d'arrivée) et la loi de Fresnel
## (une vitre renvoie 4 % de la lumière de face par surface, beaucoup plus en biais). Ce qu'on voit
## dans le reflet vient de trois sources, toutes tirées des rayons du système :
## 1. la « carte du ciel » : la planète (et la lune) vues de l'œil dans TOUTES les directions, tirée
##    des rayons de la partie C++ (ArbreLumiere.carte_ciel) ; le Soleil et l'étoile compagne restent
##    exacts (leur disque est calculé dans le programme de dessin) ;
## 2. la « sonde du cockpit » : l'intérieur du vaisseau vu depuis la tête du pilote, tiré des rayons
##    lancés sur les formes du vaisseau (objets.gd, les mêmes que le posemètre). Elle se remplit un peu
##    à chaque image (RAYONS_PAR_IMAGE cases) ;
## 3. la visière : la face intérieure renvoie au pilote un voile très flou de son propre visage,
##    éclairé par la lumière qui traverse la visière (réglage global oeil_reflet_visiere).
## Les deux cartes sont des textures en longitude-latitude (u = atan2(x, −z) / 2π + 0,5,
## v = acos(y) / π), en nombres à virgule (luminances en cd/m²), « prémultipliées » : rouge, vert,
## bleu = luminance × part couverte, alpha = part couverte. Réglages globaux : reflets_ciel,
## reflets_cockpit, reflets_base (repère du vaisseau → affichage), reflets_rayon_sonde, reflets_actifs.

const LARGEUR_CIEL := 64
const HAUTEUR_CIEL := 32
const LARGEUR_COCKPIT := 32
const HAUTEUR_COCKPIT := 16
## Cases de la sonde du cockpit recalculées à chaque image (1 à 2 rayons chacune, quelques µs).
const RAYONS_PAR_IMAGE := 24
## La carte du ciel est refaite une image sur N (la planète bouge lentement vue du vaisseau).
const CIEL_TOUTES_LES := 12
## Rayon (m) de la boule autour de la tête sur laquelle on « pose » la sonde du cockpit, pour corriger
## le décalage entre la tête et le point de la vitre (correction de parallaxe).
const RAYON_SONDE := 0.9

## Indice de réfraction du verre acrylique de la verrière et du polycarbonate de la visière.
const INDICE_VERRIERE := 1.49
const INDICE_VISIERE := 1.586
## Ce que la visière renvoie vers l'œil : pour moitié le visage (peau, 0,35), pour moitié la mousse
## sombre de l'intérieur du casque (0,05) → part moyenne de la lumière renvoyée 0,2.
const ALBEDO_VISAGE := 0.2
## Visières : part de la lumière renvoyée vers l'œil par la face intérieure (rouge, vert, bleu).
## Claire : deux surfaces de polycarbonate (Fresnel). Solaire : en plus le film d'or mince vu par
## derrière (valeurs approchées pour un film qui laisse passer 20 % : l'or renvoie le rouge et absorbe
## le bleu). Sans casque : rien.
const REFLETS_VISIERES := [Vector3(0.0, 0.0, 0.0), Vector3(0.098, 0.098, 0.098), Vector3(0.55, 0.46, 0.28)]

var image_ciel: Image
var tex_ciel: ImageTexture
var image_cockpit: Image
var tex_cockpit: ImageTexture
var _donnees_cockpit := PackedFloat32Array()
var _case := 0
var _image := 0
## Nombre de cases de la sonde déjà calculées au moins une fois (pour les tests).
var cases_faites := 0


## Crée les deux cartes et les donne aux programmes de dessin (réglages globaux).
func preparer() -> void:
	var noir := PackedFloat32Array()
	noir.resize(LARGEUR_CIEL * HAUTEUR_CIEL * 4)
	image_ciel = Image.create_from_data(LARGEUR_CIEL, HAUTEUR_CIEL, false, Image.FORMAT_RGBAF, noir.to_byte_array())
	tex_ciel = ImageTexture.create_from_image(_avec_mipmaps(image_ciel))
	_donnees_cockpit.resize(LARGEUR_COCKPIT * HAUTEUR_COCKPIT * 4)
	image_cockpit = Image.create_from_data(LARGEUR_COCKPIT, HAUTEUR_COCKPIT, false, Image.FORMAT_RGBAF,
		_donnees_cockpit.to_byte_array())
	tex_cockpit = ImageTexture.create_from_image(_avec_mipmaps(image_cockpit))
	var rs := RenderingServer
	rs.global_shader_parameter_set("reflets_ciel", tex_ciel)
	rs.global_shader_parameter_set("reflets_cockpit", tex_cockpit)
	rs.global_shader_parameter_set("reflets_rayon_sonde", RAYON_SONDE)
	rs.global_shader_parameter_set("reflets_actifs", 1.0)


## Les mipmaps (cartes de plus en plus floues) servent aux surfaces rugueuses : un métal brossé
## reflète une image floue. Calculées en demi-flottants pour que la carte graphique sache les lire.
static func _avec_mipmaps(img: Image) -> Image:
	var copie := img.duplicate() as Image
	copie.convert(Image.FORMAT_RGBAH)
	copie.generate_mipmaps()
	return copie


## Direction → coordonnées de la carte (u, v entre 0 et 1). La même formule dans les programmes de dessin.
static func uv(d: Vector3) -> Vector2:
	return Vector2(atan2(d.x, -d.z) / TAU + 0.5, acos(clampf(d.y, -1.0, 1.0)) / PI)


## Coordonnées de la carte → direction (longueur 1).
static func direction(p: Vector2) -> Vector3:
	var lon := (p.x - 0.5) * TAU
	var th := p.y * PI
	return Vector3(sin(th) * sin(lon), cos(th), -sin(th) * cos(lon))


## Loi de Fresnel (approximation de Schlick) pour une surface d'indice n vue sous un angle de cosinus c.
static func fresnel(c: float, n: float) -> float:
	var f0 := pow((n - 1.0) / (n + 1.0), 2.0)
	return f0 + (1.0 - f0) * pow(1.0 - clampf(c, 0.0, 1.0), 5.0)


## Une lame de verre (deux surfaces, la lumière fait des allers-retours entre elles) : part renvoyée.
## Le reste traverse : (1 − R) / (1 + R). Rien n'est perdu (le verre absorbe très peu).
static func reflet_lame(c: float, n: float) -> float:
	var r := fresnel(c, n)
	return 2.0 * r / (1.0 + r)


## 1. La carte du ciel. astres = liste de dictionnaires, du plus proche au plus lointain :
## {"planete": Planete, "oeil": position de l'œil dans le repère de l'astre (64 bits), "soleil":
## direction du Soleil (affichage), "eclairement": lux, "angle": rayon apparent du Soleil}.
## Un astre plus proche cache ceux qui sont derrière lui.
func mettre_a_jour_ciel(astres: Array, forcer := false) -> void:
	_image += 1
	if not forcer and (_image % CIEL_TOUTES_LES) != 1:
		return
	var n := LARGEUR_CIEL * HAUTEUR_CIEL
	var total := PackedFloat32Array()
	total.resize(n * 4)
	var reste := PackedFloat32Array()
	reste.resize(n)
	reste.fill(1.0)
	for a in astres:
		var pl = a["planete"]
		if pl == null:
			continue
		var carte: PackedFloat32Array = pl.carte_ciel(a["oeil"], a["soleil"], a["eclairement"], LARGEUR_CIEL,
			HAUTEUR_CIEL, a.get("angle", 0.004652))
		for k in n:
			var cov := carte[k * 4 + 3]
			if cov <= 0.0:
				continue
			var part := cov * reste[k]
			total[k * 4] += carte[k * 4] * part
			total[k * 4 + 1] += carte[k * 4 + 1] * part
			total[k * 4 + 2] += carte[k * 4 + 2] * part
			total[k * 4 + 3] += part
			reste[k] -= part
	image_ciel.set_data(LARGEUR_CIEL, HAUTEUR_CIEL, false, Image.FORMAT_RGBAF, total.to_byte_array())
	tex_ciel.update(_avec_mipmaps(image_ciel))


## Ce que montre la carte du ciel dans la direction d (affichage) : Color(r, g, b prémultipliés, part).
func lire_ciel(d: Vector3) -> Color:
	var p := uv(d)
	return image_ciel.get_pixel(clampi(int(p.x * LARGEUR_CIEL), 0, LARGEUR_CIEL - 1),
		clampi(int(p.y * HAUTEUR_CIEL), 0, HAUTEUR_CIEL - 1))


## 2. La sonde du cockpit (repère du vaisseau, depuis l'œil) : RAYONS_PAR_IMAGE cases de plus.
## objets = Objets (objets.gd), oeil_local = œil dans le repère du vaisseau, soleil = direction du
## Soleil (repère du vaisseau), e_soleil = lux (part visible comprise), e_autre = lux venus d'ailleurs.
func mettre_a_jour_cockpit(objets: RefCounted, oeil_local: Vector3, soleil: Vector3, e_soleil: float,
		e_autre: float, nb := RAYONS_PAR_IMAGE) -> void:
	if objets == null or objets.nb_faces == 0:
		return
	var n := LARGEUR_COCKPIT * HAUTEUR_COCKPIT
	for i in mini(nb, n):
		var k := _case
		_case = (_case + 1) % n
		var p := Vector2((k % LARGEUR_COCKPIT + 0.5) / LARGEUR_COCKPIT, (k / LARGEUR_COCKPIT + 0.5) / HAUTEUR_COCKPIT)
		var c: Color = objets.luminance_vue_couleur(oeil_local, direction(p), soleil, e_soleil, e_autre)
		_donnees_cockpit[k * 4] = c.r * c.a
		_donnees_cockpit[k * 4 + 1] = c.g * c.a
		_donnees_cockpit[k * 4 + 2] = c.b * c.a
		_donnees_cockpit[k * 4 + 3] = c.a
		cases_faites = mini(cases_faites + 1, n)
	image_cockpit.set_data(LARGEUR_COCKPIT, HAUTEUR_COCKPIT, false, Image.FORMAT_RGBAF,
		_donnees_cockpit.to_byte_array())
	tex_cockpit.update(_avec_mipmaps(image_cockpit))


## Repère du vaisseau → repère d'affichage (pour lire la sonde du cockpit).
static func regler_base(base: Basis) -> void:
	RenderingServer.global_shader_parameter_set("reflets_base", base)


## Luminance moyenne (cd/m²) de l'intérieur du cockpit vu de la tête (moyenne de la sonde).
func luminance_cockpit() -> float:
	var s := 0.0
	var n := LARGEUR_COCKPIT * HAUTEUR_COCKPIT
	for k in n:
		s += 0.2126 * _donnees_cockpit[k * 4] + 0.7152 * _donnees_cockpit[k * 4 + 1] + 0.0722 * _donnees_cockpit[k * 4 + 2]
	return s / n


## 3. La visière : luminance (cd/m², par couleur) du voile renvoyé à l'œil par sa face intérieure.
## visiere = 0 sans casque, 1 claire, 2 solaire ; filtre = part transmise par la visière ;
## e_visage = lux reçus par le visage AVANT la visière (Soleil + le reste). La lumière traverse la
## visière, éclaire le visage (peau mate), puis la face intérieure en renvoie une partie vers l'œil.
## Le visage est à 3-5 cm : bien trop près pour être net, il ne reste qu'un voile uniforme.
static func reflet_visiere(visiere: int, filtre: Vector3, e_visage: float) -> Vector3:
	var r: Vector3 = REFLETS_VISIERES[clampi(visiere, 0, REFLETS_VISIERES.size() - 1)]
	return r * filtre * (ALBEDO_VISAGE * e_visage / PI)


## Image fantôme du Soleil dans la visière : part de la lumière du Soleil (déjà passée par la visière)
## qui revient vers l'œil après deux réflexions : face intérieure du polycarbonate (≈ 5 %), puis face
## extérieure (claire : ≈ 4,9 %) ou film d'or vu de l'intérieur (solaire). Sans casque : rien.
const FANTOMES_VISIERES := [Vector3(0.0, 0.0, 0.0), Vector3(0.00245, 0.00245, 0.00245),
	Vector3(0.0275, 0.023, 0.014)]
## La coque (rayon ≈ 15 cm) fait du Soleil une image virtuelle à ≈ 7,5 cm de l'œil.
const DISTANCE_IMAGE_FANTOME := 0.075


## Global « oeil_fantome » : xyz = part renvoyée, w = rayon angulaire du flou (rad) = rayon de la
## pupille / distance de l'image (l'œil est réglé à l'infini), jamais moins que le Soleil.
static func fantome_visiere(visiere: int, pupille_mm: float, rayon_soleil: float) -> Vector4:
	var f: Vector3 = FANTOMES_VISIERES[clampi(visiere, 0, FANTOMES_VISIERES.size() - 1)]
	var w := maxf(0.0005 * pupille_mm / DISTANCE_IMAGE_FANTOME, rayon_soleil)
	return Vector4(f.x, f.y, f.z, w)


## Lux reçus par le visage (une demi-boule tournée vers « devant ») venant d'une étoile de direction s
## et d'éclairement e : moyenne de max(cos, 0) sur la demi-boule = (1 + devant·s) / 4.
static func eclairement_visage(devant: Vector3, s: Vector3, e: float) -> float:
	return e * (1.0 + clampf(devant.dot(s), -1.0, 1.0)) * 0.25
