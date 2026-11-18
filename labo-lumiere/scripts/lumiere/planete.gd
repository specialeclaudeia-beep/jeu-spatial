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

const PLACES := 1024                 ## morceaux affichés au plus (65 536 rayons)
var arbre: Object                    ## ArbreLumiere (partie C++)
var rayon := 600000.0
## Nouveaux morceaux calculés au plus par image, et temps maximum pour les calculer (budget du
## programme : éclairer 3 ms) ; le reste attend l'image suivante.
var max_par_image := 96
var budget_eclairer_ms := 3.0
var materiau: ShaderMaterial
var image_rayons: Image
var image_coins: Image
var tex_rayons: ImageTexture
var tex_coins: ImageTexture


## Vrai si la partie C++ est bien chargée.
static func cpp_disponible() -> bool:
	return ClassDB.class_exists("ArbreLumiere")


func preparer(p_rayon: float, graine: int) -> bool:
	if not cpp_disponible():
		return false
	rayon = p_rayon
	arbre = ClassDB.instantiate("ArbreLumiere")
	arbre.configurer(p_rayon, graine, PLACES)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = MorceauType.creer(true)
	mm.instance_count = PLACES
	multimesh = mm
	# Les morceaux sont placés par le shader : Godot ne doit jamais les croire hors de l'écran.
	custom_aabb = AABB(Vector3.ONE * -1.0e9, Vector3.ONE * 2.0e9)
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	image_rayons = Image.create_from_data(arbre.largeur_rayons(), arbre.hauteur_rayons(), false,
		Image.FORMAT_RGBA8, arbre.donnees_rayons())
	tex_rayons = ImageTexture.create_from_image(image_rayons)
	image_coins = Image.create_from_data(arbre.largeur_coins(), PLACES, false, Image.FORMAT_RGBAF,
		arbre.donnees_coins())
	tex_coins = ImageTexture.create_from_image(image_coins)
	materiau = ShaderMaterial.new()
	materiau.shader = ShaderPlanete
	materiau.set_shader_parameter("rayons", tex_rayons)
	materiau.set_shader_parameter("coins", tex_coins)
	material_override = materiau
	return true


## Une image de la boucle. oeil = position de l'œil dans le repère de la planète (m, 64 bits) ;
## vers_centre = centre de la planète moins position de l'œil, dans le repère d'affichage (la caméra
## est à l'origine) ; temps = horloge du labo en secondes.
func mettre_a_jour(camera: Camera3D, oeil: PackedFloat64Array, vers_centre: PackedFloat64Array, temps: float,
		chrono: RefCounted) -> void:
	var b := camera.global_transform.basis
	var axes := PackedFloat32Array([-b.z.x, -b.z.y, -b.z.z, b.x.x, b.x.y, b.x.z, b.y.x, b.y.y, b.y.z])
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
		image_coins.set_data(arbre.largeur_coins(), PLACES, false, Image.FORMAT_RGBAF, arbre.donnees_coins())
		tex_coins.update(image_coins)
	RenderingServer.multimesh_set_buffer(multimesh.get_rid(), arbre.tampon_instances(Basis.IDENTITY, vers_centre))
	materiau.set_shader_parameter("maintenant", temps)
	materiau.set_shader_parameter("profondeur_pres", camera.near)
	materiau.set_shader_parameter("profondeur_loin", camera.far)
	materiau.set_shader_parameter("centre_planete", Vector3(vers_centre[0], vers_centre[1], vers_centre[2]))
	chrono.fin(ChronoBoucle.ENVOYER)
	chrono.nb_rayons = arbre.nb_rayons()


## Le posemètre : luminance (cd/m²) de 16 × 9 cases de l'écran, tirée des rayons affichés.
func posemetre(camera: Camera3D, oeil: PackedFloat64Array, soleil_dir: Vector3, eclairement: float,
		fond: float) -> PackedFloat32Array:
	var b := camera.global_transform.basis
	var axes := PackedFloat32Array([-b.z.x, -b.z.y, -b.z.z, b.x.x, b.x.y, b.x.z, b.y.x, b.y.y, b.y.z])
	var taille := camera.get_viewport().get_visible_rect().size
	var tan_v := tan(deg_to_rad(camera.fov) * 0.5)
	return arbre.posemetre(oeil, axes, tan_v * taille.x / taille.y, tan_v, soleil_dir, eclairement, fond)


## Hauteur du sol (m au-dessus du rayon) sous la position p (repère de la planète).
func hauteur_sol(p: PackedFloat64Array) -> float:
	return arbre.hauteur_sol(p)
