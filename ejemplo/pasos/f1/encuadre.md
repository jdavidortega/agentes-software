## Contexto
La persona registra sus gastos en un CSV con columnas `fecha,categoria,importe` y quiere un resumen por
categoría desde la terminal (`contexto/brief.md`). Muestras reales: `contexto/gastos.csv` y
`contexto/gastos-invalido.csv`. Hallazgo del muestreo: los importes usan punto decimal y dos decimales.

## Objetivos
- Ver el gasto por categoría y el total de un archivo en una sola orden.

## No-objetivos (explícito)
- Gráficos, varios archivos a la vez, monedas o formatos de fecha.

## Criterios de éxito
- C1: con un CSV válido imprime `categoria: importe` por categoría, con dos decimales, de mayor a menor importe (empate: por nombre), y al final `Total: <importe>`; código 0.
- C2: si una fila tiene un importe que no es un número, escribe `error: fila <n>: importe inválido «<valor>»` en la salida de error (n = línea del archivo, la cabecera es la 1), no imprime resumen y termina con código 1.
- C3: si el archivo no existe, escribe `error: no existe <ruta>` en la salida de error y termina con código 1.

## Set de oro (ejemplos de salida esperada)
- Entrada: `contexto/gastos.csv` → Salida esperada: `comida: 15.00` / `transporte: 3.25` / `ocio: 2.00` /
  `Total: 20.25`, código 0.
- Entrada: cabecera y dos filas `b,1.00` y `a,1.00` → Salida esperada: `a: 1.00` / `b: 1.00` /
  `Total: 2.00`.
- Entrada: solo la cabecera → Salida esperada: `Total: 0.00`.
- Entrada: `contexto/gastos-invalido.csv` → Salida esperada: `error: fila 3: importe inválido «abc»`,
  sin resumen, código 1.
- Entrada: ruta `no-existe.csv` → Salida esperada: `error: no existe no-existe.csv`, código 1.

## Entradas y salidas

| E/S | Nombre | Origen / consumidor | Formato | Muestra en `contexto/` o acceso | Validada |
|-----|--------|---------------------|---------|----------------------------------|----------|
| Entrada | archivo de gastos | la persona | CSV `fecha,categoria,importe`, punto decimal | `contexto/gastos.csv`, `contexto/gastos-invalido.csv` | sí |
| Salida | resumen | la persona, en la terminal | texto, una línea por categoría y el total | set de oro, par 1 | sí |

## Restricciones
- Sin dependencias fuera de la biblioteca estándar.

## Stack y arquitectura
- Python 3 con la biblioteca estándar; un script `resumen.py` con una función `resumir(lineas)` y su
  línea de órdenes. Pruebas con `unittest` (ADR-001).

## Modelo de despliegue
- **Destino:** solo local. **Empaquetado:** ninguno; se ejecuta con `python3 resumen.py <archivo>`.

## Stakeholders / usuarios
- Una sola persona, en su equipo.
