# Plan y diseño (vivo)

> Fase 2 — Diseño / plan. Aquí vive la **solución** (el problema está en
> `contexto.md`). No es estático: nace en el diseño y se ajusta con la evidencia.
> Reúne el diseño, el plan por incrementos, la bitácora y el backlog. Manténlo conciso.

## Enfoque y arquitectura

<!-- El enfoque MÍNIMO que satisface los criterios de éxito. Por qué este y no otro.
Si el proyecto lo amerita, describe aquí la arquitectura: componentes y cómo se
relacionan. OPCIONAL: en proyectos pequeños basta el enfoque + los ADR; no la
inventes si no aporta (anti-sobredimensionamiento). -->
-

## Modelo de datos (entradas/salidas)

<!-- OBLIGATORIO si el sistema produce salida estructurada; si no, no lo inventes
(anti-sobredimensionamiento). El esquema de SALIDA se define ANTES de construir:
campos, tipos y UN ejemplo concreto, coherente con el set de oro de contexto.md.
Si no hubo insumo real (caso 2 de la ingesta), aquí aterriza el bosquejo diseñado y
validado con la persona. Es un CONTRATO: el revisor funcional lo verifica contra lo
que el consumidor real ejecuta, y cambiarlo después requiere ADR. -->
-

## Incrementos

<!-- Pasos pequeños y revisables, en orden. ID I# con su alias «slug» (aquí vive el
alias de los incrementos); indica qué criterio(s) C# satisface (enlace en
docs/trazabilidad.md). Marca el estado. -->
- [ ] I1 «…» — _…_ (satisface: C_)
- [ ] I2 «…» — _…_ (satisface: C_)

## Bitácora

<!-- Una línea por avance o ajuste. Lo que cambió respecto al plan y por qué.
Las decisiones con alternativas van a docs/decisiones.md; aquí queda el rastro.
Registra una línea de cierre de CADA revisión independiente (juez o revisor funcional:
qué revisó, veredicto y conteo de hallazgos, "ver trazabilidad"), TAMBIÉN cuando es
PASA sin hallazgos: esa línea es el rastro de que la revisión ocurrió. El detalle de
hallazgos y su estado vive en docs/trazabilidad.md.
COMPACTACIÓN: al cerrar un incremento, sus líneas se colapsan a UNA (resumen del
incremento); el detalle queda en git. Al cierre va también la línea de consumo
(scripts/consumo.py; formato en docs/convenciones.md §Contexto). -->
- [AAAA-MM-DD] _…_

## Fuera de alcance / backlog

<!-- Lo que NO entra ahora pero podría hacerse después, organizado por posible
incremento futuro. Aquí quedan guardadas las mejoras que van surgiendo (incluidas
las sugerencias del juez o del revisor funcional que la persona acoja, y las
reversiones futuras previstas en las Consecuencias de un ADR).
Si la decisión de "hasta dónde cubrir" tuvo alternativas, regístrala además como
ADR en docs/decisiones.md (la lista va aquí; el porqué, allá). -->
- _…_
