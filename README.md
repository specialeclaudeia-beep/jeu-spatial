# jeu-spatial
Un jeu a la première personne dans l'espace , avec un physique réaliste.

Moteur : Godot 4.7 (rendu Compatibilité). Dossier de référence du projet : `docs/dossier-jeu-spatial.md`.

## Ouvrir le projet
1. Lance Godot 4.7.
2. Dans le gestionnaire de projets : **Importer**, puis choisis le fichier `project.godot` de ce dossier.
3. Appuie sur **Lecture ▶** (en haut à droite) ou **F5**.

## Commandes
Toutes les commandes se changent dans le jeu : **F2** (ou **Options** sur la manette) ouvre l'écran
de configuration. On clique sur une case (ou on la choisit avec la croix directionnelle puis Croix),
puis on appuie sur la touche, le bouton ou le stick voulu. Les réglages sont sauvegardés tout de suite
(fichier `commandes.cfg` dans le dossier de sauvegarde de Godot) et rechargés à chaque partie.
Sticks et gâchettes sont analogiques : pousser à moitié demande la moitié.

Disposition par défaut :

| Action | Clavier | Manette (PS5) |
|---|---|---|
| plus / moins de poussée | Z / S | R2 / L2 |
| couper la poussée | Espace | Croix |
| tangage (nez en haut / en bas) | flèches haut / bas | stick gauche haut / bas |
| lacet (nez à gauche / à droite) | Q / D | L1 / R1 |
| roulis (pencher à gauche / à droite) | A / E | stick gauche gauche / droite |
| stabilisateur de rotation | T | Triangle |
| pause | P | Carré |
| cacher / montrer l'aide | H | Rond |
| recommencer / remettre en orbite | R / O | Créer |
| temps ×1, ×10, ×100, ×1000 | 1 2 3 4 | croix directionnelle gauche / droite (moins / plus vite) |
| tourner la tête (le vaisseau ne bouge pas) | — | stick droit (lâché : la tête revient devant) |
| regarder droit devant | C | R3 (enfoncer le stick droit) |
| tests de physique | F1 (Échap pour revenir) | Rond pour revenir |
| configurer les commandes | F2 | Options |

## Ce qui est simulé
- Vaisseau de 10 t, corps rigide à 6 degrés de liberté (masse, inertie, couples).
- 5 moteurs arrière de 200 kN (chacun seul pousse 2 fois le poids ; ensemble, 10 g d'accélération),
  chacun à sa vraie position. 12 petits propulseurs d'orientation de 6 kN (le roulis n'est possible
  qu'avec eux).
- Calcul automatique des poussées : on demande une poussée et une rotation, et le calcul choisit
  combien chaque propulseur pousse, d'après sa position (moteurs d'un côté plus forts que de l'autre,
  propulseurs d'orientation). Le vaisseau n'est jamais tourné directement.
- Gravité de Newton calculée en permanence (planète de test : 600 km de rayon, 9,81 m/s² au sol).
- Gravité de plusieurs astres possible (somme des attractions) et petit couple dû au gradient de gravité :
  laissé seul en orbite, le vaisseau se balance lentement autour de la direction de la planète.
- Pas de carburant. Pas encore d'atmosphère (phase 4 de la feuille de route).
- Marqueurs : (o) = direction où l'on va, (x) = direction d'où l'on vient.

## Organisation
- `scripts/physique/vaisseau_physique.gd` : toute la physique (indépendante de l'affichage).
- `scripts/jeu.gd` : affichage, cockpit provisoire, instruments.
- `scripts/commandes.gd` : touches du clavier et de la manette (disposition par défaut, sauvegarde).
- `scripts/ecran_touches.gd` : l'écran de configuration des commandes (F2).
- `scripts/tests_physique.gd` : les tests automatiques (F1).
- `shaders/` : surface de la planète et ciel étoilé.
- `banc-essai/banc-lumiere-fractale.html` : banc d'essai du système de lumière fractale (s'ouvre dans un navigateur, sur PC). Version en ligne : https://claude.ai/artifact/7RTivTLhf6TDjpeZyELo2m
