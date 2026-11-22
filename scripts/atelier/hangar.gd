extends Node3D
## Le hangar de l'atelier (décor PROVISOIRE, voulu léger pour le PC : une soixantaine de boîtes, une seule
## lumière avec ombres). Le vaisseau est posé au centre, nez vers la grande porte (−Z) : c'est par là
## qu'il sort, et le vol commence « devant le hangar ».
## Le sol porte une grille comme celle de Blender (1 m, 5 m, axes rouge et vert) et la zone de montage.
## « Fond neutre » (vue technique) : murs et toit cachés, fond gris uni, il ne reste que la grille.
## Étape 4 : la SALLE À PART. Le hangar disparaît (sol, murs, dehors) ; à sa place, une salle sombre avec
## un plateau rond éclairé, juste sous la pièce qu'on y a emmenée seule pour l'analyser.

const LARGEUR := 64.0       # m (x)
const ARRIERE := 26.0       # m : mur du fond à z = +26
const AVANT := -34.0        # m : mur de la porte à z = −34
const HAUTEUR := 21.0       # m
const PORTE_LARGEUR := 34.0
const PORTE_HAUTEUR := 15.0
const FOND_JOUR := Color(0.5, 0.6, 0.74)   # dehors, vu par la porte
const FOND_NEUTRE := Color(0.235, 0.235, 0.24)
const FOND_SALLE := Color(0.055, 0.066, 0.09)

## Le plateau de la salle à part : métal sombre, cercles tous les mètres, rayons tous les 30°, bord lumineux.
const SHADER_PLATEAU := """
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;
uniform float rayon = 5.0;
varying vec3 pos_local;

void vertex() {
	pos_local = VERTEX;
}

float trait(float x, float largeur) {
	float fw = fwidth(x) * 0.9;
	return 1.0 - smoothstep(largeur * 0.5, largeur * 0.5 + fw, abs(x));
}

void fragment() {
	vec2 p = pos_local.xz * rayon;
	float r = length(p);
	float a = atan(p.y, p.x);
	vec3 c = vec3(0.13, 0.145, 0.17);
	c = mix(c, vec3(0.24, 0.29, 0.35), 0.8 * trait(fract(r + 0.5) - 0.5, 0.025));
	c = mix(c, vec3(0.22, 0.27, 0.33), 0.6 * trait(fract(a / 0.5235988 + 0.5) - 0.5, 0.03 / max(r, 0.3)) * step(0.6, r));
	float bord = smoothstep(rayon - 0.35, rayon - 0.08, r);
	c = mix(c, vec3(0.3, 0.75, 1.0), bord * 0.85);
	ALBEDO = c;
	EMISSION = vec3(0.3, 0.75, 1.0) * bord * 0.9;
	ROUGHNESS = 0.55;
	METALLIC = 0.4;
}
"""

const SHADER_SOL := """
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;
uniform float technique = 0.0;   // 1 = fond neutre (seulement la grille)
varying vec3 pos_monde;

void vertex() {
	pos_monde = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float bruit(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	float a = fract(sin(dot(i, vec2(12.9898, 78.233))) * 43758.5453);
	float b = fract(sin(dot(i + vec2(1.0, 0.0), vec2(12.9898, 78.233))) * 43758.5453);
	float c = fract(sin(dot(i + vec2(0.0, 1.0), vec2(12.9898, 78.233))) * 43758.5453);
	float d = fract(sin(dot(i + vec2(1.0, 1.0), vec2(12.9898, 78.233))) * 43758.5453);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

// 1 sur une ligne tous les « pas » mètres (largeur en mètres), adoucie selon la taille du pixel
float lignes(vec2 p, float pas, float largeur) {
	vec2 q = p / pas;
	vec2 d = abs(fract(q + 0.5) - 0.5) * pas;
	vec2 fw = fwidth(p) * 0.9;
	vec2 l = 1.0 - smoothstep(vec2(largeur * 0.5), vec2(largeur * 0.5) + fw, d);
	return max(l.x, l.y);
}

float bande(float x, float largeur) {
	float fw = fwidth(x) * 0.9;
	return 1.0 - smoothstep(largeur * 0.5, largeur * 0.5 + fw, abs(x));
}

void fragment() {
	vec2 p = pos_monde.xz;
	float n = bruit(p * 0.7) * 0.6 + bruit(p * 3.1) * 0.3 + bruit(p * 13.0) * 0.1;
	vec3 beton = vec3(0.30, 0.31, 0.33) * (0.86 + 0.22 * n);
	vec3 neutre = vec3(0.26, 0.26, 0.27);
	vec3 c = mix(beton, neutre, technique);
	// dalles de béton de 5 m (joints sombres), puis grille façon Blender
	c *= 1.0 - 0.35 * lignes(p, 5.0, 0.05) * (1.0 - technique);
	vec3 trait = mix(vec3(0.42, 0.44, 0.47), vec3(0.36, 0.36, 0.37), technique);
	c = mix(c, trait, 0.55 * lignes(p, 1.0, 0.018));
	c = mix(c, trait * 1.25, 0.75 * lignes(p, 5.0, 0.035));
	// axes : X en rouge, avant-arrière en vert (comme Blender)
	c = mix(c, vec3(0.75, 0.22, 0.22), bande(p.y, 0.06));
	c = mix(c, vec3(0.42, 0.66, 0.18), bande(p.x, 0.06));
	// zone de montage (jaune) et sortie vers la porte (hachures), seulement dans le hangar
	float zone = max(max(bande(abs(p.x) - 11.0, 0.18) * step(abs(p.y), 12.0), bande(abs(p.y) - 12.0, 0.18) * step(abs(p.x), 11.0)), 0.0);
	float sortie = step(abs(p.x), 9.0) * step(p.y, -12.5) * step(-31.0, p.y) * step(0.5, fract((p.x + p.y) * 0.35)) * bande(abs(p.x) - 8.5, 1.0);
	c = mix(c, vec3(0.86, 0.66, 0.12), max(zone, sortie * 0.85) * (1.0 - technique));
	ALBEDO = c;
	ROUGHNESS = 0.78;
	SPECULAR = 0.35;
}
"""

var sol: MeshInstance3D
var materiau_sol: ShaderMaterial
var decor: Node3D            # murs, toit, poutres, caisses (cachés en fond neutre)
var dehors: Node3D           # le sol devant la porte
var environnement: Environment
var lumiere_toit: DirectionalLight3D
var lumiere_douce: DirectionalLight3D
var technique := false
var en_salle := false        # la salle à part est montrée (le hangar est caché)
var salle: Node3D            # la salle à part : son plateau
var plateau: MeshInstance3D
var materiau_plateau: ShaderMaterial


func _ready() -> void:
	name = "Hangar"
	_creer_lumieres()
	_creer_sol()
	decor = Node3D.new()
	decor.name = "Decor"
	add_child(decor)
	_creer_murs()
	_creer_toit()
	# murs et toit ne font pas d'ombre (la lumière du toit vient des verrières) : seuls le vaisseau et
	# les équipements posés au sol en font
	for n in decor.get_children():
		(n as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_creer_equipements()


func _creer_lumieres() -> void:
	environnement = Environment.new()
	environnement.background_mode = Environment.BG_COLOR
	environnement.background_color = FOND_JOUR
	environnement.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environnement.ambient_light_color = Color(0.62, 0.67, 0.76)
	environnement.ambient_light_energy = 0.55
	environnement.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environnement.tonemap_exposure = 0.88
	var we := WorldEnvironment.new()
	we.environment = environnement
	add_child(we)
	# lumière du toit (verrières) : la seule avec des ombres
	lumiere_toit = DirectionalLight3D.new()
	lumiere_toit.name = "Lumiere_toit"
	lumiere_toit.light_energy = 1.2
	lumiere_toit.light_color = Color(1.0, 0.97, 0.92)
	lumiere_toit.shadow_enabled = true
	lumiere_toit.shadow_bias = 0.04
	lumiere_toit.directional_shadow_max_distance = 70.0
	lumiere_toit.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	add_child(lumiere_toit)
	lumiere_toit.basis = Basis.looking_at(Vector3(0.35, -1.0, 0.25).normalized(), Vector3.FORWARD)
	# lumière douce d'appoint (les grandes lampes du côté de la porte), sans ombres
	lumiere_douce = DirectionalLight3D.new()
	lumiere_douce.name = "Lumiere_douce"
	lumiere_douce.light_energy = 0.45
	lumiere_douce.light_color = Color(0.78, 0.86, 1.0)
	lumiere_douce.shadow_enabled = false
	add_child(lumiere_douce)
	lumiere_douce.basis = Basis.looking_at(Vector3(-0.4, -0.45, 0.8).normalized(), Vector3.UP)


func _creer_sol() -> void:
	materiau_sol = ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = SHADER_SOL
	materiau_sol.shader = sh
	var m := PlaneMesh.new()
	m.size = Vector2(LARGEUR, ARRIERE - AVANT)
	sol = MeshInstance3D.new()
	sol.name = "Sol"
	sol.mesh = m
	sol.position = Vector3(0, 0, (ARRIERE + AVANT) * 0.5)
	sol.material_override = materiau_sol
	sol.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(sol)
	# dehors : la piste devant la porte, en plein jour
	dehors = Node3D.new()
	dehors.name = "Dehors"
	add_child(dehors)
	var piste := PlaneMesh.new()
	piste.size = Vector2(400.0, 300.0)
	var mp := MeshInstance3D.new()
	mp.mesh = piste
	mp.position = Vector3(0, -0.02, AVANT - 150.0)
	mp.material_override = _matiere(Color(0.56, 0.55, 0.52), 0.95)
	mp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	dehors.add_child(mp)
	# collines au loin (simples boîtes très plates, couleur de roche)
	for i in 7:
		var b := BoxMesh.new()
		b.size = Vector3(120.0 + 30.0 * (i % 3), 18.0 + 9.0 * ((i * 5) % 4), 40.0)
		var mi := MeshInstance3D.new()
		mi.mesh = b
		mi.position = Vector3(-260.0 + i * 85.0, b.size.y * 0.3, AVANT - 290.0 - 20.0 * (i % 2))
		mi.rotation = Vector3(0, 0.2 * ((i % 3) - 1), 0)
		mi.material_override = _matiere(Color(0.5, 0.45, 0.4).lerp(Color(0.62, 0.66, 0.74), 0.35), 1.0)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		dehors.add_child(mi)


func _creer_murs() -> void:
	var metal := _matiere(Color(0.33, 0.36, 0.4), 0.7, 0.35)
	var metal_sombre := _matiere(Color(0.18, 0.2, 0.23), 0.6, 0.5)
	var jaune := _matiere(Color(0.85, 0.62, 0.1), 0.6)
	var x0 := -LARGEUR * 0.5
	var x1 := LARGEUR * 0.5
	var profondeur := ARRIERE - AVANT
	# mur du fond et murs de côté (épaisseur 0,6 m)
	_boite(decor, Vector3(LARGEUR, HAUTEUR, 0.6), Vector3(0, HAUTEUR * 0.5, ARRIERE + 0.3), metal)
	_boite(decor, Vector3(0.6, HAUTEUR, profondeur), Vector3(x0 - 0.3, HAUTEUR * 0.5, (ARRIERE + AVANT) * 0.5), metal)
	_boite(decor, Vector3(0.6, HAUTEUR, profondeur), Vector3(x1 + 0.3, HAUTEUR * 0.5, (ARRIERE + AVANT) * 0.5), metal)
	# mur de la porte : deux côtés et le linteau
	var cote := (LARGEUR - PORTE_LARGEUR) * 0.5
	_boite(decor, Vector3(cote, HAUTEUR, 0.6), Vector3(x0 + cote * 0.5, HAUTEUR * 0.5, AVANT - 0.3), metal)
	_boite(decor, Vector3(cote, HAUTEUR, 0.6), Vector3(x1 - cote * 0.5, HAUTEUR * 0.5, AVANT - 0.3), metal)
	_boite(decor, Vector3(PORTE_LARGEUR, HAUTEUR - PORTE_HAUTEUR, 0.6), Vector3(0, (HAUTEUR + PORTE_HAUTEUR) * 0.5, AVANT - 0.3), metal)
	# cadre de la porte (jaune), et rail de la porte coulissante
	_boite(decor, Vector3(0.8, PORTE_HAUTEUR, 1.0), Vector3(-PORTE_LARGEUR * 0.5, PORTE_HAUTEUR * 0.5, AVANT), jaune)
	_boite(decor, Vector3(0.8, PORTE_HAUTEUR, 1.0), Vector3(PORTE_LARGEUR * 0.5, PORTE_HAUTEUR * 0.5, AVANT), jaune)
	_boite(decor, Vector3(PORTE_LARGEUR + 0.8, 0.8, 1.0), Vector3(0, PORTE_HAUTEUR + 0.4, AVANT), jaune)
	# piliers tous les 7 m le long des murs, poutre horizontale à mi-hauteur (passerelle)
	var z := ARRIERE
	while z > AVANT + 1.0:
		for x in [x0 + 0.5, x1 - 0.5]:
			_boite(decor, Vector3(0.7, HAUTEUR, 0.7), Vector3(x, HAUTEUR * 0.5, z), metal_sombre)
		z -= 7.5
	var x := x0 + 4.0
	while x < x1 - 1.0:
		_boite(decor, Vector3(0.7, HAUTEUR, 0.7), Vector3(x, HAUTEUR * 0.5, ARRIERE - 0.5), metal_sombre)
		x += 8.0
	for cote_x in [x0 + 1.6, x1 - 1.6]:
		_boite(decor, Vector3(2.4, 0.25, profondeur - 2.0), Vector3(cote_x, 7.0, (ARRIERE + AVANT) * 0.5 + 0.5), metal_sombre)
		_boite(decor, Vector3(0.08, 1.0, profondeur - 2.0), Vector3(cote_x + (1.15 if cote_x < 0 else -1.15), 7.6, (ARRIERE + AVANT) * 0.5 + 0.5), jaune)


func _creer_toit() -> void:
	var metal_sombre := _matiere(Color(0.16, 0.17, 0.2), 0.7, 0.4)
	var lampe := _matiere(Color(1.0, 0.98, 0.94), 0.5)
	lampe.emission_enabled = true
	lampe.emission = Color(1.0, 0.97, 0.9)
	lampe.emission_energy_multiplier = 2.2
	var profondeur := ARRIERE - AVANT
	_boite(decor, Vector3(LARGEUR + 1.2, 0.5, profondeur + 1.2), Vector3(0, HAUTEUR + 0.25, (ARRIERE + AVANT) * 0.5), metal_sombre)
	# fermes du toit (poutres en travers) et rangées de lampes
	var z := ARRIERE - 3.0
	while z > AVANT + 2.0:
		_boite(decor, Vector3(LARGEUR, 1.1, 0.45), Vector3(0, HAUTEUR - 0.6, z), metal_sombre)
		for x in [-18.0, -6.0, 6.0, 18.0]:
			var l := _boite(decor, Vector3(5.0, 0.15, 1.2), Vector3(x, HAUTEUR - 1.25, z - 3.0), lampe)
			l.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		z -= 7.5


func _creer_equipements() -> void:
	var caisse := _matiere(Color(0.42, 0.36, 0.27), 0.9)
	var bleu := _matiere(Color(0.16, 0.3, 0.5), 0.6, 0.3)
	var gris := _matiere(Color(0.46, 0.48, 0.5), 0.6, 0.5)
	var rouge := _matiere(Color(0.6, 0.16, 0.13), 0.6, 0.2)
	# caisses le long du mur gauche
	for i in 6:
		var s := 1.0 + 0.25 * (i % 3)
		_boite(decor, Vector3(s, s, s), Vector3(-29.0 + (i % 2) * 1.3, s * 0.5 + (1.05 if i >= 4 else 0.0), 14.0 - i * 1.6), caisse)
	# établis et armoires à outils le long du mur du fond
	for i in 4:
		_boite(decor, Vector3(3.2, 0.9, 1.1), Vector3(-14.0 + i * 6.0, 0.45, ARRIERE - 1.6), gris)
		_boite(decor, Vector3(1.2, 2.0, 0.6), Vector3(-11.5 + i * 6.0, 1.0, ARRIERE - 1.2), bleu if i % 2 == 0 else rouge)
	# chariot élévateur stylisé, à droite
	_boite(decor, Vector3(1.6, 1.2, 2.6), Vector3(24.0, 0.8, 6.0), _matiere(Color(0.85, 0.62, 0.1), 0.6))
	_boite(decor, Vector3(0.15, 3.0, 0.15), Vector3(23.4, 1.5, 4.6), gris)
	_boite(decor, Vector3(0.15, 3.0, 0.15), Vector3(24.6, 1.5, 4.6), gris)
	# échafaudage de maintenance (à côté de la zone de montage)
	for k in 4:
		var px := 14.5 + (k % 2) * 3.0
		var pz := -4.0 + (k / 2) * 3.0
		_boite(decor, Vector3(0.12, 6.0, 0.12), Vector3(px, 3.0, pz), gris)
	for h in [2.0, 4.0, 6.0]:
		_boite(decor, Vector3(3.3, 0.12, 3.3), Vector3(16.0, h, -2.5), gris)


## Fond neutre (vue technique, façon logiciel de dessin) ou hangar.
func vue_technique(oui: bool) -> void:
	technique = oui
	_appliquer()


## La salle à part (oui) ou le hangar (non). centre : sous quoi poser le plateau (repère du monde) ;
## bas : hauteur du dessus du plateau ; rayon : du plateau (m).
func salle_a_part(oui: bool, centre := Vector3.ZERO, bas := 0.0, rayon := 4.0) -> void:
	en_salle = oui
	if oui:
		if salle == null:
			_creer_salle()
		rayon = clampf(rayon, 2.0, 30.0)
		salle.position = Vector3(centre.x, bas, centre.z)
		salle.scale = Vector3(rayon, 1.0, rayon)
		materiau_plateau.set_shader_parameter("rayon", rayon)
	_appliquer()


func _appliquer() -> void:
	sol.visible = not en_salle
	decor.visible = not technique and not en_salle
	dehors.visible = not technique and not en_salle
	if salle != null:
		salle.visible = en_salle
	materiau_sol.set_shader_parameter("technique", 1.0 if technique else 0.0)
	if en_salle:
		environnement.background_color = FOND_SALLE
		environnement.ambient_light_energy = 0.7
	else:
		environnement.background_color = FOND_NEUTRE if technique else FOND_JOUR
		environnement.ambient_light_energy = 0.75 if technique else 0.55


func _creer_salle() -> void:
	salle = Node3D.new()
	salle.name = "Salle_a_part"
	add_child(salle)
	materiau_plateau = ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = SHADER_PLATEAU
	materiau_plateau.shader = sh
	var c := CylinderMesh.new()
	c.top_radius = 1.0
	c.bottom_radius = 1.0
	c.height = 0.06
	c.radial_segments = 64
	c.rings = 1
	plateau = MeshInstance3D.new()
	plateau.name = "Plateau"
	plateau.mesh = c
	plateau.position = Vector3(0.0, -0.03, 0.0)
	plateau.material_override = materiau_plateau
	plateau.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	salle.add_child(plateau)


func _boite(parent: Node3D, taille: Vector3, position: Vector3, matiere: Material) -> MeshInstance3D:
	var b := BoxMesh.new()
	b.size = taille
	var mi := MeshInstance3D.new()
	mi.mesh = b
	mi.position = position
	mi.material_override = matiere
	parent.add_child(mi)
	return mi


static func _matiere(c: Color, rugosite := 0.8, metal := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rugosite
	m.metallic = metal
	return m
