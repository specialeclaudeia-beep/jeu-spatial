// Corps commun de objet.gdshader et objet_double.gdshader (étape 8) : voir objet.gdshader.
#include "res://scripts/lumiere/oeil.gdshaderinc"
#include "res://scripts/lumiere/compagnon.gdshaderinc"
#include "res://scripts/lumiere/lampes.gdshaderinc"
#include "res://scripts/lumiere/objets.gdshaderinc"
#include "res://scripts/lumiere/reflets.gdshaderinc"

uniform vec3 albedo_lin = vec3(0.5);            // couleur de la surface (part de lumière renvoyée, linéaire)
uniform sampler2D tex_albedo : source_color, hint_default_white;
uniform float metal = 0.0;
uniform float rugosite = 0.5;
uniform vec3 emission_couleur = vec3(0.0);      // couleur de ce que la surface émet (luminance 1)
uniform sampler2D tex_emission : source_color, hint_default_white;
uniform float emission_luminance = 0.0;         // cd/m² (écran, voyant, tuyère…)
uniform float lux_fond = 2.0e-4;                // étoiles lointaines et fond du ciel

// Étape 8 : « trou » dans l'ombre (repère du maillage). Une coque qui passe au-dessus du cockpit sous
// la verrière ne doit pas lui faire d'ombre : dans la passe des ombres, ses points dans cette boîte
// sont ignorés. Boîte vide par défaut (min > max).
uniform vec3 trou_min = vec3(1.0);
uniform vec3 trou_max = vec3(-1.0);

varying vec3 pos_maillage;
varying vec3 reste;          // tout sauf le Soleil (cd/m²), passé de fragment() à light()
varying vec3 alb;

void vertex() {
	pos_maillage = VERTEX;
}

void fragment() {
	vec3 a = albedo_lin * texture(tex_albedo, UV).rgb;
	vec3 p = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 n = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	vec3 e = lux_fond + lumiere_planete(p, n) + lampes_eclairement(p, n);
	if (compagnon_eclairement > 0.0) {
		e += compagnon_couleur * compagnon_eclairement * objets_compagnon_visible * max(dot(n, compagnon_direction), 0.0);
	}
	// Étape 9 : la lumière renvoyée par les autres surfaces du cockpit (rebond).
	e += reflets_rebond_cockpit(p, n);
	vec3 emis = emission_couleur * texture(tex_emission, UV).rgb * emission_luminance;
	// Étape 9 : reflet de ce qui entoure l'objet (cockpit, planète), flou selon la rugosité. Le Soleil
	// et la compagne n'y sont pas : leur reflet est calculé dans light() (avec l'ombre).
	vec3 vv = normalize(CAMERA_POSITION_WORLD - p);
	float nv = max(dot(n, vv), 1e-4);
	vec3 f0 = mix(vec3(0.04), a, metal);
	float rg = clamp(rugosite, 0.03, 1.0);
	vec3 autour = reflets_part(f0, rg, nv) * reflets_luminance(p, reflect(-vv, n), rg * rg * 1.2,
		objets_soleil_visible, objets_compagnon_visible, 0.0);
	reste = a * (1.0 - metal) * e / PI + emis + autour + oeil_voile(normalize(p - CAMERA_POSITION_WORLD), TIME);
	alb = a;
	// Godot multiplie la lumière par ALBEDO : on lui donne 1, la vraie couleur est dans notre calcul.
	ALBEDO = vec3(1.0);
	METALLIC = 0.0;
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
	// Passe des ombres (vue du Soleil, projection orthographique) : la profondeur normale.
	if (PROJECTION_MATRIX[3][3] > 0.5) {
		if (all(greaterThan(pos_maillage, trou_min)) && all(lessThan(pos_maillage, trou_max))) {
			discard;
		}
		DEPTH = FRAGCOORD.z;
	} else {
		DEPTH = profondeur_log(-VERTEX.z);
	}
}

void light() {
	// Soleil : éclairement × cos × ombre (ATTENUATION) × part visible du disque.
	float nl = max(dot(NORMAL, LIGHT), 0.0);
	vec3 e = soleil_couleur * (soleil_eclairement * objets_soleil_visible * ATTENUATION * nl);
	vec3 diffus = alb * (1.0 - metal) * e / PI;
	// Reflet du Soleil (loi de Blinn-Phong normalisée, reflet de Schlick) : métal et surfaces lisses.
	vec3 h = normalize(LIGHT + VIEW);
	float r = clamp(rugosite, 0.03, 1.0);
	float m = clamp(2.0 / (r * r * r * r) - 2.0, 1.0, 4096.0);
	float nh = max(dot(NORMAL, h), 0.0);
	vec3 f0 = mix(vec3(0.04), alb, metal);
	vec3 f = f0 + (1.0 - f0) * pow(1.0 - max(dot(h, VIEW), 0.0), 5.0);
	vec3 reflet = f * ((m + 8.0) / (8.0 * PI)) * pow(nh, m) * e;
	DIFFUSE_LIGHT = oeil_vers_ecran(reste + diffus + reflet, FRAGCOORD.xy, TIME);
	SPECULAR_LIGHT = vec3(0.0);
}
