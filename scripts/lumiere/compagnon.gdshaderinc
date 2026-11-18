// L'étoile compagne (étape 6, scripts/lumiere/etoile_proche.gd) : une 2e étoile proche, en plus du Soleil.
// Ses réglages viennent du processeur à chaque image, comme ceux du Soleil (section [shader_globals]
// de project.godot). Éclairement 0 = éteinte.

global uniform vec3 compagnon_direction;     // direction vers elle, repère d'affichage, longueur 1
global uniform float compagnon_eclairement;  // lux qu'elle donne face à elle
global uniform float compagnon_luminance;    // luminance moyenne de son disque, cd/m²
global uniform float compagnon_rayon_angle;  // rayon apparent de son disque, radians
global uniform float compagnon_temperature;  // température de surface, K
global uniform vec3 compagnon_couleur;       // couleur de sa lumière (luminance 1)
