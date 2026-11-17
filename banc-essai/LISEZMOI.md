# Banc d'essai de la lumière en triangles

Des pages web qui s'ouvrent d'un double-clic (Chrome, Edge ou Firefox, avec Internet). Elles servent de
laboratoire pour le « système de décomposition fractale de la lumière » avant de le construire dans Godot.

| Fichier | Contenu |
|---|---|
| `banc-lumiere-fractale.html` | Version 1 (15/11/2026), gardée telle quelle |
| `banc-lumiere-v2.html` | Version 2 (étape 1 du programme, 17/11/2026) |

## Version 2 : ce qu'il y a de nouveau
- **Question 43, deux versions côte à côte** : à gauche (A), la lumière du Soleil est calculée dans chaque
  rayon ; à droite (B), le rayon garde la couleur et la pente du sol, et la carte graphique ajoute le Soleil
  à chaque pixel. Le menu « Question 43 » permet aussi de voir A seul ou B seul.
- **Fusion par taille ET par ressemblance** : une zone unie (mer, glace) reste en grands triangles
  (jusqu'à 3 rayons de large), les côtes et les reliefs gardent leurs petits triangles. Réglage « seuil ».
- **Couleurs stables** : couleurs posées sur les coins partagés et mélangées selon la surface ; un parent vaut
  exactement la moyenne de ses enfants ; marge « couper à 8 px, fusionner à 6 px » ; un nouveau coin part de la
  couleur déjà affichée puis glisse en 0,1 s ; tramage contre les bandes ; bords sans fentes là où un petit
  triangle touche un grand.
- **Soleil visible** avec sa vraie taille (0,53°) et un halo léger ; les étoiles disparaissent quand il est
  dans le champ.
- **Relief éclairé** : le sol a de vraies pentes (le bruit donne sa pente exacte) et un grain à toutes les
  échelles.
- **Éclipse avec pénombre** par une lune d'essai (90 km de rayon, à 12 000 km).
- **Petite échelle (question 37)** : on descend jusqu'à 10 cm du sol, les triangles font alors 1 mm.
  Positions calculées en 64 bits par rapport à la caméra : rien ne tremble.

## Boutons
| Bouton | Ce qu'il fait |
|---|---|
| Près du sol | 1,8 km au-dessus d'une côte, côté jour |
| Au millimètre | 10 cm au-dessus du sol (triangles de 1 mm) |
| Voir l'éclipse | place la lune devant le Soleil et la caméra au-dessus de l'ombre |
| Voir le Soleil | côté nuit, le Soleil juste à côté du bord de la planète |
| Lancer les tests | 11 tests automatiques (tout doit être vert) |

Souris : glisser = tourner autour, molette = monter ou descendre. Curseur « Regard » : de la verticale
jusqu'à l'horizon.
