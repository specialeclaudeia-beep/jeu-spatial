# jeu-spatial
Un jeu a la première personne dans l'espace , avec un physique réaliste.

Moteur : Godot 4.7 (rendu Compatibilité). Dossier de référence du projet : `docs/dossier-jeu-spatial.md`.

## Ouvrir le projet
1. Lance Godot 4.7.
2. Dans le gestionnaire de projets : **Importer**, puis choisis le fichier `project.godot` de ce dossier.
3. Appuie sur **Lecture ▶** (en haut à droite) ou **F5**.

## Commandes
| Touche | Action |
|---|---|
| Z / S | plus / moins de poussée |
| Espace | couper la poussée |
| Flèches haut / bas | tangage (nez en haut / en bas) |
| Q / D | lacet (nez à gauche / à droite) |
| A / E | roulis |
| T | stabilisateur de rotation (agit seulement avec les propulseurs) |
| 1 2 3 4 | temps ×1, ×10, ×100, ×1000 |
| P | pause |
| O ou R | revenir en orbite à 100 km |
| F1 | tests de physique (Échap pour revenir) |
| H | cacher / montrer l'aide |

## Ce qui est simulé
- Vaisseau de 10 t, corps rigide à 6 degrés de liberté (masse, inertie, couples).
- 5 moteurs arrière de 40 kN, chacun à sa vraie position : pour tourner avec les moteurs,
  certains poussent plus que d'autres. 12 petits propulseurs d'orientation (1,5 kN) pour tourner
  moteurs coupés (le roulis n'est possible qu'avec eux).
- Gravité de Newton calculée en permanence (planète de test : 600 km de rayon, 9,81 m/s² au sol).
- Pas de carburant. Pas encore d'atmosphère (phase 4 de la feuille de route).
- Marqueurs : (o) = direction où l'on va, (x) = direction d'où l'on vient.

## Organisation
- `scripts/physique/vaisseau_physique.gd` : toute la physique (indépendante de l'affichage).
- `scripts/jeu.gd` : affichage, cockpit provisoire, instruments, commandes.
- `scripts/tests_physique.gd` : les tests automatiques (F1).
- `shaders/` : surface de la planète et ciel étoilé.
