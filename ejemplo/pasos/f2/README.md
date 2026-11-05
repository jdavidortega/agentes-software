# Resumen de gastos

Resume por categoría un CSV de gastos y da el total, desde la terminal. Proyecto de ejemplo del método:
su ciclo completo está en la historia de git (`git log --reverse`).

```mermaid
flowchart LR
  A[CSV de gastos] --> B[resumen.py] --> C[Gasto por categoría y total]
```

## Cómo se ejecuta

```sh
python3 resumen.py contexto/gastos.csv
```

## Entradas y salidas

Entrada: CSV `fecha,categoria,importe` con punto decimal. Salida, para `contexto/gastos.csv`:

```
comida: 15.00
transporte: 3.25
ocio: 2.00
Total: 20.25
```

Con un importe que no es un número, o un archivo que no existe, escribe `error: …` y termina con código 1.

## Estructura

- `resumen.py`: el programa. `tests/`: sus pruebas (`sh scripts/check.sh`).
- `docs/`: encuadre, plan, trazabilidad y decisiones del método. `contexto/`: las entradas.
