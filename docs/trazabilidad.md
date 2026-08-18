# Trazabilidad

> El "hilo" mínimo que conecta **requisitos → incrementos → revisión**, con estado.
> Inteligente = mínimo: solo se rastrea lo que ayuda a decidir. Demasiada
> trazabilidad se vuelve carga y se abandona; si rastrear algo no aporta, no lo hagas.
> **Toda marca de tiempo va en UTC** (`AAAA-MM-DD HH:MM`), tomada del reloj real
> (`date -u`), no de memoria.

## IDs y cómo se enlazan

- **Criterios de éxito:** `C1, C2…` (definidos en `docs/contexto.md`).
- **Incrementos:** `I1, I2…` (en `docs/plan.md`).
- **Decisiones:** `ADR-###` (en `docs/decisiones.md`).
- **Alias:** todo `C#`, `I#` y hallazgo lleva un alias (slug de 2–4 palabras; ver
  `docs/convenciones.md` §Identificadores y alias). El de los `C#` y hallazgos vive
  **aquí** (columna Alias, único lugar); el de los `I#`, junto al incremento en
  `docs/plan.md`. Se cita siempre `ID «alias»`.
- **Vacíos del revisor funcional (arranque):** `R-E.<n>` (p. ej. `R-E.1`); se registran
  al cerrar el arranque y se cierran (la persona llena el hueco) antes del gate de diseño.
- **Hallazgos del juez (ejecución):** `R-I<incremento>.<n>` (p. ej. `R-I3.1`).
- **Hallazgos del juez de seguridad:** `R-S<incremento>.<n>` (p. ej. `R-S3.1`). Mismo
  ciclo y misma tabla que los del juez; el prefijo los distingue de un vistazo en el gate.
- **Commits** enlazan en el footer: `Ref: F#` (cierre de fase — `F1`, `F2`, `F4`, `F5`),
  `Ref: I3` (incremento de la Fase 3), `Cierra: R-I3.1` (hallazgo del juez),
  `Cierra: R-S3.1` (hallazgo de seguridad) o `Cierra: R-E.1` (vacío del revisor
  funcional).

## Cobertura de criterios

<!-- Forward: qué incremento satisface cada criterio y si está verificado.
Backward: de un criterio se llega a su incremento. Una fila por criterio.
`verificado` se marca pieza a pieza en la Fase 3; la Fase 4 (conjunto) no cambia
estados aquí: su resultado queda en la bitácora de plan.md y el commit `Ref: F4`. -->

| Criterio | Alias | Incremento(s) | Estado | Nota |
|----------|-------|---------------|--------|------|
| C1 | «…» | I_ | pendiente / cubierto / verificado | |

## Registro de vacíos del revisor funcional (arranque)

<!-- Vacíos de completitud/consistencia del encuadre, a cierre del arranque. Ciclo:
abierto → resuelto (la persona llenó el hueco). Deben quedar todos resueltos antes
del gate de diseño; no se rastrean las sugerencias (las acogidas → backlog de plan.md). -->

| Vacío | Alias | Punto incumplido | Estado | Resuelto (cómo · AAAA-MM-DD HH:MM UTC) |
|-------|-------|------------------|--------|----------------------------------------|
| R-E._ | «…» | _…_ | abierto | — |

## Registro de revisiones del juez

<!-- Solo BLOQUEANTES, a cierre. Ciclo: abierto → resuelto (fecha + commit) →
verificado (juez). Incluye los de seguridad (`R-S#.n`): misma tabla, mismo ciclo. En
esos, la columna Criterio lleva el `C#` que protege o la categoría OWASP/CWE. Las
sugerencias no se rastrean aquí: van como aviso al gate (las acogidas → backlog de
plan.md). -->

| Hallazgo | Alias | Incr. | Criterio | Descripción | Estado | Resuelto (AAAA-MM-DD HH:MM UTC · commit) |
|----------|-------|-------|----------|-------------|--------|------------------------------------------|
| R-I_._ | «…» | I_ | C_ | _…_ | abierto | — |

## Histórico (compactado)

<!-- Hallazgos `verificado` archivados en la compactación del cierre de incremento:
UNA línea por hallazgo. El detalle completo vive en git
(`git log --grep="Cierra: R-…"`); el porqué, en los ADR. -->

- _(ejemplo)_ `R-I_._ «alias» · verificado AAAA-MM-DD · commit abc1234`
