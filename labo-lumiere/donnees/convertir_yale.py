"""Convertit le catalogue d'étoiles de Yale (Bright Star Catalogue, 5e édition, domaine public)
en un petit fichier binaire lu par scripts/lumiere/etoiles.gd.

Source utilisée : la version JSON de brettonw (https://github.com/brettonw/YaleBrightStarCatalog,
fichier bsc5.json), elle-même tirée de http://tdc-www.harvard.edu/catalogs/bsc5.html.
Usage : python3 convertir_yale.py bsc5.json ../scripts/lumiere/etoiles_yale.bin

Format (petit-boutiste) : « YALE », nombre d'étoiles (uint32), puis pour chaque étoile 4 float32 :
ascension droite (rad, J2000), déclinaison (rad), magnitude V, indice de couleur B-V
(0,6 quand il manque : couleur du Soleil, à peu près).
"""
import json, math, re, struct, sys

def angle_ad(s):
    h, m, sec = re.match(r"(\d+)h (\d+)m ([\d.]+)s", s).groups()
    return (int(h) + int(m) / 60 + float(sec) / 3600) * 15 * math.pi / 180

def angle_dec(s):
    sg, d, m, sec = re.match(r"([+-])(\d+)° (\d+)′ ([\d.]+)″", s).groups()
    v = int(d) + int(m) / 60 + float(sec) / 3600
    return (-v if sg == "-" else v) * math.pi / 180

def main(entree, sortie):
    etoiles = []
    for e in json.load(open(entree, encoding="utf-8")):
        if "RA" not in e or "Vmag" not in e:
            continue
        bv = float(e["B-V"]) if e.get("B-V") not in (None, "") else 0.6
        etoiles.append((angle_ad(e["RA"]), angle_dec(e["Dec"]), float(e["Vmag"]), bv))
    etoiles.sort(key=lambda x: x[2])   # les plus brillantes d'abord
    with open(sortie, "wb") as f:
        f.write(b"YALE" + struct.pack("<I", len(etoiles)))
        for x in etoiles:
            f.write(struct.pack("<4f", *x))
    print(len(etoiles), "étoiles ; la plus brillante : V =", etoiles[0][2])

if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
