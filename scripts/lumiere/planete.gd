extends MultiMeshInstance3D
## La planète en rayons (étape 4) : le système de décomposition fractale de la lumière appliqué à
## une vraie planète. Les 4 temps de chaque image (programme, partie 5) :
##   1. choisir   — partie C++ (ArbreLumiere.choisir) : quels triangles de l'arbre afficher ;
##   2. éclairer  — partie C++ (ArbreLumiere.eclairer, sur plusieurs fils) : les rayons des nouveaux triangles ;
##   3. envoyer   — ici : les textures (seulement si quelque chose a changé) et la place de chaque morceau ;
##   4. dessiner  — planete.gdshader, un MultiMesh du morceau type.
## Les positions sont en 64 bits côté processeur ; la carte graphique ne reçoit que des positions
## relatives à l'œil (32 bits suffisent alors).
## Si la partie C++ manque (DLL absente), preparer() renvoie false et le labo garde sa boule d'essai.

const MorceauType = preload("res://scripts/lumiere/morceau_type.gd")
const ShaderPlanete = preload("res://scripts/lumiere/planete.gdshader")
const ChronoBoucle = preload("res://scripts/lumiere/chrono_boucle.gd")
const Etoiles = preload("res://scripts/lumiere/etoiles.gd")

const PLACES := 1024                 ## morceaux affichés au plus par défaut (65 536 rayons)
var places := PLACES
var arbre: Object                    ## ArbreLumiere (partie C++)
## Rotation de la planète dans le repère d'affichage (étape 5 : la lune tourne sur elle-même).
var rotation_astre := Basis.IDENTITY
## Astre qui peut cacher le Soleil à cette planète (étape 5, éclipses) : [x, y, z, rayon], centre
## dans le repère de CETTE planète (m, 64 bits). Vide = aucun.
var occulteur := PackedFloat64Array()
var rayon := 600000.0
## Nouveaux morceaux calculés au plus par image, et temps maximum pour les calculer (budget du
## programme : éclairer 3 ms) ; le reste attend l'image suivante.
var max_par_image := 96
var budget_eclairer_ms := 3.0
## Étape 7 : distance la plus proche qu'on dessine (m) pour la profondeur logarithmique. Elle peut être
## bien plus petite que le plan proche de la caméra (Godot ne sait pas gérer 0,2 mm → 300 km). 0 : camera.near.
var profondeur_pres := 0.0
## Étape 8 : distance la plus lointaine pour la profondeur logarithmique (m). Dans le jeu, la caméra de
## Godot ne va pas plus loin que le vaisseau ; la planète (jamais coupée) va bien au-delà. 0 : camera.far.
var profondeur_loin := 0.0
## Einstein A2 : vitesse de l'œil en fraction de c (repère d'affichage). Non nulle, la planète est vue
## déformée par l'aberration, et la partie C++ choisit ses triangles dans le champ de vision « au repos »
## (là d'où vient vraiment la lumière qui arrive à l'écran).
var vitesse_oeil := Vector3.ZERO
## Facteur Doppler au centre de la planète (dernière image) : > 1 devant (bleu, brillant), < 1 derrière.
var doppler_centre := 1.0
static var _table_corps_noir: ImageTexture
var materiau: ShaderMaterial
var image_rayons: Image
var image_coins: Image
var tex_rayons: ImageTexture
var tex_coins: ImageTexture


## Vrai si la partie C++ est bien chargée.
static func cpp_disponible() -> bool:
	return ClassDB.class_exists("ArbreLumiere")


func preparer(p_rayon: float, graine: int, p_places := PLACES) -> bool:
	if not cpp_disponible():
		return false
	rayon = p_rayon
	places = p_places
	arbre = ClassDB.instantiate("ArbreLumiere")
	arbre.configurer(p_rayon, graine, places)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = MorceauType.creer(true)
	mm.instance_count = places
	multimesh = mm
	# Les morceaux sont placés par le shader : Godot ne doit jamais les croire hors de l'écran.
	custom_aabb = AABB(Vector3.ONE * -1.0e9, Vector3.ONE * 2.0e9)
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	image_rayons = Image.create_from_data(arbre.largeur_rayons(), arbre.hauteur_rayons(), false,
		Image.FORMAT_RGBA8, arbre.donnees_rayons())
	tex_rayons = ImageTexture.create_from_image(image_rayons)
	image_coins = Image.create_from_data(arbre.largeur_coins(), places, false, Image.FORMAT_RGBAF,
		arbre.donnees_coins())
	tex_coins = ImageTexture.create_from_image(image_coins)
	materiau = ShaderMaterial.new()
	materiau.shader = ShaderPlanete
	materiau.set_shader_parameter("rayons", tex_rayons)
	materiau.set_shader_parameter("coins", tex_coins)
	materiau.set_shader_parameter("rayon_corps", p_rayon)
	if _table_corps_noir == null:
		_table_corps_noir = Etoiles.table_corps_noir()
	materiau.set_shader_parameter("corps_noir", _table_corps_noir)
	material_override = materiau
	return true


## Axes de la caméra (devant, droite, haut) dans le repère de la planète.
func _axes(camera: Camera3D) -> PackedFloat32Array:
	var b := rotation_astre.transposed() * camera.global_transform.basis
	return PackedFloat32Array([-b.z.x, -b.z.y, -b.z.z, b.x.x, b.x.y, b.x.z, b.y.x, b.y.y, b.y.z])


## Einstein A2 : le champ de vision à donner à la partie C++. Sans vitesse : celui de la caméra.
## À grande vitesse, l'écran reçoit la lumière d'un autre morceau du ciel « au repos » (aberration à
## l'envers). L'aberration change les cercles du ciel en cercles : le cercle qui entoure l'écran devient
## un autre cercle, qu'on retrouve avec 3 de ses points. Renvoie [axes, tan_h, tan_v, hauteur_px] :
## la hauteur en pixels est réglée pour que les triangles gardent leur taille VUE à l'écran
## (un objet devant paraît D fois plus petit, derrière plus grand).
func champ_repos(camera: Camera3D, vers_centre: PackedFloat64Array) -> Array:
	var axes := _axes(camera)
	var taille := camera.get_viewport().get_visible_rect().size
	var tan_v := tan(deg_to_rad(camera.fov) * 0.5)
	var tan_h := tan_v * taille.x / taille.y
	var b := vitesse_oeil
	if b.length() < 1e-9:
		doppler_centre = 1.0
		return [axes, tan_h, tan_v, taille.y, axes, tan_h, tan_v]
	var cb := camera.global_transform.basis
	var f := -cb.z
	var t := sqrt(tan_h * tan_h + tan_v * tan_v)
	var points: Array[Vector3] = []
	for k in 3:
		var phi := TAU * k / 3.0
		var d := (f + (cb.x * cos(phi) + cb.y * sin(phi)) * t).normalized()
		points.append(Etoiles.aberration(d, -b)[0])
	var f_repos: Vector3 = Etoiles.aberration(f, -b)[0]
	var a := (points[1] - points[0]).cross(points[2] - points[0]).normalized()
	if a.dot(f_repos) < a.dot(points[0]):
		a = -a
	var demi := acos(clampf(a.dot(points[0]), -1.0, 1.0))
	var c := Vector3(vers_centre[0], vers_centre[1], vers_centre[2]).normalized()
	var g := 1.0 / sqrt(1.0 - minf(b.length_squared(), 0.999999999))
	doppler_centre = g * (1.0 + b.dot(c))
	var loupe := clampf(1.0 / doppler_centre, 0.1, 10.0)
	var px_par_radian := taille.y / (2.0 * tan_v) * loupe
	var inv := rotation_astre.transposed()
	var droite := (cb.y.cross(a) if absf(cb.y.dot(a)) < 0.99 else cb.x.cross(a)).normalized()
	var haut := a.cross(droite)
	# Pour le posemètre : toujours le cercle « au repos » (au plus 85° de rayon, 4 bords).
	var tp := tan(minf(demi, deg_to_rad(85.0)))
	var axes_pose := _paquet(inv * a, inv * droite, inv * haut)
	if demi < deg_to_rad(80.0):
		var tn := tan(demi)
		return [_paquet(inv * a, inv * droite, inv * haut), tn, tn, px_par_radian * 2.0 * tn, axes_pose, tp]
	# Champ trop large pour 4 bords : la partie C++ garde seulement la moitié du ciel tournée vers la
	# planète (de l'extérieur, on n'en voit jamais plus ; l'horizon fait le reste).
	var vc := inv * c
	return [_paquet(vc, vc, vc), 2.0, 2.0, px_par_radian * 4.0, axes_pose, tp]


static func _paquet(devant: Vector3, droite: Vector3, haut: Vector3) -> PackedFloat32Array:
	return PackedFloat32Array([devant.x, devant.y, devant.z, droite.x, droite.y, droite.z, haut.x, haut.y, haut.z])


## Une image de la boucle. oeil = position de l'œil dans le repère de la planète (m, 64 bits) ;
## vers_centre = centre de la planète moins position de l'œil, dans le repère d'affichage (la caméra
## est à l'origine) ; temps = horloge du labo en secondes ; occulteur_affichage = centre (par rapport
## à la caméra) et rayon de l'astre qui peut cacher le Soleil (w = 0 : aucun).
func mettre_a_jour(camera: Camera3D, oeil: PackedFloat64Array, vers_centre: PackedFloat64Array, temps: float,
		chrono: RefCounted, occulteur_affichage := Vector4.ZERO) -> void:
	var champ := champ_repos(camera, vers_centre)

	chrono.debut(ChronoBoucle.CHOISIR)
	arbre.choisir(oeil, champ[0], champ[1], champ[2], champ[3], temps)
	chrono.fin(ChronoBoucle.CHOISIR)

	chrono.debut(ChronoBoucle.ECLAIRER)
	arbre.eclairer(max_par_image, budget_eclairer_ms)
	chrono.fin(ChronoBoucle.ECLAIRER)

	chrono.debut(ChronoBoucle.ENVOYER)
	if arbre.a_change():
		image_rayons.set_data(arbre.largeur_rayons(), arbre.hauteur_rayons(), false, Image.FORMAT_RGBA8,
			arbre.donnees_rayons())
		tex_rayons.update(image_rayons)
		image_coins.set_data(arbre.largeur_coins(), places, false, Image.FORMAT_RGBAF, arbre.donnees_coins())
		tex_coins.update(image_coins)
	RenderingServer.multimesh_set_buffer(multimesh.get_rid(), arbre.tampon_instances(rotation_astre, vers_centre))
	materiau.set_shader_parameter("maintenant", temps)
	materiau.set_shader_parameter("profondeur_pres", profondeur_pres if profondeur_pres > 0.0 else camera.near)
	materiau.set_shader_parameter("profondeur_loin", profondeur_loin if profondeur_loin > 0.0 else camera.far)
	materiau.set_shader_parameter("centre_planete", Vector3(vers_centre[0], vers_centre[1], vers_centre[2]))
	materiau.set_shader_parameter("occulteur", occulteur_affichage)
	chrono.fin(ChronoBoucle.ENVOYER)
	chrono.nb_rayons = arbre.nb_rayons()


## Le posemètre : luminance (cd/m²) de 16 × 9 cases de l'écran, tirée des rayons affichés.
## Le Soleil caché par l'occulteur (éclipse) est pris en compte rayon par rayon.
## soleil_dir est donné dans le repère d'affichage.
## Einstein A2 : à grande vitesse, les cases sont mesurées dans le champ « au repos » (voir champ_repos),
## puis chaque case est renvoyée là où l'œil la voit (_cases_vues).
func posemetre(camera: Camera3D, oeil: PackedFloat64Array, soleil_dir: Vector3, eclairement: float,
		fond: float, soleil_angle := 0.004652) -> PackedFloat32Array:
	var vers_centre := PackedFloat64Array([-oeil[0], -oeil[1], -oeil[2]])
	var vc := rotation_astre * Vector3(vers_centre[0], vers_centre[1], vers_centre[2])
	var champ := champ_repos(camera, PackedFloat64Array([vc.x, vc.y, vc.z]))
	var s := rotation_astre.transposed() * soleil_dir
	var tv: float = champ[6] if champ.size() > 6 else champ[5]
	var cases: PackedFloat32Array = arbre.posemetre(oeil, champ[4], champ[5], tv, s, eclairement, fond,
		occulteur, soleil_angle)
	if vitesse_oeil != Vector3.ZERO:
		cases = _cases_vues(camera, cases, champ[4], champ[5])
	return cases


## Étape 9 : la carte du ciel vue de l'œil (toutes les directions), tirée des rayons affichés, pour les
## reflets. largeur × hauteur cases en longitude-latitude, repère d'affichage ; 4 nombres par case
## (luminance rouge, verte, bleue en cd/m², part couverte par l'astre). soleil_dir : repère d'affichage.
func carte_ciel(oeil: PackedFloat64Array, soleil_dir: Vector3, eclairement: float, largeur: int, hauteur: int,
		soleil_angle := 0.004652) -> PackedFloat32Array:
	var s := rotation_astre.transposed() * soleil_dir
	return arbre.carte_ciel(oeil, rotation_astre, largeur, hauteur, s, eclairement, occulteur, soleil_angle)


## Einstein A2 : les 16 × 9 cases mesurées « au repos » (axes en paquet, tangente tp), vues par l'œil qui
## va vite : chaque case est vue ailleurs (aberration), plus petite ou plus grande (son angle solide
## divisé par D²) et plus ou moins brillante (D⁴, couleur du corps noir à D × 5 772 K). On garde celles
## qui tombent dans l'écran, et chaque case de l'écran reçoit la moyenne pondérée de celles qui y tombent
## (ou, s'il n'y en a aucune, la moyenne de tout l'écran).
func _cases_vues(camera: Camera3D, cases: PackedFloat32Array, axes: PackedFloat32Array, tp: float) -> PackedFloat32Array:
	var taille := camera.get_viewport().get_visible_rect().size
	var tv := tan(deg_to_rad(camera.fov) * 0.5)
	var th := tv * taille.x / taille.y
	var a := rotation_astre * Vector3(axes[0], axes[1], axes[2])
	var dr := rotation_astre * Vector3(axes[3], axes[4], axes[5])
	var hu := rotation_astre * Vector3(axes[6], axes[7], axes[8])
	var inv := camera.global_transform.basis.inverse()
	var somme := PackedFloat64Array()
	var poids := PackedFloat64Array()
	somme.resize(cases.size())
	poids.resize(cases.size())
	var total := 0.0
	var total_poids := 0.0
	for j in 9:
		for i in 16:
			var x := ((i + 0.5) / 16.0 * 2.0 - 1.0) * tp
			var y := ((j + 0.5) / 9.0 * 2.0 - 1.0) * tp
			var r := (a + dr * x - hu * y).normalized()
			var ab: Array = Etoiles.aberration(r, vitesse_oeil)
			var d: float = ab[1]
			var vu: Vector3 = inv * (ab[0] as Vector3)
			if vu.z >= 0.0:
				continue
			var sx := vu.x / (-vu.z * th)
			var sy := -vu.y / (-vu.z * tv)
			if absf(sx) >= 1.0 or absf(sy) >= 1.0:
				continue
			var w := 1.0 / (pow(1.0 + x * x + y * y, 1.5) * d * d)
			var l := cases[j * 16 + i] * Etoiles.facteur_luminance(d, Etoiles.T_SOLEIL)
			var k := mini(8, int((sy + 1.0) * 4.5)) * 16 + mini(15, int((sx + 1.0) * 8.0))
			somme[k] += l * w
			poids[k] += w
			total += l * w
			total_poids += w
	var moyenne := total / total_poids if total_poids > 0.0 else 0.0
	var sortie := PackedFloat32Array()
	sortie.resize(cases.size())
	for k in cases.size():
		sortie[k] = somme[k] / poids[k] if poids[k] > 0.0 else moyenne
	return sortie


## Part de chaque case (0 à 1) couverte par la planète au dernier posemètre.
func couverture() -> PackedFloat32Array:
	return arbre.couverture()


## Hauteur du sol (m au-dessus du rayon) sous la position p (repère de la planète).
func hauteur_sol(p: PackedFloat64Array) -> float:
	return arbre.hauteur_sol(p)
