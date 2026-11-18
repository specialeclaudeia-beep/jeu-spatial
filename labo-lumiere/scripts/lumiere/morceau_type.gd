extends RefCounted
## Le « morceau type » : un triangle coupé 3 fois en 4 = 64 petits triangles (programme, partie 5).
## Il est dessiné ~520 fois avec un MultiMesh : chaque copie est posée sur un triangle de la planète
## par sa transformation (coin A = origine, côtés B−A et C−A = axes X et Y).
## Chaque petit triangle porte son numéro (0 à 63) dans UV.x : le shader s'en sert pour lire
## la couleur de SON rayon dans la texture des rayons.
## Les sommets ne sont pas partagés (192 sommets), pour que chaque petit triangle ait un numéro à lui.
## Depuis l'étape 4, UV.y porte le numéro du COIN (0 à 44, grille du morceau) : le shader de la
## planète lit sa position dans la texture des coins. Avec les « jupes » (creer(true)), on ajoute
## le long des 3 bords de petits murs qui descendent sous le sol : ils cachent les fentes qui
## pourraient s'ouvrir entre deux morceaux de tailles différentes. Leurs coins du bas ont UV.y + 64.

const COUPES := 8                       # 8 petits triangles par côté = 3 coupes en 4
const NB_TRIANGLES := COUPES * COUPES   # 64


## Fabrique le maillage du morceau type, en coordonnées (u, v) du triangle de base.
static func creer(avec_jupes := false) -> ArrayMesh:
	var sommets := PackedVector3Array()
	var uvs := PackedVector2Array()
	var pas := 1.0 / COUPES
	var numero := 0
	for i in COUPES:              # rangée, en partant du côté A-B
		for j in COUPES - i:      # triangles « pointe en haut » de la rangée
			var a := Vector3(j * pas, i * pas, 0)
			_ajouter(sommets, uvs, a, a + Vector3(pas, 0, 0), a + Vector3(0, pas, 0), numero)
			numero += 1
			if j < COUPES - i - 1:  # triangle « pointe en bas » juste à côté
				var b := a + Vector3(pas, 0, 0)
				_ajouter(sommets, uvs, b, b + Vector3(0, pas, 0), a + Vector3(0, pas, 0), numero)
				numero += 1
	if avec_jupes:
		for a in COUPES:   # bord A-B (en bas)
			_jupe(sommets, uvs, Vector2i(a, 0), Vector2i(a + 1, 0), _numero_haut(0, a))
		for b in COUPES:   # bord A-C (à gauche)
			_jupe(sommets, uvs, Vector2i(0, b + 1), Vector2i(0, b), _numero_haut(b, 0))
		for b in COUPES:   # bord B-C (en biais)
			_jupe(sommets, uvs, Vector2i(COUPES - b, b), Vector2i(COUPES - b - 1, b + 1), _numero_haut(b, COUPES - 1 - b))
	var tableaux := []
	tableaux.resize(Mesh.ARRAY_MAX)
	tableaux[Mesh.ARRAY_VERTEX] = sommets
	tableaux[Mesh.ARRAY_TEX_UV] = uvs
	var maillage := ArrayMesh.new()
	maillage.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, tableaux)
	return maillage


## Numéro d'un coin de la grille (a le long de A→B, b le long de A→C), comme dans la partie C++.
static func numero_coin(a: int, b: int) -> int:
	return b * (COUPES + 1) - b * (b - 1) / 2 + a


## Numéro du petit triangle « pointe en haut » de la rangée b, colonne j.
static func _numero_haut(b: int, j: int) -> int:
	var base := 0
	for r in b:
		base += 2 * (COUPES - r) - 1
	return base + 2 * j


static func _ajouter(s: PackedVector3Array, uvs: PackedVector2Array, a: Vector3, b: Vector3, c: Vector3, n: int) -> void:
	# Ordre des coins tourné pour que la face regarde vers +Z (vers l'extérieur de la planète).
	for p in [a, b, c]:
		s.append(p)
		uvs.append(Vector2(n + 0.5, numero_coin(roundi(p.x * COUPES), roundi(p.y * COUPES)) + 0.5))


## Un petit mur sous le bord p → q, qui prend la couleur du rayon n.
static func _jupe(s: PackedVector3Array, uvs: PackedVector2Array, p: Vector2i, q: Vector2i, n: int) -> void:
	var kp := numero_coin(p.x, p.y)
	var kq := numero_coin(q.x, q.y)
	var vp := Vector3(p.x, p.y, 0) / COUPES
	var vq := Vector3(q.x, q.y, 0) / COUPES
	for c in [[vp, kp], [vq, kq], [vq, kq + 64], [vp, kp], [vq, kq + 64], [vp, kp + 64]]:
		s.append(c[0])
		uvs.append(Vector2(n + 0.5, c[1] + 0.5))
