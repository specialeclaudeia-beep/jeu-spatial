# Labo-lumière

Un petit projet Godot à part, rangé dans le dossier du jeu. On y construit le système de lumière
en triangles sans risquer de casser le jeu. Le jeu ne voit pas ce dossier.

## L'ouvrir (une seule fois)
1. Ouvre Godot. Dans le gestionnaire de projets, clique sur **Importer**.
2. Choisis `Documents\jeu spacial\labo-lumiere\project.godot`, puis **Importer et modifier**.
3. Pour que Claude puisse piloter Godot : **Projet → Paramètres du projet → Extensions**,
   coche **Godot AI**. Ferme la fenêtre.
4. Appuie sur **F5** (ou Lecture ▶) : la scène du labo s'ouvre.

## Ce qu'on voit (étape 3)
Le vrai Soleil, à sa vraie distance (1 unité astronomique, 150 millions de km), avec sa vraie
taille (un demi-degré) et sa vraie lumière, et une boule grise d'essai de 1 km (comme la Lune),
en attendant la planète en rayons (étape 4). Tout passe par **l'œil du pilote** :
- la **pupille** se ferme au soleil (2 mm) et s'ouvre dans le noir (8 mm) ;
- l'œil **s'habitue** : en quelques secondes à la lumière (ébloui avant), lentement au noir ;
- le **halo** (éblouissement) autour du Soleil, avec ses fines raies, comme dans un vrai œil ;
- la **vision de nuit** : dans le noir, les couleurs partent, tout devient gris-bleu avec du grain.

Les points de vue d'essai (touches **1** à **4**) :
1. départ, la boule à moitié éclairée ;
2. on regarde le Soleil : éblouissement (tout devient blanc, puis l'œil s'habitue en quelques secondes) ;
3. dans l'ombre de la boule : nuit complète, l'œil s'habitue au noir en ~20 secondes ;
4. au bord de l'ombre : la moitié du Soleil dépasse (éclipse).

## Ce qu'on voyait à l'étape 0
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
| points de vue d'essai | 1, 2, 3, 4 |
| halo de l'œil oui / non | H |
| œil qui s'habitue au noir à la vraie vitesse (lente, ~5 min) ou accélérée | T |

## Mesure de vitesse (étape 2)
Ouvre `scenes/mesure.tscn` puis **F6**. Ne touche à rien pendant ~25 secondes : 6 essais
s'enchaînent, puis un tableau s'affiche et s'enregistre dans `mesures/resultats-pc.md`.
La planète a des couleurs au hasard : c'est normal, les rayons sont factices.

## Tests automatiques
Ouvre `scenes/tests.tscn` (double-clic dans le panneau Système de fichiers), puis **F6**.
Tout doit être vert (17 tests depuis l'étape 3).

## Avancement
- Étape 0 (17/11/2026) : labo créé, scène vide avec le compteur, 7 tests automatiques.
- Étape 1 (17/11/2026) : banc d'essai v2 dans `banc-essai/banc-lumiere-v2.html` (page web, voir `banc-essai/LISEZMOI.md`) : question 43 en deux versions côte à côte, ressemblance, couleurs stables, Soleil, éclipse, descente au millimètre. 11 tests automatiques.
- Étape 2 (17/11/2026) : mesure de vitesse sur le PC (`scenes/mesure.tscn`). Dessin très rapide (2,3 ms), mais le calcul en GDScript prend 16 ms au lieu de 5 → 53 images/s. Décision de Gwenaël : le calcul (choisir + éclairer) passera en C++. 10 tests automatiques.
- Étape 3 (18/11/2026) : le vrai Soleil à 1 UA et l'œil du pilote (pupille, adaptation, halo selon la formule d'éblouissement de la CIE, vision de nuit, couronne du Soleil visible pendant une éclipse). 17 tests automatiques.
