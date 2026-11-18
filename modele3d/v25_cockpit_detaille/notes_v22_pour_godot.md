# Vaisseau v22 : vraies matières et vraies masses

Même géométrie que la v21 (buses encastrées, sans missiles sous les ailes). `notes_v21_pour_godot.md` reste valable.
Nouveau : chaque pièce a une matière et une masse. Tout est dans `masses_godot.json` (repère Godot, mètres, kg).

## Matières
| Matière | Pièces | Masse |
|---|---|---|
| Composite fibre de carbone | 4 ailes, ailerons | 1 481 kg |
| Alliage aluminium-lithium | coque, trappes, marquages | 883 kg |
| Titane | 3 anneaux de la tuyère, moteur central, moteurs de levage, buses | 708 kg |
| Acier haute résistance | trains d'atterrissage | 420 kg |
| Verre aluminosilicate feuilleté | verrière | 343 kg |
| Aluminium | habillage du cockpit | 192 kg |

Méthode : masse d'une pièce = surface × épaisseur équivalente (peau + raidisseurs) × densité.
Épaisseurs : coque 6 mm, ailes 5 mm, titane 8 mm, acier 10 mm, verre 12 mm, habillage 2 mm.
Chaque objet a aussi `matiere` et `masse_kg` dans ses extras.

## Équipements intérieurs (objets `Masse_*`, sphères dans Blender)
Cœur du moteur principal 1 500 kg, 4 réacteurs d'aile 380 kg chacun (enfants de leur aile : ils suivent le repliage), moteurs de levage 240 kg, avionique (ordinateur de bord) 350 kg tout au bout du nez, canons 300 kg, air/eau/refroidissement 250 kg, pilote + siège 180 kg.
**Pas de carburant** : le jeu n'en a pas (voir l'en-tête de `vaisseau_physique.gd`), donc la masse ne change jamais en vol.

## Résultats (ailes ouvertes, train rentré)
- Masse totale : **8 367 kg** (structure 4 027 kg + équipements 4 340 kg). La physique utilise aujourd'hui 10 000 kg.
- **Centre de gravité : (0, 0.013, 1.444) en Godot**, donc **1,44 m derrière le centre** du modèle (les moteurs pèsent lourd à l'arrière).
- Moments d'inertie autour du centre de gravité : tangage (x) 67 998, lacet (y) 81 414, roulis (z) 19 209 kg·m². La matrice complète est dans le JSON.

## Pour la physique (`vaisseau_physique.gd`)
1. Prendre le centre de gravité réel : les couples des propulseurs doivent être calculés autour de ce point, pas autour de l'origine du modèle. C'est important pour le vol vertical : les moteurs de levage sont à l'avant et la tuyère orientable à l'arrière.
2. Remplacer l'inertie actuelle par ces valeurs.
3. Passer la masse à 8 367 kg.
4. Facultatif : recalculer le centre de gravité quand les ailes se replient : chaque aile a sa masse et son centre, et son réacteur la suit.
