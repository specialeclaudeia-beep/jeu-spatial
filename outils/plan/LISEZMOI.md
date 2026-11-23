# Plan du chasseur v27

Le jeu construit le vaisseau à partir de son **plan** : `vaisseaux/chasseur_v27.plan.json`. C'est un
fichier texte qui liste les pièces du vaisseau (structure, équipements, moteurs, propulseurs, roues,
points de la coque, plaques d'air) et ses pièces mobiles (charnières des ailes, tuyère, vérins). La
physique (`scripts/physique/vaisseau_physique.gd`) n'y ajoute que les lois. Le format est décrit dans
`scripts/atelier/plan.gd` et les types de pièces dans `scripts/atelier/catalogue.gd`.

## Refaire le plan après un changement du modèle Blender

1. Masses des pièces du modèle (Blender 5.3, ou le module `bpy` de Python) :

   ```
   blender -b --python outils/plan/extraire_masses_blender.py -- modele3d/v27_roues_arriere/vaisseau_v27.blend outils/plan/masses_pieces_v27.json
   ```

   Chaque pièce qui a une propriété `masse_kg` est comptée comme une coque mince (sa masse répartie
   sur sa surface) : on obtient sa masse, son centre et son inertie propre. Les objets vides `Masse_*`
   sont des équipements, comptés comme une masse en un point.

2. Écriture du plan (Python 3 seul suffit) :

   ```
   python outils/plan/composer_plan_v27.py
   ```

   Les moteurs, propulseurs, roues et plaques d'air sont écrits dans ce script, avec les mêmes valeurs
   que l'ancien code du jeu. La section « vie » (la cabine sous pression, étape 8 de l'atelier) aussi :
   son volume d'air et la courbure de ses parois viennent de `cabine_cockpit_v27.py` (à relancer si le
   cockpit change : `python outils/plan/cabine_cockpit_v27.py`, Python 3 + numpy, quelques minutes).

3. Lancer les tests : `res://scenes/tests_atelier.tscn` (atelier), puis les tests de physique (F1).

## Fichiers

- `extraire_masses_blender.py` : masses, centres et inertie de chaque pièce du modèle Blender.
- `masses_pieces_v27.json` : son résultat pour le modèle v27.
- `composer_plan_v27.py` : écrit le plan du chasseur.
- `cabine_cockpit_v27.py` : mesure la cabine sur le modèle du cockpit (volume d'air rempli par petits
  cubes de 2 cm depuis la place du pilote, rayon de courbure de chaque paroi).
- `ancien_code_v27.json` : ce que faisait le code d'avant l'atelier (vaisseau écrit dans le code). Les
  tests de l'atelier vérifient que le vaisseau construit par le plan fait la même chose : moteurs,
  propulseurs, ailes, vol vertical, train, plaques d'air.

## Ce qui a changé par rapport à l'ancien calcul de Blender

L'ancien calcul (`modele3d/v27_roues_arriere/masses_godot.json`) avait été mis à jour « par différence »
pour les versions v26 et v27 : les nouvelles pièces y étaient comptées comme des masses en un point. Le
plan compte la forme de chaque pièce. Résultat : même masse (8 534,6 kg au lieu de 8 534,1), centre de
gravité 6 mm plus en arrière (1,437 m au lieu de 1,431), inertie un peu plus grande (tangage +1,2 %,
lacet +2,7 %, roulis +9,6 %). Le vaisseau tourne donc un peu moins vite en roulis pour la même poussée.
Les quatre objets vides des réacteurs d'aile du fichier `.blend` sont mal rattachés à leur aile (ils
sont tous à l'origine) : le plan reprend leur vraie place, celle de l'ancien calcul.
