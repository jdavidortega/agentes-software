# Registro de decisiones (ADR-lite)

> **ADR** = Architecture Decision Record (registro de decisión de arquitectura);
> "-lite" = versión ligera: fecha y hora, contexto, opciones, decisión, razón, consecuencias.
> Una entrada por cada decisión donde había más de una opción razonable.
> Copia el bloque de abajo hacia arriba (las más recientes primero).
> **Fecha y hora en UTC**, tomadas del reloj real (`date -u`), no de memoria.
>
> **Estado y decisiones diferidas.** Un ADR en estado **`propuesta`** es una decisión
> **abierta** que aún no se toma (p. ej. detectaste el dilema en la Ingesta pero se
> decide en el Encuadre). Regístrala igual desde que aparece, con **`Se resuelve en:`**
> la actividad correspondiente. El gate de esa actividad no se cruza con ADRs en
> `propuesta` pendientes: ahí pasan a **`aceptada`** (con su decisión y razón). Así una
> decisión diferida queda rastreada, no como una promesa en prosa que se pierde.

---

## ADR-000 — Plantilla (ejemplo, borrar)

- **Fecha y hora (UTC):** AAAA-MM-DD HH:MM
- **Estado:** propuesta | aceptada | reemplazada por ADR-XXX
- **Se resuelve en:** _(solo si está `propuesta`) actividad/fase donde se decidirá._
- **Contexto:** _qué problema o disyuntiva nos llevó a decidir._
- **Opciones consideradas:**
  - A) _…_
  - B) _…_
- **Decisión:** _qué se eligió._
- **Razón:** _por qué, frente a las alternativas._
- **Consecuencias:** _qué implica (positivo y negativo), qué deuda asumimos._

---
