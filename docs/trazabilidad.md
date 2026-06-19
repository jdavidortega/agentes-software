# Trazabilidad

> El "hilo" mínimo que conecta **requisitos → incrementos → revisión**, con estado.
> Inteligente = mínimo: solo se rastrea lo que ayuda a decidir. Demasiada
> trazabilidad se vuelve carga y se abandona; si rastrear algo no aporta, no lo hagas.

## IDs y cómo se enlazan

- **Criterios de éxito:** `C1, C2…` (definidos en `docs/contexto.md`).
- **Incrementos:** `I1, I2…` (en `docs/plan.md`).
- **Decisiones:** `ADR-###` (en `docs/decisiones.md`).
- **Hallazgos del juez:** `R-I<incremento>.<n>` (p. ej. `R-I3.1`).
- **Commits** enlazan en el footer: `Ref: I3` (incremento) o `Cierra: R-I3.1` (hallazgo).

## Cobertura de criterios

<!-- Forward: qué incremento satisface cada criterio y si está verificado.
Backward: de un criterio se llega a su incremento. Una fila por criterio. -->

| Criterio | Incremento(s) | Estado | Nota |
|----------|---------------|--------|------|
| C1 | I_ | pendiente / cubierto / verificado | |

## Registro de revisiones del juez

<!-- Solo BLOQUEANTES, a cierre. Ciclo: abierto → resuelto (fecha + commit) →
verificado (juez). Las sugerencias no se rastrean aquí: van como aviso al gate. -->

| Hallazgo | Incr. | Criterio | Descripción | Estado | Resuelto (fecha · commit) |
|----------|-------|----------|-------------|--------|---------------------------|
| R-I_._ | I_ | C_ | _…_ | abierto | — |
