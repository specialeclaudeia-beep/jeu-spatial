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
	material_override = materiau
	return true


## Axes de la caméra (devant, droite, haut) dans le repère de la planète.
func _axes(camera: Camera3D) -> PackedFloat32Array:
	var b := rotation_astre.transposed() * camera.global_transform.basis
	return PackedFloat32Array([-b.z.x, -b.z.y, -b.z.z, b.x.x, b.x.y, b.x.z, b.y.x, b.y.y, b.y.z])


## Une image de la boucle. oeil = position de l'œil dans le repère de la planète (m, 64 bits) ;
## vers_centre = centre de la planète moins position de l'œil, dans le repère d'affichage (la caméra
## est à l'origine) ; temps = horloge du labo en secondes ; occulteur_affichage = centre (par rapport
## à la caméra) et rayon de l'astre qui peut cacher le Soleil (w = 0 : aucun).
func mettre_a_jour(camera: Camera3D, oeil: PackedFloat64Array, vers_centre: PackedFloat64Array, temps: float,
		chrono: RefCounted, occulteur_affichage := Vector4.ZERO) -> void:
	var axes := _axes(camera)
	var taille := camera.get_viewport().get_visible_rect().size
	var tan_v := tan(deg_to_rad(camera.fov) * 0.5)
	var tan_h := tan_v * taille.x / taille.y

	chrono.debut(ChronoBoucle.CHOISIR)
	arbre.choisir(oeil, axes, tan_h, tan_v, taille.y, temps)
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
func posemetre(camera: Camera3D, oeil: PackedFloat64Array, soleil_dir: Vector3, eclairement: float,
		fond: float, soleil_angle := 0.004652) -> PackedFloat32Array:
	var axes := _axes(camera)
	var taille := camera.get_viewport().get_visible_rect().size
	var tan_v := tan(deg_to_rad(camera.fov) * 0.5)
	var s := rotation_astre.transposed() * soleil_dir
	return arbre.posemetre(oeil, axes, tan_v * taille.x / taille.y, tan_v, s, eclairement, fond, occulteur,
		soleil_angle)


## Part de chaque case (0 à 1) couverte par la planète au dernier posemètre.
func couverture() -> PackedFloat32Array:
	return arbre.couverture()


## Hauteur du sol (m au-dessus du rayon) sous la position p (repère de la planète).
func hauteur_sol(p: PackedFloat64Array) -> float:
	return arbre.hauteur_sol(p)
