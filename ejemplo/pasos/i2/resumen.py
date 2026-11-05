"""Resumen de gastos por categoría (C1, C2)."""
import csv
import sys
from decimal import Decimal, InvalidOperation


class ErrorDeEntrada(Exception):
    """Entrada que no se puede resumir; su mensaje es el que ve la persona."""


def resumir(lineas):
    """Devuelve las líneas del resumen de un CSV `fecha,categoria,importe`."""
    totales = {}
    lector = csv.DictReader(lineas)
    for fila in lector:
        try:
            importe = Decimal(fila["importe"])
        except InvalidOperation:
            raise ErrorDeEntrada(f"fila {lector.line_num}: importe inválido «{fila['importe']}»") from None
        totales[fila["categoria"]] = totales.get(fila["categoria"], Decimal("0")) + importe
    orden = sorted(totales.items(), key=lambda par: (-par[1], par[0]))
    salida = [f"{categoria}: {importe:.2f}" for categoria, importe in orden]
    salida.append(f"Total: {sum(totales.values(), Decimal('0')):.2f}")
    return salida


def main(argv):
    try:
        with open(argv[1], encoding="utf-8", newline="") as archivo:
            lineas = resumir(archivo)
    except ErrorDeEntrada as error:
        print(f"error: {error}", file=sys.stderr)
        return 1
    print("\n".join(lineas))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
