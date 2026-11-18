# Vaisseau v24 + droïde v01

Fait à partir de la v23. Les notes v21, v22 et v23 restent valables (copiées dans ce dossier).

## Correction importante
De la v20 à la v23, plusieurs pièces avaient perdu leurs matériaux : tout était exporté avec le premier matériau de la liste, donc en gris uni.
Les pièces touchées sont les trains (jambes, pieds, fourche, roue, carters), les buses RCS, `Cockpit_habillage` et `Emplacement_droide`.
C'est corrigé ici : **utiliser les glb v24, pas ceux de la v20 à la v23.**

## Le droïde : `droide_v01.glb` (fichier à part)
- Environ 1 m de haut, base de 60 cm de diamètre, environ 3 900 triangles, 45 kg.
- Origine = dessous de la base. Il regarde vers l'avant du vaisseau (-Z en Godot).
- Pour le mettre dans le vaisseau : instancier `droide_v01.glb` comme enfant du nœud `Point_droide` (position 0, rotation 0). Il est fait pour entrer dans le logement : rayon 0,30 m sous la coque, trou de 0,33 m. Le corps est entièrement caché, seule la tête dépasse. Le logement fait 0,74 m de profondeur depuis la v24 (0,50 m en v23) : `Point_droide` est maintenant en Godot (0, 0.29, 1.85).
- Pièces mobiles (extras `type = pivot`) :
  - `Droide_tete` tourne sur Z (Godot Y) : la tête peut regarder autour.
  - `Droide_bras_gauche_epaule` / `_droit_epaule` (axe X) : 0° = rangé le long du corps, `angle_travail_deg` = -70° = levé vers l'avant.
  - `Droide_bras_*_coude` (axe X) : `angle_travail_deg` = -40°.
  - Bras gauche : pince. Bras droit : outil de réparation.
- Lumières : l'œil (matériau `Oeil_droide`) et les petits voyants bleus (`Led_droide`) sont émissifs.
- Attention : bras levés, le droïde ne rentre plus dans le trou. Ne lever les bras que quand il est sorti.

## Masses (`masses_godot.json` recalculé)
Le droïde (45 kg) et son logement sont comptés.
Masse totale : 8 451 kg. Centre de gravité Godot : (0, 0.021, 1.448). Inertie : tangage 68 072, lacet 81 432, roulis 19 269 kg·m².
