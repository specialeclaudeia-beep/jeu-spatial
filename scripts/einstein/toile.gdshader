// Einstein B : la « toile de l'espace » (voir scripts/einstein/toile.gd). Des lignes lumineuses affichées
// (comme un instrument), toujours de la même luminosité à l'écran, quel que soit l'éblouissement de l'œil.
// Elles sont cachées par ce qui est devant elles (cockpit, planète) : même profondeur logarithmique.
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, fog_disabled, shadows_disabled;

#include "res://scripts/lumiere/oeil.gdshaderinc"
#include "res://scripts/lumiere/objets.gdshaderinc"

uniform float force = 0.6;     // luminosité des lignes à l'écran (0 à 1)

varying float profondeur;

void vertex() {
	vec4 vue = MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	profondeur = -vue.z;
	POSITION = PROJECTION_MATRIX * vue;
	POSITION.z = 0.0;   // jamais coupée aux plans proche et lointain (profondeur écrite plus bas)
}

void fragment() {
	ALBEDO = COLOR.rgb * force;
	DEPTH = profondeur_log(profondeur);
}
