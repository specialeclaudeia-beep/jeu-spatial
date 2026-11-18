# Labo-lumière

Un petit projet Godot à part, rangé dans le dossier du jeu. On y construit le système de lumière
en triangles sans risquer de casser le jeu. Le jeu ne voit pas ce dossier.

## L'ouvrir (une seule fois)
1. Ouvre Godot. Dans le gestionnaire de projets, clique sur **Importer**.
2. Choisis `Documents\jeu spacial\labo-lumiere\project.godot`, puis **Importer et modifier**.
3. Pour que Claude puisse piloter Godot : **Projet → Paramètres du projet → Extensions**,
   coche **Godot AI**. Ferme la fenêtre.
4. Appuie sur **F5** (ou Lecture ▶) : la scène du labo s'ouvre.

## Étape 8 : la lumière est dans le jeu
Le système du labo est maintenant aussi dans le jeu (ouvrir le projet du jeu, F5). En plus du labo :
le cockpit éclairé par le vrai Soleil avec les ombres des montants, la lampe du cockpit qui s'allume
seule la nuit, le projecteur (J), la visière du casque (U : relevée, claire, teintée) et la tête qui
bouge sous les G (I).

## Ce qu'on voit (étape 7)
**On peut descendre jusqu'au millimètre.** L'œil va maintenant jusqu'à 5 mm du sol (avant : 1,8 m), et
les triangles se coupent jusqu'à des rayons d'environ **1 mm**. Près du sol, on découvre :
- des **cailloux**, des blocs de 1,5 m jusqu'aux graviers de 1 cm, chacun avec sa propre teinte ;
- le **grain du sable**, jusqu'au millimètre ;
- les **ombres du relief proche** : chaque coin de triangle connaît la hauteur de son horizon vers
  l'est, le nord, l'ouest et le sud. Quand le Soleil (ou l'étoile compagne) passe sous cet horizon,
  le coin est à l'ombre. Les cailloux font donc de l'ombre, les montagnes aussi (la limite jour / nuit,
  vue d'orbite, devient déchiquetée comme sur la Lune), et les ombres suivent le Soleil qui avance.
  Les ombres sont toutes noires : sans air, rien ne les éclaire (la lumière renvoyée par le sol
  autour viendra avec les rebonds, question 38).

Avant, tout était calculé en « 32 bits » à 600 km du centre de la planète, soit 4 cm d'erreur : en
dessous, les petits triangles auraient tremblé. Tout est maintenant en « 64 bits ».

Nouvelles touches :
- **L** (loupe) : l'œil à 3 cm au-dessus du sol, le Soleil bas (12°) : on voit les grains et les
  ombres des graviers. Avance doucement avec Z (quelques mm par seconde) ;
- **G** (descente) : descente continue de l'orbite (1 500 km) jusqu'à 3 cm du sol, en 40 secondes.
  Rien ne doit sauter ni clignoter : les triangles s'affinent tout le long.

## Ce qu'on voyait à l'étape 6
**Le vrai ciel étoilé** : les 9 096 étoiles du catalogue de Yale (toutes celles qu'un œil humain peut
voir, jusqu'à la magnitude 6,5), à leur vraie place, avec leur vrai éclat et leur vraie couleur
(Bételgeuse orangée, Rigel bleutée…), et la **Voie lactée**, plus claire vers le centre de la galaxie.
Le ciel tourne avec le jour, comme sur Terre (le pôle nord du ciel est au-dessus du pôle de la planète).
Rien n'est caché « à la main » : le jour, ou face au Soleil, l'œil se ferme et les étoiles disparaissent
d'elles-mêmes ; la nuit, l'œil s'habitue au noir (quelques secondes, ou ~5 min avec T) et elles apparaissent.
Les étoiles brillantes ont un petit halo, comme dans un vrai œil (même loi que celui du Soleil).

**Une étoile compagne** : une naine orange à 5 fois la distance du Soleil (on la voit comme un point
orangé très brillant). Elle éclaire aussi la planète et la lune : là où le Soleil est couché mais elle
levée, le sol est éclairé en orangé, un peu comme un jour très couvert (610 lux). Sa lumière met
41 min 35 s pour arriver. Touche **E** pour l'éteindre ou la rallumer.

**À très grande vitesse** (touche **B** : 0,1 – 0,5 – 0,9 – 0,99 fois la vitesse de la lumière, droit
devant) : les étoiles se resserrent vers l'avant (aberration), deviennent bleues et plus brillantes devant,
rouges et sombres derrière (effet Doppler). Pour l'instant, seul le ciel (étoiles, Soleil, compagne,
Voie lactée) change ; la planète et la lune ne sont pas encore déformées à ces vitesses.

**Corrigé** : avant, sur le côté nuit, des pentes tournées vers le Soleil s'éclairaient même quand le
Soleil était loin sous l'horizon. Maintenant la planète cache le Soleil (et la compagne) sous l'horizon :
la nuit est vraiment noire, et au coucher du Soleil seuls les sommets restent éclairés.

Nouveaux points de vue :
9. le Soleil est couché, l'étoile compagne éclaire seule le sol ;
0. le ciel étoilé, côté nuit, vers le centre de la galaxie (attendre quelques secondes que l'œil s'habitue).

## Ce qu'on voyait à l'étape 5
Une **petite lune** de 150 km tourne autour de la planète, à 6 000 km de son centre, poussée par la
vraie gravité : un tour prend 60 heures (touche **V** pour accélérer le temps : ×10, ×100, ×1000).
Elle montre toujours la même face à la planète, comme notre Lune.
Elle fait de **vraies éclipses** : quand elle passe devant le Soleil, son ombre tombe sur le sol, toute
noire au milieu, avec une **pénombre** autour (le Soleil n'y est caché qu'en partie). Vue du sol, la lune
paraît 6 fois plus grosse que le Soleil : l'éclipse est totale, et la **couronne** du Soleil apparaît.
Quand la lune passe dans l'ombre de la planète, c'est une **éclipse de lune**.
La lumière met du temps à arriver : celle de la lune environ 20 millièmes de seconde, celle du Soleil
8 min 19 s. La lune est dessinée là où elle était quand sa lumière est partie (le compteur l'affiche).

Nouveaux points de vue :
6. éclipse totale de Soleil, vue du sol (le matin) ;
7. l'ombre de la lune sur la planète, vue d'orbite ;
8. éclipse de lune : la lune à moitié dans l'ombre de la planète, avec la bande de pénombre.

## Ce qu'on voyait à l'étape 4
Une vraie **planète de 600 km de rayon** dessinée avec ton système de lumière en triangles :
des montagnes, de grandes plaines sombres et des hauts plateaux clairs. Plus on s'approche,
plus les triangles se coupent en 4 (jusqu'à des rayons de quelques centimètres au ras du sol),
et chaque nouveau triangle **glisse** doucement de la forme de son parent vers la sienne :
rien ne doit clignoter. Le calcul (choisir les triangles, les éclairer) est fait en **C++**,
beaucoup plus vite que le GDScript. La planète **tourne** : un jour dure 2 heures (le Soleil avance
dans le ciel ; touche **R** pour arrêter).
La vitesse dépend de l'altitude : lent au ras du sol, très rapide en orbite (molette pour régler).

Les points de vue d'essai (touches **1** à **5**) :
1. vue d'orbite, la planète à moitié éclairée ;
2. au sol, on regarde le Soleil : éblouissement ;
3. côté nuit : noir complet, l'œil passe en vision de nuit ;
4. coucher de Soleil : la moitié du Soleil dépasse de l'horizon ;
5. rase-mottes à 200 m, en plein jour (avance avec Z).

## Ce qu'on voyait à l'étape 3
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
| points de vue d'essai | 1 à 9, et 0 |
| étoile compagne oui / non | E |
| essai à grande vitesse (0 ; 0,1 ; 0,5 ; 0,9 ; 0,99 c) | B |
| temps accéléré (×1, ×10, ×100, ×1000) | V |
| halo de l'œil oui / non | H |
| rotation de la planète oui / non | R |
| œil qui s'habitue au noir à la vraie vitesse (lente, ~5 min) ou accélérée | T |

## Mesure de vitesse (étape 2)
Ouvre `scenes/mesure.tscn` puis **F6**. Ne touche à rien pendant ~25 secondes : 6 essais
s'enchaînent, puis un tableau s'affiche et s'enregistre dans `mesures/resultats-pc.md`.
La planète a des couleurs au hasard : c'est normal, les rayons sont factices.

## Mesure de la planète (étape 4)
Lance le labo avec l'option `-- --mesure` (Claude le fait pour toi) : 12 essais s'enchaînent
(~55 s, dont les éclipses, le ciel étoilé et la grande vitesse), puis le tableau s'enregistre dans `mesures/resultats-planete-pc.md`.

## Tests automatiques
Ouvre `scenes/tests.tscn` (double-clic dans le panneau Système de fichiers), puis **F6**.
Tout doit être vert (37 tests depuis l'étape 6).

## Avancement
- Étape 0 (17/11/2026) : labo créé, scène vide avec le compteur, 7 tests automatiques.
- Étape 1 (17/11/2026) : banc d'essai v2 dans `banc-essai/banc-lumiere-v2.html` (page web, voir `banc-essai/LISEZMOI.md`) : question 43 en deux versions côte à côte, ressemblance, couleurs stables, Soleil, éclipse, descente au millimètre. 11 tests automatiques.
- Étape 2 (17/11/2026) : mesure de vitesse sur le PC (`scenes/mesure.tscn`). Dessin très rapide (2,3 ms), mais le calcul en GDScript prend 16 ms au lieu de 5 → 53 images/s. Décision de Gwenaël : le calcul (choisir + éclairer) passera en C++. 10 tests automatiques.
- Étape 4 (18/11/2026) : la planète en rayons, calculée en C++ (rien à installer : la partie C++ est déjà compilée dans `scripts/lumiere/bin`). 600 km, relief, couleurs stables, glissement, rotation (jour de 2 h), l'œil mesure la lumière avec les rayons. Mesure automatique : voir « Mesure de la planète » ci-dessous.
- Étape 5 (18/11/2026) : petite lune (vraie gravité), éclipses de Soleil et de lune avec pénombre, retard de la lumière, temps accéléré (V). 30 tests automatiques.
- Étape 3 (18/11/2026) : le vrai Soleil à 1 UA et l'œil du pilote (pupille, adaptation, halo selon la formule d'éblouissement de la CIE, vision de nuit, couronne du Soleil visible pendant une éclipse). 17 tests automatiques.
- Étape 6 (18/11/2026) : les étoiles (catalogue de Yale, Voie lactée), une étoile compagne qui éclaire aussi la planète, aberration et Doppler à grande vitesse (B), et la planète qui cache enfin le Soleil sous l'horizon. 37 tests automatiques.
- Étape 8 (18/11/2026) : la lumière branchée dans le jeu (cockpit, vaisseau, lampes, casque et visière, tête sous les G, le vaisseau se pose sur le relief). 42 tests du labo, 32 tests du jeu.
