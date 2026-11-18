// Une vitre (étape 8 : la verrière du cockpit), vue par le système de lumière. Elle laisse passer
// presque toute la lumière et en renvoie un peu (loi de Fresnel : 4 % de face, beaucoup plus en biais).
// Ici seulement le reflet du Soleil (son disque, très lumineux) ; les reflets du ciel, de la planète et
// du cockpit viendront à l'étape 9.
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, fog_disabled;

#include "res://scripts/lumiere/oeil.gdshaderinc"
#include "res://scripts/lumiere/objets.gdshaderinc"

void fragment() {
	vec3 v = normalize((INV_VIEW_MATRIX * vec4(VIEW, 0.0)).xyz);   // vers l'œil
	vec3 n = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	if (dot(n, v) < 0.0) n = -n;
	float c = clamp(dot(n, v), 0.0, 1.0);
	float f = 0.04 + 0.96 * pow(1.0 - c, 5.0);
	vec3 refl = reflect(-v, n);
	// Le disque du Soleil vu dans la vitre (adouci sur un pixel).
	float th = atan(length(cross(refl, soleil_direction)), dot(refl, soleil_direction));
	float disque = clamp((soleil_rayon_angle - th) / max(oeil_pixel_angle, 1e-6) + 0.5, 0.0, 1.0);
	vec3 l = soleil_couleur * soleil_luminance * 0.8 * disque * f * objets_soleil_visible;
	ALBEDO = max(oeil_vers_ecran(l, FRAGCOORD.xy, TIME) - oeil_vers_ecran(vec3(0.0), FRAGCOORD.xy, TIME), vec3(0.0));
	DEPTH = profondeur_log(-VERTEX.z);
}
