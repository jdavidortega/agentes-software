# Trazabilidad

> El "hilo" mínimo que conecta **requisitos → incrementos → revisión**, con estado.
> Inteligente = mínimo: solo se rastrea lo que ayuda a decidir. Demasiada
> trazabilidad se vuelve carga y se abandona; si rastrear algo no aporta, no lo hagas.

## IDs y cómo se enlazan

- **Criterios de éxito:** `C1, C2…` (definidos en `docs/contexto.md`).
- **Incrementos:** `I1, I2…` (en `docs/plan.md`).
- **Decisiones:** `ADR-###` (en `docs/decisiones.md`).
- **Vacíos del revisor funcional (arranque):** `R-E.<n>` (p. ej. `R-E.1`); se registran
  al cerrar el arranque y se cierran (la persona llena el hueco) antes del gate de diseño.
- **Hallazgos del juez (ejecución):** `R-I<incremento>.<n>` (p. ej. `R-I3.1`).
- **Commits** enlazan en el footer: `Ref: I3` (incremento) o `Cierra: R-I3.1` (hallazgo).

## Cobertura de criterios

<!-- Forward: qué incremento satisface cada criterio y si está verificado.
Backward: de un criterio se llega a su incremento. Una fila por criterio. -->

| Criterio | Incremento(s) | Estado | Nota |
|----------|---------------|--------|------|
| C1 | I_ | pendiente / cubierto / verificado | |

## Registro de vacíos del revisor funcional (arranque)

<!-- Vacíos de completitud/consistencia del encuadre, a cierre del arranque. Ciclo:
abierto → resuelto (la persona llenó el hueco). Deben quedar todos resueltos antes
del gate de diseño; no se rastrean las sugerencias. -->

| Vacío | Punto incumplido | Estado | Resuelto (cómo / cuándo) |
|-------|------------------|--------|--------------------------|
| R-E._ | _…_ | abierto | — |

## Registro de revisiones del juez

<!-- Solo BLOQUEANTES, a cierre. Ciclo: abierto → resuelto (fecha + commit) →
verificado (juez). Las sugerencias no se rastrean aquí: van como aviso al gate. -->

| Hallazgo | Incr. | Criterio | Descripción | Estado | Resuelto (fecha · commit) |
|----------|-------|----------|-------------|--------|---------------------------|
| R-I_._ | I_ | C_ | _…_ | abierto | — |
