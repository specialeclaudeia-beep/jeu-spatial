// Dessin des rayons (programme, partie 5, temps 4 « dessiner »).
// Chaque copie du morceau type (MultiMesh) est un triangle de la planète ; chaque petit triangle
// lit SON rayon dans la texture : couleur du sol (texel pair) et direction moyenne non normalisée
// (texel impair : sa longueur dit l'étalement). La lumière directe du Soleil est calculée ici,
// à chaque pixel (décision Q43 = version B). Depuis l'étape 3 : la lumière est en vraies unités
// (cd/m²) et passe par l'œil du pilote (oeil.gdshaderinc) avant l'écran.
shader_type spatial;
render_mode unshaded, cull_disabled, skip_vertex_transform;

#include "res://scripts/lumiere/oeil.gdshaderinc"

uniform sampler2D rayons : filter_nearest;   // 2 texels par rayon, 256 rayons par ligne
uniform vec3 soleil = vec3(0.6, 0.3, 0.74);  // direction vers le Soleil (repère du monde)
uniform float rayon_planete = 1000.0;
uniform float lumiere_soleil = 1.0;          // part de l'éclairement du Soleil reçue (ombres)

varying flat int indice;
varying vec3 normale_monde;
varying vec3 pos_monde;

void vertex() {
	// Coin du morceau sur le triangle plat, puis remonté sur la sphère.
	vec3 p = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	p = normalize(p) * rayon_planete;
	normale_monde = normalize(p);
	pos_monde = p;
	indice = INSTANCE_ID * 64 + int(UV.x);
	POSITION = PROJECTION_MATRIX * (VIEW_MATRIX * vec4(p, 1.0));
}

void fragment() {
	ivec2 t = ivec2((indice % 256) * 2, indice / 256);
	vec4 couleur = texelFetch(rayons, t, 0);
	vec3 dir = texelFetch(rayons, t + ivec2(1, 0), 0).xyz * 2.0 - 1.0;
	// Direction moyenne non normalisée : plus elle est courte, plus la lumière est « étalée ».
	float etalement = 1.0 - clamp(length(dir), 0.0, 1.0);
	vec3 n = normalize(mix(normale_monde, dir, 0.7) + 1e-5);
	float direct = max(dot(n, normalize(soleil)), 0.0);
	direct = mix(direct, 0.5 * (dot(n, normalize(soleil)) + 1.0) * 0.6, etalement);
	// Sol mat : luminance = couleur du sol × éclairement × cos / π (+ un millième pour la lueur du ciel).
	vec3 l = couleur.rgb * soleil_couleur * soleil_eclairement * lumiere_soleil * (direct + 0.001) / PI;
	vec3 vue = normalize(pos_monde - CAMERA_POSITION_WORLD);
	ALBEDO = oeil_vers_ecran(l + oeil_voile(vue, TIME), FRAGCOORD.xy, TIME);
}
