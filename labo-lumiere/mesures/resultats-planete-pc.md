# Mesure de la planète en rayons (étape 4)

Date : 2026-11-18T03:22:54 · Intel(R) Core(TM) i3-1005G1 CPU @ 1.20GHz · Intel(R) UHD Graphics

Sans synchronisation avec l'écran (vsync coupée). Dessiner = processeur + carte graphique (Godot) ;
Processus = tout le GDScript de l'image (choisir/éclairer compris).

| Essai | Images/s | Image (ms) | Choisir | Éclairer | Envoyer | Dessiner | Rayons | Processus | Dessin processeur | Dessin carte graphique |
|---|---|---|---|---|---|---|---|---|---|---|
| Vue d'orbite (1) | 219 | 4.6 | 0.18 | 0.00 | 0.08 | 4.70 | 19968 | 11.63 | 0.44 | 4.26 |
| Rase-mottes en avançant (5) | 137 | 7.3 | 0.78 | 0.20 | 0.37 | 7.51 | 44301 | 8.88 | 0.60 | 6.91 |
| Face au Soleil (2) | 262 | 3.8 | 0.04 | 0.00 | 0.07 | 3.95 | 0 | 5.39 | 0.44 | 3.51 |
| Côté nuit (3) | 218 | 4.6 | 0.45 | 0.00 | 0.11 | 5.12 | 30336 | 7.38 | 0.79 | 4.33 |
| Coucher de Soleil (4) | 148 | 6.8 | 0.57 | 0.01 | 0.13 | 7.08 | 45440 | 8.67 | 0.65 | 6.43 |
| Orbite, planète cachée (ciel seul) | 365 | 2.7 | 0.27 | 0.00 | 0.10 | 2.15 | 28800 | 5.22 | 0.41 | 1.73 |
