extends RefCounted
## Les objets proches (étape 8) : le vaisseau et son cockpit, éclairés par le système de lumière.
## Ce fichier fait partie du système : il ne dépend de rien d'autre que de son dossier.
##
## 1. convertir() remplace les matières du modèle 3D (exporté de Blender) par celles du système :
##    objet.gdshader (vraie luminance, ombres du Soleil, œil du pilote, profondeur logarithmique)
##    et vitre.gdshader pour les vitres. Les couleurs du modèle sont gardées.
## 2. Le « posemètre » des objets : l'œil doit savoir combien de lumière vient du cockpit qu'il
##    regarde (sinon, la nuit, il s'habitue au ciel noir et le cockpit éclairé l'éblouit). Les formes
##    du modèle sont rangées une fois dans un petit monde à part (repère du vaisseau, jamais déplacé),
##    et chaque case du posemètre y lance un rayon (PhysicsServer3D : quelques microsecondes chacun).
##    Une case qui touche le cockpit reçoit la luminance du point touché ; un second rayon vers le
##    Soleil dit si ce point est à l'ombre.

const ShaderObjet = preload("res://scripts/lumiere/objet.gdshader")
const ShaderObjetDouble = preload("res://scripts/lumiere/objet_double.gdshader")
const ShaderVitre = preload("res://scripts/lumiere/vitre.gdshader")

## Luminance (cd/m²) de ce qu'émettent les surfaces, selon le début du nom de leur matière.
## Un écran d'ordinateur ou de tableau de bord : 100 à 300 cd/m² ; un voyant : quelques dizaines.
## Lampe et tuyères : réglées à chaque image par le jeu (allumées ou non, poussée des moteurs).
const EMISSIONS := {"Ecran": 120.0, "Voyant": 40.0, "Lampe": 0.0, "Tuyere": 0.0}
const FOND := 2.0e-4                   # lux du fond du ciel (comme la planète)

var materiaux: Array[ShaderMaterial] = []
## nom de la matière du modèle → ses matières du système (pour régler lampes et tuyères)
var par_nom: Dictionary = {}
var nb_faces := 0

var _espace := RID()
var _corps := RID()
var _forme := RID()
var _faces_albedo := PackedFloat32Array()      # 3 nombres par face (couleur linéaire)
var _faces_emission := PackedFloat32Array()    # luminance émise par face (cd/m²)
var _faces_emis_couleur := PackedFloat32Array() # 3 nombres par face : couleur de l'émission (étape 9)
var _faces_matiere := PackedStringArray()


## Remplace les matières de tous les maillages sous `racine`, et range leurs faces (repère de
## `reference`, le nœud qui suit le vaisseau) pour le posemètre. Les vitres ne font pas d'ombre et
## ne comptent pas dans le posemètre (on voit à travers).
func convertir(racine: Node3D, reference: Node3D) -> void:
	var faces := PackedVector3Array()
	for n in racine.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.mesh == null:
			continue
		var t := _transformation(mi, reference)
		var noeud_vitre := mi.name.to_lower().contains("verriere") and not mi.name.to_lower().contains("cadre")
		for i in mi.mesh.get_surface_count():
			var m := mi.get_active_material(i) as BaseMaterial3D
			if m == null:
				continue
			var nom := m.resource_name
			var vitre := m.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED
			var nouveau := ShaderMaterial.new()
			if vitre:
				nouveau.shader = ShaderVitre
			else:
				nouveau.shader = ShaderObjetDouble if m.cull_mode == BaseMaterial3D.CULL_DISABLED else ShaderObjet
				var a := m.albedo_color.srgb_to_linear()
				nouveau.set_shader_parameter("albedo_lin", Vector3(a.r, a.g, a.b))
				if m.albedo_texture:
					nouveau.set_shader_parameter("tex_albedo", m.albedo_texture)
				nouveau.set_shader_parameter("metal", m.metallic)
				nouveau.set_shader_parameter("rugosite", m.roughness)
				var lum := 0.0
				if m.emission_enabled:
					lum = _emission(nom)
					var e := m.emission.srgb_to_linear()
					nouveau.set_shader_parameter("emission_couleur", Vector3(e.r, e.g, e.b))
					if m.emission_texture:
						nouveau.set_shader_parameter("tex_emission", m.emission_texture)
				nouveau.set_shader_parameter("emission_luminance", lum)
			nouveau.resource_name = nom
			mi.set_surface_override_material(i, nouveau)
			materiaux.append(nouveau)
			if not par_nom.has(nom):
				par_nom[nom] = []
			(par_nom[nom] as Array).append(nouveau)
			if vitre or noeud_vitre:
				continue
			_ranger_faces(mi.mesh, i, t, m, faces)
		if noeud_vitre:
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if faces.is_empty():
		return
	if not _espace.is_valid():
		_espace = PhysicsServer3D.space_create()
		PhysicsServer3D.space_set_active(_espace, true)
	_creer_corps(faces)


## Émission d'une matière (cd/m²) d'après le début de son nom.
static func _emission(nom: String) -> float:
	for debut in EMISSIONS:
		if nom.begins_with(debut):
			return EMISSIONS[debut]
	return 50.0


## Transformation du maillage dans le repère de `reference` (sans passer par l'arbre de scène).
static func _transformation(n: Node3D, reference: Node3D) -> Transform3D:
	var t := Transform3D.IDENTITY
	var x: Node = n
	while x != null and x != reference:
		if x is Node3D:
			t = (x as Node3D).transform * t
		x = x.get_parent()
	return t


func _ranger_faces(mesh: Mesh, surface: int, t: Transform3D, m: BaseMaterial3D, faces: PackedVector3Array) -> void:
	var tableaux := mesh.surface_get_arrays(surface)
	var sommets: PackedVector3Array = tableaux[Mesh.ARRAY_VERTEX]
	var indices: PackedInt32Array = tableaux[Mesh.ARRAY_INDEX] if tableaux[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
	var a := m.albedo_color.srgb_to_linear()
	var lum := _emission(m.resource_name) if m.emission_enabled else 0.0
	var ec := m.emission.srgb_to_linear() if m.emission_enabled else Color.WHITE
	var y_ec := 0.2126 * ec.r + 0.7152 * ec.g + 0.0722 * ec.b
	ec = Color(ec.r / y_ec, ec.g / y_ec, ec.b / y_ec) if y_ec > 1e-6 else Color.WHITE
	var nb := indices.size() / 3 if not indices.is_empty() else sommets.size() / 3
	for f in nb:
		for k in 3:
			var j := indices[f * 3 + k] if not indices.is_empty() else f * 3 + k
			faces.append(t * sommets[j])
		_faces_albedo.append_array([a.r, a.g, a.b])
		_faces_emission.append(lum)
		_faces_emis_couleur.append_array([ec.r, ec.g, ec.b])
		_faces_matiere.append(m.resource_name)
	nb_faces = _faces_emission.size()


func _creer_corps(faces: PackedVector3Array) -> void:
	if _corps.is_valid():
		PhysicsServer3D.free_rid(_corps)
		PhysicsServer3D.free_rid(_forme)
	_forme = PhysicsServer3D.concave_polygon_shape_create()
	PhysicsServer3D.shape_set_data(_forme, {"faces": faces, "backface_collision": true})
	_corps = PhysicsServer3D.body_create()
	PhysicsServer3D.body_set_mode(_corps, PhysicsServer3D.BODY_MODE_STATIC)
	PhysicsServer3D.body_add_shape(_corps, _forme)
	PhysicsServer3D.body_set_space(_corps, _espace)


## Perce un trou dans l'ombre d'un maillage (boîte donnée dans le repère de `reference`) : par exemple la
## coque sous la verrière, qui sinon mettrait tout le cockpit à l'ombre.
func percer_ombre(mi: MeshInstance3D, boite: AABB, reference: Node3D) -> void:
	var inv := _transformation(mi, reference).affine_inverse()
	var b := AABB(inv * boite.position, Vector3.ZERO)
	for k in 8:
		b = b.expand(inv * boite.get_endpoint(k))
	for i in mi.mesh.get_surface_count():
		var m := mi.get_surface_override_material(i) as ShaderMaterial
		if m and m.shader != ShaderVitre:
			m.set_shader_parameter("trou_min", b.position)
			m.set_shader_parameter("trou_max", b.end)


## Boîte d'un maillage dans le repère de `reference`.
static func boite(mi: MeshInstance3D, reference: Node3D) -> AABB:
	var t := _transformation(mi, reference)
	var a := mi.get_aabb()
	var b := AABB(t * a.position, Vector3.ZERO)
	for k in 8:
		b = b.expand(t * a.get_endpoint(k))
	return b


## Change la luminance émise par une matière (nom du modèle) : lampe allumée, tuyère qui pousse…
func regler_emission(nom: String, luminance: float) -> void:
	for m in par_nom.get(nom, []):
		(m as ShaderMaterial).set_shader_parameter("emission_luminance", luminance)
	for f in nb_faces:
		if _faces_matiere[f] == nom:
			_faces_emission[f] = luminance


## Rayon dans le repère du vaisseau : {} s'il ne touche rien, sinon position, normale, face.
func toucher(depuis: Vector3, direction: Vector3, longueur := 60.0) -> Dictionary:
	if not _corps.is_valid():
		return {}
	var etat := PhysicsServer3D.space_get_direct_state(_espace)
	if etat == null:
		return {}
	var q := PhysicsRayQueryParameters3D.create(depuis, depuis + direction * longueur)
	q.hit_back_faces = true
	return etat.intersect_ray(q)


## Luminance (cd/m²) vue dans la direction `direction` (repère du vaisseau) depuis `oeil`, ou -1 si le
## rayon ne touche pas le vaisseau. soleil = direction du Soleil (repère du vaisseau), e_soleil = lux
## (part visible comprise), e_autre = lux venus d'ailleurs (compagne, planète, lampes : moyenne).
func luminance_vue(oeil: Vector3, direction: Vector3, soleil: Vector3, e_soleil: float, e_autre: float) -> float:
	var c := luminance_vue_couleur(oeil, direction, soleil, e_soleil, e_autre)
	if c.a <= 0.0:
		return -1.0
	return 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b


## Étape 9 : la même chose en couleur (sonde du cockpit pour les reflets) : Color(rouge, vert, bleu en
## cd/m², alpha = 1 si le rayon touche le vaisseau, 0 sinon).
func luminance_vue_couleur(oeil: Vector3, direction: Vector3, soleil: Vector3, e_soleil: float, e_autre: float) -> Color:
	var r := toucher(oeil, direction)
	if r.is_empty():
		return Color(0.0, 0.0, 0.0, 0.0)
	var f: int = r.get("face_index", -1)
	var alb := Vector3(0.3, 0.3, 0.3)
	var emis := Vector3.ZERO
	if f >= 0 and f < nb_faces:
		alb = Vector3(_faces_albedo[f * 3], _faces_albedo[f * 3 + 1], _faces_albedo[f * 3 + 2])
		emis = Vector3(_faces_emis_couleur[f * 3], _faces_emis_couleur[f * 3 + 1], _faces_emis_couleur[f * 3 + 2]) * _faces_emission[f]
	var n: Vector3 = r["normal"]
	if n.dot(direction) > 0.0:
		n = -n
	var e := e_autre + FOND
	var c := n.dot(soleil)
	if c > 0.0 and e_soleil > 0.0:
		var p: Vector3 = r["position"]
		if toucher(p + n * 0.01, soleil).is_empty():
			e += e_soleil * c
	var l := alb * (e / PI) + emis
	return Color(l.x, l.y, l.z, 1.0)


func liberer() -> void:
	if _corps.is_valid():
		PhysicsServer3D.free_rid(_corps)
		PhysicsServer3D.free_rid(_forme)
		_corps = RID()
	if _espace.is_valid():
		PhysicsServer3D.free_rid(_espace)
		_espace = RID()
