# Vaisseau v23 : emplacement pour le droïde

Fait à partir de la v22. `notes_v21_pour_godot.md`, `notes_v22_pour_godot.md` et `masses_godot.json` restent valables (l'emplacement est vide, donc il ne change pas la masse).

## Ce qui change
- La coque (`Fuselage`) a maintenant un trou rond sur le dessus, juste derrière la verrière.
- L'objet `Emplacement_droide` est le logement : bague métallique, paroi sombre, anneau orange, fond avec 4 crochets et une prise de connexion à 3 voyants. Diamètre 0,66 m, profondeur 0,50 m.
- Le nœud `Point_droide` est au fond du logement, en Godot **(0, 0.53, 1.85)** (extras `type = emplacement_droide`, `diametre_m`, `profondeur_m`). Un droïde ajouté plus tard se place avec son pied sur ce point et dépasse de la coque.
