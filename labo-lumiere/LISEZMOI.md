# Labo-lumière

Un petit projet Godot à part, rangé dans le dossier du jeu. On y construit le système de lumière
en triangles sans risquer de casser le jeu. Le jeu ne voit pas ce dossier.

## L'ouvrir (une seule fois)
1. Ouvre Godot. Dans le gestionnaire de projets, clique sur **Importer**.
2. Choisis `Documents\jeu spacial\labo-lumiere\project.godot`, puis **Importer et modifier**.
3. Pour que Claude puisse piloter Godot : **Projet → Paramètres du projet → Extensions**,
   coche **Godot AI**. Ferme la fenêtre.
4. Appuie sur **F5** (ou Lecture ▶) : la scène du labo s'ouvre.

## Ce qu'on voit (étape 0)
Un fond noir, une boule grise éclairée par une lampe provisoire (juste un repère) et,
en haut à gauche, le **compteur** :
- **Images/s** : le nombre d'images par seconde (on vise 60) ;
- **Temps (ms)** : le temps pris par chacun des 4 temps de la boucle du système de lumière
  (choisir, éclairer, envoyer, dessiner). Un « ! » apparaît quand un temps dépasse son budget ;
- **Rayons** : le nombre de rayons de lumière calculés (0 pour l'instant).

## Touches
| Action | Touche |
|---|---|
| cacher / montrer le compteur | F3 |
| avancer / reculer | Z / S |
| aller à gauche / à droite | Q / D |
| monter / descendre | Espace / C |
| aller 5 fois plus vite | Maj (maintenue) |
| regarder autour | clic droit maintenu + souris |
| changer la vitesse | molette |

## Tests automatiques
Ouvre `scenes/tests.tscn` (double-clic dans le panneau Système de fichiers), puis **F6**.
Tout doit être vert.

## Avancement
- Étape 0 (17/11/2026) : labo créé, scène vide avec le compteur, 7 tests automatiques.
- Étape 1 (17/11/2026) : banc d'essai v2 dans `banc-essai/banc-lumiere-v2.html` (page web, voir `banc-essai/LISEZMOI.md`) : question 43 en deux versions côte à côte, ressemblance, couleurs stables, Soleil, éclipse, descente au millimètre. 11 tests automatiques.
