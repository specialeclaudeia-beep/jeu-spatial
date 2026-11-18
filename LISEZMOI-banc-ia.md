# Banc d'essai du droïde (petite IA)

Ce banc d'essai est **à part du jeu** : il ne touche pas au vaisseau. Il vérifie si une petite IA,
sur ce PC, comprend des ordres en français et choisit la bonne fonction du vaisseau, en combien de
temps, et si l'image reste fluide pendant qu'elle réfléchit.

## 1. Installer l'extension NobodyWho (une seule fois)

Godot fermé, copie ces lignes dans PowerShell :

```powershell
cd "$HOME\Documents\jeu spacial"
Invoke-WebRequest "https://github.com/nobodywho-ooo/nobodywho/releases/download/nobodywho-godot-v13.0.0/nobodywho-godot-nobodywho-godot-v13.0.0.zip" -OutFile "$env:TEMP\nobodywho.zip"
Expand-Archive "$env:TEMP\nobodywho.zip" "$env:TEMP\nobodywho" -Force
$dossier = (Get-ChildItem "$env:TEMP\nobodywho" -Recurse -Filter nobodywho.gdextension | Select-Object -First 1).Directory.FullName
Copy-Item $dossier "addons\" -Recurse -Force
Get-ChildItem "addons\nobodywho"
```

La dernière ligne doit lister `nobodywho.gdextension` et un fichier `...windows-msvc-release.dll`.

## 2. Lancer le banc d'essai

1. Ouvre le projet dans Godot (redémarre-le s'il était ouvert).
2. Dans le panneau des fichiers, ouvre `scenes/banc_ia.tscn`, puis appuie sur **F6** (lancer cette scène).
3. Appuie sur **1** pour essayer LFM2.5-350M, ou sur **2** pour Qwen3-0.6B.
   Au premier essai, le modèle se télécharge (environ 230 Mo et 400 Mo) : il faut patienter.
4. Le banc envoie 10 ordres, et affiche pour chacun la fonction choisie, le temps de réponse et la
   fluidité (images par seconde). Le cube qui tourne montre si ça saccade.
5. Tu peux aussi taper tes propres ordres en bas, puis Entrée.

Le bilan est enregistré dans `banc_ia_resultats.txt` (le chemin s'affiche à l'écran) :
envoie-le à Claude, ou une capture d'écran.
