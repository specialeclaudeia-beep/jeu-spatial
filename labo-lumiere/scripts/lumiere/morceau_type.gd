extends RefCounted
## Le « morceau type » : un triangle coupé 3 fois en 4 = 64 petits triangles (programme, partie 5).
## Il est dessiné ~520 fois avec un MultiMesh : chaque copie est posée sur un triangle de la planète
## par sa transformation (coin A = origine, côtés B−A et C−A = axes X et Y).
## Chaque petit triangle porte son numéro (0 à 63) dans UV.x : le shader s'en sert pour lire
## la couleur de SON rayon dans la texture des rayons.
## Les sommets ne sont pas partagés (192 sommets), pour que chaque petit triangle ait un numéro à lui.

const COUPES := 8                       # 8 petits triangles par côté = 3 coupes en 4
const NB_TRIANGLES := COUPES * COUPES   # 64


## Fabrique le maillage du morceau type, en coordonnées (u, v) du triangle de base.
static func creer() -> ArrayMesh:
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
	var tableaux := []
	tableaux.resize(Mesh.ARRAY_MAX)
	tableaux[Mesh.ARRAY_VERTEX] = sommets
	tableaux[Mesh.ARRAY_TEX_UV] = uvs
	var maillage := ArrayMesh.new()
	maillage.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, tableaux)
	return maillage


static func _ajouter(s: PackedVector3Array, uvs: PackedVector2Array, a: Vector3, b: Vector3, c: Vector3, n: int) -> void:
	# Ordre des coins tourné pour que la face regarde vers +Z (vers l'extérieur de la planète).
	for p in [a, b, c]:
		s.append(p)
		uvs.append(Vector2(n + 0.5, 0.0))
