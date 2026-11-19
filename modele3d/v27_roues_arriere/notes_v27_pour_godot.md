# Vaisseau v27 : roues arrière à la place des patins

Fait à partir de la v26 (fichier `vaisseau_v27.blend`, Blender 5.3). Seul le bas du train arrière change.
Cockpit et droïde identiques à la v26 (`cockpit_v27.glb` = `cockpit_v26.glb`).

## Pourquoi
Les patins arrière glissaient : au sol, au-delà d'environ 10 m/s, le vaisseau partait en tête-à-queue
sans le stabilisateur (T), et il freinait mal (seule la roue avant avait un frein).

## Ce qui change dans le modèle
- `Pied_arriere_*` garde son nom et son rôle (il reste parallèle à la coque, biellette) mais devient une
  **fusée** : rotule du bout de jambe, axe de roue, disque et étrier de frein. Extras : `type = "fusee_a_plat"`, 41,7 kg.
- `Roue_arriere_*` (nouveau, enfant du pied) : même roue que la roue avant (rayon 0,18 m), axe X,
  14 cm vers l'extérieur du bout de jambe et 6 cm au-dessus. Extras : `type = "roue"`, `axe = "X"`, `rayon_m = 0.18`, 30 kg.
- Bas des roues sorties : Godot (±1,184, -1,6, 2,4), soit **2,37 m** entre les roues (patins v26 : 2,09 m).
  Hauteur du vaisseau au sol inchangée.
- Train rentré : la roue tient dans le puits (elle dépasse de 3 cm dans le haut du puits, à l'intérieur de la coque : invisible).

## Masses
Par différence avec la v26 (masses ponctuelles, train rentré) : masse inchangée 8 534,1 kg, centre de
gravité Godot (0, 0,0147, 1,431), inertie tangage 67 901,5 / lacet 81 291,3 / roulis 19 295,1 kg·m².

## Dans la physique
Les roues arrière roulent dans l'axe du vaisseau, accrochent de côté (adhérence des pneus 0,8), et sont
freinées (Maj : les trois roues). Frein de parc automatique à l'arrêt, gaz à zéro. Braquage de la roue
avant réduit en vitesse (virage à 0,3 g au plus) pour ne pas basculer.

Fait dans le cloud avec Blender 5.3 (module bpy), script de modélisation reproductible.
