# Cockpit v16 : pièces mobiles et branchements à faire dans Godot

Repère : Blender (x, y, z) = Godot (x, z, -y). Tous les nœuds sont dans `cockpit_v16.glb`. Les propriétés listées sont dans les « extras » glTF de chaque nœud.

## Pièces qui suivent les commandes en continu
| Nœud (pivot) | Commande du jeu | Mouvement (axes Blender) |
|---|---|---|
| `Levier_gaz` | gaz (0 à 1) | rotation X de `angle_gaz_0_deg` = -30° à `angle_gaz_1_deg` = +30° |
| `Voyant_gaz_1` … `Voyant_gaz_8` | gaz | allumé si gaz ≥ `seuil` (1/8 … 8/8), sinon éteint (émission à 0) |
| `Manche` | tangage, roulis, lacet | rotation X ±15° (tangage), Y ±15° (roulis), Z ±10° (lacet) |
| `Pedale_gauche` / `Pedale_droite` | lacet | rotation X jusqu'à `angle_max_deg` (+12° / -12°) |

## Commandes qu'on actionne (souris ou touche)
| Nœud | `action` (nom de l'action Godot) | Type |
|---|---|---|
| `Interrupteur_train` | train | interrupteur : rotation X -25° (arrêt) / +25° (marche) |
| `Interrupteur_ailes` | ailes | interrupteur |
| `Interrupteur_stabilisateur` | stabilisateur | interrupteur |
| `Interrupteur_couper_gaz` | couper_gaz | interrupteur (revient en place) |
| `Voyant_train`, `Voyant_ailes`, `Voyant_stabilisateur`, `Voyant_couper_gaz` | état | allumé si train sorti / ailes ouvertes / stabilisateur activé / gaz à 0 |
| `Bouton_temps_x1`, `_x10`, `_x100`, `_x1000`, `Bouton_temps_moins`, `Bouton_temps_plus` | temps_… | bouton : s'enfonce de 4 mm (`course_m`), direction Blender (0, 0, -1) |
| `Bouton_pause`, `Bouton_vue`, `Bouton_aide`, `Bouton_ecran_touches`, `Bouton_remettre_orbite` | même nom | bouton |
| `Poignee_recommencer` (poignée rouge) | recommencer | poignée : se tire de 3 cm, direction Blender (0, -1, 0) |

Chaque pièce visible est l'enfant `…_piece` de son pivot : on fait bouger le pivot. Pour cliquer, on peut ajouter une zone de clic (Area3D) sur chaque `…_piece`.

## Écrans (à remplir en direct, par exemple avec un SubViewport par écran)
Chaque écran est un rectangle séparé, avec ses UV de 0 à 1 et son propre matériau (l'image actuelle n'est là qu'en attendant). Propriétés : `ecran`, `largeur_m`, `hauteur_m`.
| Nœud | Taille | Contenu demandé par Gwenaël |
|---|---|---|
| `Ecran_centre` | 0,256 × 0,166 m | carte/radar : planètes proches, leur position dans l'espace et leur distance |
| `Ecran_gauche` | 0,296 × 0,166 m | état du vaisseau : ailes, train, gaz, stabilisateur, propulseurs |
| `Ecran_droit` | 0,296 × 0,166 m | vol : vitesse totale, horizontale et verticale, altitude, accélération en G |
| `Ecran_lateral_gauche` / `_droit` | 0,096 × 0,29 m (portrait) | infos en plus : temps (x1 à x1000, pause), orbite (périgée, apogée), etc. |

Gwenaël veut que toutes les infos de vol soient dans le cockpit.
