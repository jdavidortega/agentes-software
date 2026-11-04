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
> **Aceptación.** Rige en el arranque, la adopción, la Fase 3 y la reentrada; es la única definición. Qué
> cuenta como aprobación de la persona lo fija `AGENTS.md` §3.
> - **Decisión nueva.** Un ADR queda `aceptada` solo si identifica la decisión autorizada y su campo
>   **Aprobación** cita la respuesta de la persona que la aprueba: (a) la elección dicha por ella, o (b) su
>   aprobación inequívoca de una propuesta concreta que el ADR referencia («sí, sigue con tu recomendación»
>   sobre esa propuesta). Una autorización previa clara vale dentro de su alcance y condiciones: se cita,
>   sin pedir otra; un «continúa» que no autoriza esta decisión no la aprueba, pero tampoco anula una
>   autorización previa válida. (c) Si para llegar a la opción hay que deducirla de otra frase (p. ej. un
>   motor de base de datos a partir de «que guarde el histórico»), no hay aprobación: queda `propuesta` y
>   se pregunta aparte. La cita se puede contrastar con su fuente (`contexto/`, el brief o el registro de
>   la conversación).
> - **Retrospectivo (adopción).** Un ADR que documenta una decisión anterior al método lleva en
>   **Aprobación** `retrospectivo` y su base, que se mantiene distinta: **evidencia** (archivo),
>   **explicación confirmada** por la persona o **hipótesis**; la fecha es la de documentación en UTC.
>   Se registra en estado `aceptada` solo como documentación retrospectiva de lo vigente: ese estado no
>   acredita una aprobación histórica, no autoriza una acción nueva (p. ej. retirar una prueba o decidir su
>   tratamiento) ni verifica una garantía, y no autoriza modificarlo.
> - **Sustitución.** Cambiar una decisión vigente, también una retrospectiva, es una decisión nueva: su ADR
>   queda `propuesta` hasta su autorización (lo anterior) y enlaza el ADR que sustituiría. El anterior pasa
>   a `reemplazada-por: ADR-###` solo cuando la sustitución está `aceptada` y entra en vigor; hasta
>   entonces sigue vigente.
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
- **Aprobación:** _(si `aceptada`) cita de la elección o de la aprobación de esta propuesta, o
  `retrospectivo: evidencia | explicación confirmada | hipótesis`; vacío mientras esté `propuesta`
  (ver «Aceptación»)._
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
