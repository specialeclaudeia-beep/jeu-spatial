# jeu-spatial
Un jeu a la première personne dans l'espace , avec un physique réaliste.

Moteur : Godot 4.7 (rendu Compatibilité). Dossier de référence du projet : `docs/dossier-jeu-spatial.md`.

Version réunie le 18/11/2026 : le vaisseau v25 (cockpit détaillé, droïde R-7, pilote automatique, fait
sur le PC) avec le système de lumière (étapes 0 à 9, fait dans le cloud). Le droïde a besoin de deux
choses qui ne sont pas dans le dépôt (trop lourdes) : l'extension `addons/nobodywho` et le dossier `ia/`
(modèles Qwen3-0.6B et LFM2.5-350M). Sans elles, le jeu marche, R-7 dit seulement qu'il est hors ligne.

## Ouvrir le projet
1. Lance Godot 4.7.
2. Dans le gestionnaire de projets : **Importer**, puis choisis le fichier `project.godot` de ce dossier.
3. Appuie sur **Lecture ▶** (en haut à droite) ou **F5**.

## Commandes
Toutes les commandes se changent dans le jeu : **F2** (ou **Options** sur la manette) ouvre l'écran
de configuration. On clique sur une case (ou on la choisit avec la croix directionnelle puis Croix),
puis on appuie sur la touche, le bouton ou le stick voulu. Les réglages sont sauvegardés tout de suite
(fichier `commandes.cfg` dans le dossier de sauvegarde de Godot) et rechargés à chaque partie.
Sticks et gâchettes sont analogiques : pousser à moitié demande la moitié.

Disposition par défaut :

| Action | Clavier | Manette (PS5) |
|---|---|---|
| plus / moins de poussée | Z / S | R2 / L2 |
| couper la poussée | Espace | Croix |
| tangage (nez en haut / en bas) | flèches haut / bas | stick gauche haut / bas |
| lacet (nez à gauche / à droite) | Q / D | L1 / R1 |
| roulis (pencher à gauche / à droite) | A / E | stick gauche gauche / droite |
| stabilisateur de rotation | T | Triangle |
| pilote auto : garder le cap | K | — |
| pilote auto : s'arrêter | N | — |
| pilote auto : atterrir | L | — |
| ouvrir / replier les ailes | X | croix directionnelle haut |
| sortir / rentrer le train d'atterrissage | G | croix directionnelle bas |
| vue cockpit / vue extérieure | V | pavé tactile |
| vol vertical (décollage / atterrissage) | F | bouton micro |
| zoom pour lire les instruments (maintenir) | B | L3 (enfoncer le stick gauche) |
| pause | P | Carré |
| cacher / montrer l'aide | H | Rond |
| recommencer / remettre en orbite | R / O | Créer |
| temps ×1, ×10, ×100, ×1000, ×10 000, ×100 000 | 1 2 3 4 5 6 | croix directionnelle gauche / droite (moins / plus vite) |
| puissance des moteurs : moins / plus (÷10 / ×10, de ×1 à ×100 000) | 7 / 8 | — (à choisir avec F2) |
| tourner la tête, ou la caméra en vue extérieure (le vaisseau ne bouge pas) | — | stick droit (lâché : la tête revient devant) |
| regarder droit devant | C | R3 (enfoncer le stick droit) |
| projecteur du vaisseau (allumer / éteindre) | J | — (à choisir avec F2) |
| visière du casque : relevée, claire, teintée | U | — (à choisir avec F2) |
| tête qui bouge avec les G (oui / non) | I | — (à choisir avec F2) |
| tests de physique | F1 (Échap pour revenir) | Rond pour revenir |
| configurer les commandes | F2 | Options |

## Ordinateur de bord (pilote automatique)
Il pilote avec les mêmes moteurs et propulseurs que le joueur : il calcule seulement les ordres
(gaz, tangage, lacet, roulis, et une petite force de côté). Toucher une commande de pilotage,
ou couper la poussée, le désactive.
- **Garder le cap (K)** : garde le nez dans la direction qu'il avait à l'activation, même lancé en rotation.
- **S'arrêter (N)** : annule la vitesse par rapport à la planète. Près d'une planète, il passe tout
  seul en vol vertical (la tuyère tourne vers le haut) et se penche, nez en haut, pour pousser contre
  sa vitesse : il ne se retourne jamais. La vitesse verticale et la vitesse horizontale s'annulent en
  même temps (le freinage le plus court). Si le vaisseau monte, il laisse la gravité freiner la montée.
  Il finit immobile, à plat, en vol stationnaire.
- **Atterrir (L)** : comme N, mais il descend ensuite : chute libre, puis freinage au dernier moment avec
  la poussée voulue pour arriver à 1 m/s, train sorti, et se pose à plat.
- **Urgence** : si le vol vertical ne peut plus éviter le sol (trop bas, descente trop rapide), il utilise
  un moment les gros moteurs, nez en haut, puis revient au vol vertical.
- **Temps accéléré** : le pilote calcule ses ordres au plus toutes les 0,04 s de temps de jeu, même à
  x1000. Il limite lui-même l'accélération du temps pendant une manœuvre (x100 au plus, x10 sous
  150 m, x1 sous 30 m) ; l'écran affiche « TEMPS x1000 (pilote auto : x100) ».

## Ce qui est simulé
- Vaisseau de 10 t, corps rigide à 6 degrés de liberté (masse, inertie, couples).
- 5 moteurs arrière de 200 kN (chacun seul pousse 2 fois le poids ; ensemble, 10 g d'accélération),
  chacun à sa vraie position. 12 petits propulseurs d'orientation de 6 kN (le roulis n'est possible
  qu'avec eux).
- Calcul automatique des poussées : on demande une poussée et une rotation, et le calcul choisit
  combien chaque propulseur pousse, d'après sa position (moteurs d'un côté plus forts que de l'autre,
  propulseurs d'orientation). Le vaisseau n'est jamais tourné directement.
- Relativité restreinte d'Einstein (étape A du programme « Einstein ») : on ne peut jamais atteindre la
  vitesse de la lumière. La physique suit la « vitesse propre » (γ·v) : le pilote sent toujours la même
  poussée, mais vue de la planète, la vitesse s'approche de c sans jamais l'atteindre. À petite vitesse,
  c'est exactement Newton. Deux horloges à l'écran : celle du pilote retarde quand il va vite (facteur γ)
  et, un tout petit peu, au fond d'un puits de gravité. Les vrais moteurs donnent 12 g (0,9 c en 43 jours
  du pilote) ; touches 7 / 8 : moteurs « imaginaires » jusqu'à ×100 000 (toujours de vraies forces, dont la
  part en plus passe par le centre de gravité). Le ciel (aberration, Doppler) suit la vraie vitesse.
  Pas encore : planète et lune déformées par l'aberration (étape A2), gravité d'Einstein (étape B).
- Gravité de Newton calculée en permanence (planète de test : 600 km de rayon, 9,81 m/s² au sol).
- Gravité de plusieurs astres possible (somme des attractions) et petit couple dû au gradient de gravité :
  laissé seul en orbite, le vaisseau se balance lentement autour de la direction de la planète.
- Vaisseau dessiné d'après le modèle 3D (`modeles/vaisseau/`, exporté de Blender) : les 17 propulseurs
  de la physique sont exactement aux endroits dessinés. Les ailes se replient en 2,5 s et les propulseurs
  posés dessus tournent avec elles (le calcul des poussées en tient compte). Le train sort en 3 s.
  Posé sur le ventre, le train ne peut pas sortir (le sol bloque les jambes).
- Sol : rien n'est bloqué « par magie ». Chaque roue est au bout d'une jambe à ressort-amortisseur
  (idée des points de contact d'Orbiter) : l'amortisseur s'écrase (15 cm à l'avant, 12 cm à l'arrière,
  comme sur le modèle v20) et pousse sur le vaisseau, à l'endroit de la roue. Posé, ils s'écrasent
  d'environ 5 cm, et le modèle 3D les montre écrasés (ressorts compris). Le train encaisse un posé
  jusqu'à 4 m/s ; au-delà l'amortisseur arrive en bout de course et casse. Train rentré, la coque
  (ventre, nez, queue) touche le sol : écrasé au-delà de 3 m/s. Le sol frotte et freine le glissement.
- Vue cockpit (caméra à l'œil du pilote) ou vue extérieure (caméra qui tourne autour du vaisseau) ;
  l'intérieur du cockpit n'est affiché qu'en vue cockpit.
- Lueurs des moteurs (modèle v19/v20) : chaque sortie s'allume selon la VRAIE poussée de son moteur
  (éteinte à 0, bleue à faible puissance, violette à pleine puissance), avec un jet de lumière dont la
  longueur suit la poussée.
- Vol vertical (F) : deux moteurs de levage de 37,5 kN sortent du ventre à l'avant (trappes puis vérin),
  puis la tuyère du moteur central tourne vers le bas (4 s en tout). Les gaz poussent alors vers le haut,
  au plus 132 kN sans faire basculer le vaisseau (il pèse 98 kN au sol) : de quoi décoller et se poser
  à la verticale. Tout vient de la poussée réelle des moteurs, à leur vraie place.
- Cockpit fonctionnel : levier des gaz (et ses 8 voyants), manche et pédales suivent les commandes ;
  interrupteurs (train, ailes, stabilisateur, couper les gaz) et boutons (temps, pause, vue, aide,
  commandes, remettre en orbite, poignée rouge pour recommencer) bougent quand on les actionne, et on
  peut aussi cliquer dessus à la souris. Les 5 écrans affichent en direct : radar des astres (position,
  distance), état du vaisseau, vitesses / altitude / G, temps, orbite. En vue cockpit, le texte en
  surimpression est caché : tout est sur les écrans.
- **Système de lumière** (étape 8, copié du labo `labo-lumiere/`) : vrai Soleil (environ 127 000 lux),
  planète dessinée en rayons avec son relief (le vaisseau se pose sur ce relief), étoiles réelles, étoile
  compagne, ombres du vaisseau dans le cockpit. L'œil du pilote s'habitue à la lumière comme un vrai œil
  (la nuit, la lampe du cockpit s'allume seule). Casque et visière (touche U), projecteur (J), tête qui
  bouge de quelques centimètres sous les G (I). Si la partie C++ manque, le jeu reprend l'ancien affichage.
  Étape 9 : reflets de la verrière et de la visière (loi de Fresnel), du cockpit, de la planète et du
  Soleil ; les métaux reflètent leur entourage et la lumière rebondit dans le cockpit.
  Vaisseau v25 : écrans, voyants, lueurs et jets des moteurs passent aussi par la lumière (vraie
  luminance en cd/m², vue par l'œil). En vue extérieure, pas de visière (la caméra n'est pas dans le casque).
- Pas de carburant. Pas encore d'atmosphère (phase 4 de la feuille de route).
- Marqueurs : (o) = direction où l'on va, (x) = direction d'où l'on vient.

## Organisation
- `scripts/physique/vaisseau_physique.gd` : toute la physique (indépendante de l'affichage).
- `scripts/jeu.gd` : affichage (modèle 3D, vues, animation des ailes et du train), instruments.
- `modeles/vaisseau/` : le vaisseau (`vaisseau_exterieur.glb`), le cockpit (`cockpit.glb`) et les positions
  des propulseurs. Pour une nouvelle version du modèle, il suffit de remplacer ces fichiers (mêmes noms).
- `scripts/commandes.gd` : touches du clavier et de la manette (disposition par défaut, sauvegarde).
- `scripts/ecran_touches.gd` : l'écran de configuration des commandes (F2).
- `scripts/lumiere/` : le système de lumière, copie exacte de `labo-lumiere/scripts/lumiere/` (un test le vérifie : on le change dans le labo, puis on recopie).
- `scripts/lumiere_jeu.gd` : branche le système dans le jeu (Soleil, planète, lampes, visière, posemètre de l'œil).
- `scripts/tests_physique.gd` : les tests automatiques (F1).
- `shaders/` : surface de la planète et ciel étoilé.
