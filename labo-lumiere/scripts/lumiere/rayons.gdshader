// Dessin des rayons (programme, partie 5, temps 4 « dessiner »).
// Chaque copie du morceau type (MultiMesh) est un triangle de la planète ; chaque petit triangle
// lit SON rayon dans la texture : couleur du sol (texel pair) et direction moyenne non normalisée
// (texel impair : sa longueur dit l'étalement). La lumière directe du Soleil est calculée ici,
// à chaque pixel (décision Q43 = version B).
shader_type spatial;
render_mode unshaded, cull_disabled, skip_vertex_transform;

uniform sampler2D rayons : filter_nearest;   // 2 texels par rayon, 256 rayons par ligne
uniform vec3 soleil = vec3(0.6, 0.3, 0.74);  // direction vers le Soleil (repère du monde)
uniform float rayon_planete = 1000.0;
uniform float lumiere_soleil = 1.0;

varying flat int indice;
varying vec3 normale_monde;

void vertex() {
	// Coin du morceau sur le triangle plat, puis remonté sur la sphère.
	vec3 p = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	p = normalize(p) * rayon_planete;
	normale_monde = normalize(p);
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
	vec3 c = couleur.rgb * (direct * lumiere_soleil + 0.01);
	// Tramage : un petit bruit de ±½ niveau contre les bandes des couleurs 8 bits.
	float bruit = fract(sin(dot(FRAGCOORD.xy, vec2(12.9898, 78.233))) * 43758.5453);
	ALBEDO = c + (bruit - 0.5) / 255.0;
}
