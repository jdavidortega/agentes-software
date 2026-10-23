# Registro de decisiones (ADR-lite)

> **ADR** = Architecture Decision Record (registro de decisión de arquitectura);
> "-lite" = versión ligera: fecha y hora, contexto, opciones, decisión, razón, consecuencias.
> Una entrada por cada decisión donde había más de una opción razonable.
> El formato es el bloque ADR-000 de abajo: al registrar el primer ADR real, cópialo y borra
> ADR-000 (el doctor lo exige al cierre). Las más recientes primero.
> **Fecha y hora en UTC**, tomadas del reloj real (`date -u`), no de memoria.
>
> **Estado y decisiones diferidas.** Un ADR en estado **`propuesta`** es una decisión
> **abierta** que aún no se toma (p. ej. detectaste el dilema en la Ingesta pero se
> decide en el Encuadre). Regístrala igual desde que aparece, con **`Se resuelve en:`**
> la actividad correspondiente. El gate de esa actividad no se cruza con ADRs en
> `propuesta` pendientes: ahí pasan a **`aceptada`** (con su decisión y razón). Así una
> decisión diferida queda rastreada, no como una promesa en prosa que se pierde.
>
> **Ciclo de vida.** Cuando un ADR se reemplaza o se revierte, **el estado se actualiza
> en el ADR superado** (`reemplazada-por: ADR-###` / `revertida-por: ADR-###`), no solo
> se anota en el nuevo. Un registro donde todo figura "aceptada" —incluido lo revertido—
> no es auditable.

---

## ADR-000 — Plantilla (ejemplo, borrar)

- **Fecha y hora (UTC):** AAAA-MM-DD HH:MM
- **Estado:** propuesta | aceptada | reemplazada-por: ADR-XXX | revertida-por: ADR-XXX
- **Se resuelve en:** _(solo si está `propuesta`) actividad/fase donde se decidirá._
- **Contexto:** _qué problema o disyuntiva nos llevó a decidir._
- **Opciones consideradas:**
  - A) _…_
  - B) _…_
- **Decisión:** _qué se eligió._
- **Razón:** _por qué, frente a las alternativas._
- **Consecuencias:** _qué implica (positivo y negativo), qué deuda asumimos. Si incluye
  una reversión futura prevista (p. ej. deshacer un downgrade), esa reversión va
  **también al backlog** de `docs/plan.md`, no solo aquí._

---
