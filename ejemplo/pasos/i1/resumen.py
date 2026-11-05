"""Resumen de gastos por categoría (C1)."""
import csv
import sys
from decimal import Decimal


def resumir(lineas):
    """Devuelve las líneas del resumen de un CSV `fecha,categoria,importe`."""
    totales = {}
    for fila in csv.DictReader(lineas):
        totales[fila["categoria"]] = totales.get(fila["categoria"], Decimal("0")) + Decimal(fila["importe"])
    orden = sorted(totales.items(), key=lambda par: (-par[1], par[0]))
    salida = [f"{categoria}: {importe:.2f}" for categoria, importe in orden]
    salida.append(f"Total: {sum(totales.values(), Decimal('0')):.2f}")
    return salida


def main(argv):
    with open(argv[1], encoding="utf-8", newline="") as archivo:
        print("\n".join(resumir(archivo)))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
