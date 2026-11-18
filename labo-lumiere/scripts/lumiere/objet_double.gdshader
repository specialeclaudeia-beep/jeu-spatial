// Version à deux faces (matière « double face » du modèle, comme le cockpit).
// Les objets proches éclairés par le système de lumière (étape 8) : le vaisseau et son cockpit.
// Comme la planète, chaque pixel calcule une vraie luminance (cd/m²) puis passe par l'œil du pilote
// (oeil.gdshaderinc). Lumières : le Soleil (avec les ombres du vaisseau sur lui-même, calculées par
// Godot : c'est la seule lumière de Godot dans la scène), l'étoile compagne, la lumière renvoyée par la
// planète, les lampes du vaisseau, le fond du ciel, et ce que l'objet émet lui-même (écrans, voyants).
// La lumière du Soleil est ajoutée dans light() (là où Godot connaît l'ombre), le reste dans fragment().
// La profondeur est la même profondeur logarithmique que la planète.
shader_type spatial;
render_mode cull_disabled, ambient_light_disabled, fog_disabled;


#include "res://scripts/lumiere/objet_commun.gdshaderinc"
