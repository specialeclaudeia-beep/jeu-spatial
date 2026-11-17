# Mesure de vitesse du système de lumière (étape 2)

Date : 2026-11-17T23:32:17 · Godot 4.7.2-stable (official) · Intel(R) UHD Graphics · Intel(R) Core(TM) i3-1005G1 CPU @ 1.20GHz, 4 fils · rendu gl_compatibility · fenêtre (1280.0, 720.0)

| Essai | Rayons | Images/s | Image (ms) | Pire 5 % (ms) | Choisir | Éclairer | Envoyer | Dessiner | Carte graph. |
|---|---|---|---|---|---|---|---|---|---|
| Écran vide (repère) | 0 | 421 | 2.37 | 3.46 | 0.00 | 0.00 | 0.00 | 2.37 | 0.24 |
| Dessin seul | 33024 | 251 | 3.99 | 5.38 | 0.00 | 0.00 | 0.00 | 3.99 | 1.57 |
| Tout, 1 seul fil de calcul | 33024 | 30 | 33.74 | 38.12 | 17.33 | 14.12 | 0.50 | 2.11 | 1.67 |
| Tout, plusieurs fils de calcul | 33024 | 53 | 18.93 | 21.53 | 9.06 | 7.11 | 0.56 | 2.28 | 2.38 |
| Changement brusque (tout réécl.) | 33024 | 16 | 62.89 | 66.81 | 8.93 | 51.14 | 0.51 | 2.94 | 2.32 |
| Deux fois plus de rayons (66 000) | 66048 | 32 | 31.07 | 33.45 | 14.87 | 13.70 | 0.78 | 1.92 | 3.22 |

Budget visé : choisir 2 ms, éclairer 3 ms, envoyer 1 ms, dessiner 8 ms, image 16,7 ms (60 images/s).
« Dessiner » = image complète moins les 3 temps de calcul. « Carte graph. » = temps donné par Godot (0 s'il ne sait pas le mesurer).

**Verdict : C++ CONSEILLÉ : calcul 16.7 ms sur 6. Les deux temps les plus lents : « choisir » et « éclairer ». Changement brusque (tout refait d'un coup) : 51.1 ms pour éclairer.**

PC branché sur secteur. Tests du labo sur le PC : 10 / 10. Aucune erreur.
