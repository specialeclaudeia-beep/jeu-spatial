// Une vitre (étape 8, la verrière du cockpit ; reflets complets à l'étape 9), vue par le système de lumière.
// La verrière est une lame d'acrylique (indice 1,49) : à chaque surface, la loi de Fresnel renvoie
// 4 % de la lumière de face, beaucoup plus en biais ; la lumière fait des allers-retours entre les deux
// surfaces → part renvoyée 2R / (1 + R), part transmise (1 − R) / (1 + R) (rien n'est perdu).
// Ce qu'on voit dans le reflet (loi du miroir) : l'intérieur du cockpit (sonde par rayons), la planète
// (carte du ciel tirée des rayons), le Soleil et l'étoile compagne (disques exacts). Voir reflets.gdshaderinc.
// Ce qu'il y a derrière la vitre est relu à l'écran, ramené en luminance, multiplié par la part transmise,
// puis le reflet est ajouté, et le tout repasse par l'œil.
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, fog_disabled;

#include "res://scripts/lumiere/oeil.gdshaderinc"
#include "res://scripts/lumiere/compagnon.gdshaderinc"
#include "res://scripts/lumiere/objets.gdshaderinc"
#include "res://scripts/lumiere/reflets.gdshaderinc"

uniform float indice = 1.49;
uniform sampler2D image_derriere : hint_screen_texture, filter_nearest;

void fragment() {
	vec3 p = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 v = normalize((INV_VIEW_MATRIX * vec4(VIEW, 0.0)).xyz);   // vers l'œil
	vec3 n = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	if (dot(n, v) < 0.0) n = -n;
	float c = clamp(dot(n, v), 0.0, 1.0);
	float f0 = pow((indice - 1.0) / (indice + 1.0), 2.0);
	float r1 = f0 + (1.0 - f0) * pow(1.0 - c, 5.0);
	float part_renvoyee = 2.0 * r1 / (1.0 + r1);
	float part_transmise = (1.0 - r1) / (1.0 + r1);
	vec3 r = reflect(-v, n);
	vec3 l_reflet = part_renvoyee * reflets_luminance(p, r, 0.0, objets_soleil_visible, objets_compagnon_visible, 1.0);
	vec3 derriere = texture(image_derriere, SCREEN_UV).rgb;
	vec3 l_derriere = reflets_ecran_vers_luminance(derriere);
	// Même calcul de l'œil des deux côtés : les erreurs de l'inversion (vision de nuit) s'annulent.
	vec3 avant = oeil_vers_ecran(l_derriere, FRAGCOORD.xy, TIME);
	vec3 apres = oeil_vers_ecran(l_derriere * part_transmise + l_reflet, FRAGCOORD.xy, TIME);
	ALBEDO = clamp(derriere + apres - avant, 0.0, 1.0);
	ALPHA = 1.0;
	DEPTH = profondeur_log(-VERTEX.z);
}
