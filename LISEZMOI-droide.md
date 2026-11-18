# Droïde R-7 (IA Qwen3-0.6B dans le jeu)

- Code : `scripts/droide.gd`. Branchement : une dizaine de lignes dans `scripts/jeu.gd`.
- Sauvegarde d'avant : `projet-claude/sauvegarde-avant-droide-ia/` (jeu.gd, project.godot).
- En jeu : **Entrée** ouvre la boîte de dialogue, Entrée envoie, Échap annule. Pendant qu'on écrit,
  le clavier et la manette ne pilotent pas. La réponse s'affiche en bas, la tête du droïde bouge pendant qu'il réfléchit.
- Ce qu'il sait faire : stabilisateur, garder le cap, s'arrêter, atterrir, couper le pilote auto,
  train, ailes, vol vertical, et répondre aux questions (vitesse, altitude, g, orbite, train, ailes,
  vol vertical, pilote auto, ou tout l'état).
- Garde-fous : le verbe de l'ordre (sors / rentre, ouvre / replie…) corrige le sens si l'IA se trompe ;
  un appel écrit en texte par l'IA est rattrapé ; « atterris / pose-nous » est reconnu directement.
- Tests : `Godot_console.exe --headless --path . res://scenes/tests_droide.tscn` (≈ 1 min, avec le vrai modèle)
  ou ajouter `-- --sans-ia` (quelques secondes). Résultat du 17/11 : 15 ordres sur 15, 2,4 s en moyenne, 40/40 tests.
