## Enfoque y arquitectura
Un único módulo, `resumen.py`: `resumir(lineas)` devuelve las líneas del resumen o lanza un error con
su mensaje; `main(argv)` lee el archivo, imprime y devuelve el código de salida (ADR-001).

## Modelo de datos (entradas/salidas)
- Entrada: CSV con cabecera `fecha,categoria,importe`; importe con punto decimal (`contexto/gastos.csv`).
- Salida: texto, `categoria: importe` por línea y `Total: <importe>` (set de oro del encuadre).

## Incrementos
- [ ] I1 «resumen» — resumen por categoría y total (satisface: C1)
- [ ] I2 «importe-invalido» — fila con importe inválido (satisface: C2)
- [ ] I3 «archivo-inexistente» — archivo que no existe (satisface: C3)

## Plan de pruebas

| Incremento | Criterio | Flujo por la entrada real (qué entrada, con qué datos) | Otras por garantía (garantía · nivel · sabotaje previsto → observado) | Set de oro automatizado | Manual explícita (procedimiento · límite) |
|------------|----------|----------------------------------------|------------------------------------------------------------------------|-------------------------|-------------------------------------------|
| I1 «resumen» | C1 | `main` sobre `contexto/gastos.csv` | orden con empate · unidad · invertir el desempate → rojo; código de salida del proceso · comando (`python3 resumen.py`), una vez para todos los criterios · quitar el bloque `__main__` → rojo | pares 1–3 | — |
| I2 «importe-invalido» | C2 | `main` sobre `contexto/gastos-invalido.csv` | sin resumen parcial · unidad · imprimir antes de validar → rojo; código 1 del proceso · la misma prueba del comando · `main(sys.argv)` sin `sys.exit` → rojo | par 4 | — |
| I3 «archivo-inexistente» | C3 | `main` con una ruta inexistente | — | par 5 | — |

## Bitácora
- [2026-11-05] Plan inicial: tres incrementos, uno por criterio.

## Fuera de alcance / backlog
- Varios archivos a la vez; formato JSON de salida.
