# Vaisseau v26 : train arrière élargi

Fait à partir de la v25. Seul le train arrière change (et le ventre autour). Cockpit et droïde identiques à la v25.

## Pourquoi
Avec le train v25 (patins à 84 cm l'un de l'autre, ressorts souples, centre de gravité à 1,55 m du sol), le vaisseau se couchait dès 3,5° de pente de côté.

## Ce qui change dans le modèle
- **Jambes obliques** : `Train_arriere_*` est maintenant le pivot de la jambe, dans le ventre à Godot (±0,44, -0,76, 2,4).
  Extras : `type = "pivot_oblique"`, `axe_godot` (axe en biais, ≈ (0,766, ±0,643, 0)), `angle_rentre_deg = 90`, `angle_sorti_deg = 0`.
  Sortie (0°), la jambe part vers l'extérieur à 40° de la verticale et passe sous le réacteur d'aile (0,5 m d'écart avec l'aile ouverte).
  Rentrée (90°), elle se couche vers l'avant dans un puits du ventre.
- `Jambe_axe_arriere_*` (nouveau, enfant du pivot) porte la jambe allongée (1,01 m), le ressort et l'amortisseur, alignés sur la jambe.
  `Amortisseur_arriere_*` coulisse toujours selon son axe local (le long de la jambe).
- `Pied_arriere_*` (extra `type = "patin_a_plat"`) reste parallèle à la coque (biellette) : sa rotation = inverse de celle de la jambe.
- Patins sortis : bas à Godot (±1,044, -1,6, 2,4), soit **2,09 m** d'écart (avant : 0,84 m).
- Ventre : deux ouvertures, `Puits_train_arriere_*` (fond sombre), trappes `Trappe_arriere_*` sur `Charniere_Trappe_arriere_*`
  (charnière côté intérieur, `angle_ouvert_deg` ±90, comme les autres trappes). Les anciens carters fixes `Cylindre_arriere_*` sont supprimés,
  remplacés par les paliers `Pivot_train_arriere_*`.
- Tout ce qui est nouveau porte `cacher_en_vue_cockpit`.

## Masses (`masses_godot.json`)
Calcul par différence avec la v25 (pièces du train comptées comme des masses ponctuelles), ailes ouvertes, train rentré :
masse 8 534,1 kg (+75,6 kg : jambes plus longues, puits, trappes, paliers), centre de gravité Godot (0, 0,013, 1,431),
inertie tangage 67 922 / lacet 81 280 / roulis 19 305 kg·m².

## Résultat dans la physique
- Posé, le sol qui penche doucement de côté : il tient jusqu'à ~24° (au-delà de 26,6°, il glisse : frottement 0,5).
- Se poser à plat à 1 m/s sur une pente de côté : il tient jusqu'à ~10°. Au-delà, le patin le plus haut touche le premier et le fait trop rouler (comme un vrai avion).
