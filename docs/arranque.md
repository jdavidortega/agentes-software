# Arranque (guion del agente)

> **Para el agente.** Este es el primer punto de entrada del proyecto: ejecútalo
> ANTES de cualquier diseño o línea de código. Empiezas por **ingerir el material**
> y solo después construyes el encuadre sobre esa base. Tú conduces a la persona
> paso a paso; no es una lista para que ella lea sola.

> **Cómo se relacionan estos pasos con las 5 fases** (`AGENTS.md` §2): los Pasos 1–5
> de este arranque ocurren **dentro de las Fases 1 y 2**. Ingesta + Encuadre (Pasos
> 1–2) = **Fase 1 (Encuadre)**; Diseño + Revisión funcional + Registro (Pasos 3–5) =
> **Fase 2 (Diseño/plan)**. La **Fase 3 (Ejecución)** —la primera línea de código—
> empieza solo cuando el arranque termina y el gate de diseño está aprobado.

## REGLA DURA

No se pasa al Paso N+1 hasta que **(a)** el validador del Paso N esté en **PASA**
(condición binaria y verificable, no a tu juicio) **y (b)** la persona lo
**apruebe** explícitamente. Si un validador da FALLA, te detienes, dices qué
falta y qué archivo ajustar, y vuelves a validar. La aprobación es por paso.

**Cómo pides la aprobación (gate accionable).** Si no mostraste el contenido en el
chat (está bien por eficiencia de tokens), no pidas un OK en abstracto: indica **qué
archivos revisar** y **qué información concreta** contiene cada uno —p. ej. "revisa
`docs/contexto.md`: los criterios `C1–C4`, el set de oro y el modelo de despliegue"— y
di que **debe validarlos antes de continuar**. Nada de "ya quedó, ¿seguimos?".

**Precondición de arranque:** no se construye el encuadre sin material. La carpeta
`material/` debe tener **≥1 archivo real** (además de su `README.md`). Si está
vacía, **detente** y pídelo: aunque sea un brief breve escrito a propósito. El
encuadre se deriva del material, no de lo que la persona alcance a teclear en
frío.

## Transversal (durante todo el arranque)

- Cada decisión con **más de una opción razonable** → regístrala en
  `docs/decisiones.md` (ADR-lite), **con fecha y hora UTC** del reloj real (`date -u`).
  **Esto aplica también durante la ejecución (Fase 3)**, no solo en el diseño.
- Cada dato o lección importante que surja → guárdalo en `docs/MEMORIA.md`.
- Ante una bifurcación de diseño, **presenta opciones, no elijas en silencio**.
- Git configurado desde el inicio; **commit al cierre de cada fase y de cada
  incremento**, no solo en la Fase 3. En el arranque, eso significa al menos un commit
  al aprobar el **encuadre** (`Ref: F1`) y otro al aprobar el **plan** (`Ref: F2`).
  Ningún gate se cruza con cambios sin commitear (ver `docs/convenciones.md`).

---

## Paso 1 — Ingesta de entradas (material + análisis)

El arranque empieza por aquí: primero **inventarías lo que hay**, confirmas con la
persona que está completo, y solo entonces lo analizas y rutas. Hay dos carpetas
de entrada con roles distintos:

- `material/` — lo que se **lee y se rutea**: antecedentes, motivación, specs,
  notas, decisiones. **Obligatorio** (precondición de arranque). Reglas de ingesta
  en `material/README.md`.
- `analisis/` — **artefactos analíticos**: notebooks, scripts, datos de entrada
  (opcional) y datos de salida/resultados. Es lo que se *ejecuta o inspecciona*,
  no lo que se *lee*. **Opcional**, pero **revisarla es obligatorio**. Reglas en
  `analisis/README.md`.

**1a. Inventaría y confirma (gate de completitud).** Lista lo que encuentres en
`material/` y en `analisis/` (acuse de recibo) y pregunta: *"¿esto es todo, o
quieres agregar más antes de que lo analice?"*. No inviertas en analizar hasta que
la persona cierre el set de entrada. Si `material/` está vacía → aplica la
precondición de arranque y detente.

**1b. Clasifica y rutea (gate de ruteo).** Para cada entrada, **propón** a dónde va
con su razón y espera el OK antes de escribir en los archivos oficiales. La ingesta
**siembra los documentos vivos desde el principio** con lo que el material ya
provea: no se dejan vacíos para "después" si el material tiene contenido para ellos.
Esto incluye:

- De `material/`: los **antecedentes y la motivación** → `docs/contexto.md`; el
  **stack, tecnologías y arquitectura** que el material defina → sección "Stack y
  arquitectura" de `docs/contexto.md`; las **convenciones operativas** que el material
  ya traiga (estilo de código, patrones, comandos de build/test/run, layout de
  entorno) → `docs/convenciones.md`, **verificando comandos y versiones contra la doc
  oficial vigente** antes de fijarlos (no los tomes de memoria ni de material que
  pueda estar desactualizado); los **datos o decisiones** que implique →
  `docs/decisiones.md`.
- De `analisis/` (si tiene contenido): los **hallazgos/resultados** del análisis
  previo → `docs/contexto.md` §Contexto; los **pares datos de entrada → datos de
  salida** son **candidatos directos al set de oro** de `docs/contexto.md`,
  proponlos como tales; las **discrepancias o decisiones** que revele →
  `docs/decisiones.md`. Los notebooks y datos crudos **se quedan** en `analisis/`
  como referencia y se **enlazan** desde `contexto.md`; no se copian.

**No borres la fuente:** los originales se quedan en su carpeta para trazabilidad;
solo se eliminan si la persona lo pide. Tras rutear cada archivo de `material/`,
**registra una fila en el manifiesto** de `material/README.md` (archivo, fecha, a
dónde fue, nota). Si el material **contradice** algo ya escrito (un criterio, una
decisión), no lo archives en silencio: señala la inconsistencia y resuélvela con
la persona.

**Muestreo de insumos reales (obligatorio antes del gate de diseño).** No diseñes
solo contra la especificación: abre **1–3 muestras reales de cada insumo** (datos,
archivos, respuestas de API) y valida contra ellas los supuestos del spec —formato,
nombres, numeración, casos límite, datos ya pre-extraídos, etc. El trabajo
exploratorio nuevo vive en `analisis/`. Cada discrepancia con el spec se registra
como decisión en `docs/decisiones.md`. Es barato y evita rediseñar en plena
ejecución.

**Validador (PASA/FALLA):**
- [ ] `material/` tiene ≥1 archivo real además del `README.md` (precondición dura).
- [ ] Se inventarió `material/` y `analisis/` y la persona confirmó que el set de
  entrada está completo.
- [ ] Todo el material aportado quedó clasificado y ruteado (con gate).
- [ ] `analisis/` fue revisada: si tenía contenido, sus hallazgos quedaron ruteados
  (con gate) y los datos de salida se evaluaron como candidatos a set de oro; si
  estaba vacía, se registró explícitamente "no hay análisis previo".
- [ ] Cada archivo de `material/` procesado tiene su fila en el manifiesto de
  `material/README.md`.
- [ ] Se muestrearon 1–3 ejemplos reales de cada insumo y se validaron los supuestos
  del spec contra ellos, o se registró "no hay insumos reales disponibles aún".
- [ ] Las discrepancias spec↔realidad quedaron como decisión en `docs/decisiones.md`.

---

## Paso 2 — Encuadre (revisar y completar el borrador)

Con la ingesta hecha, ya tienes un **borrador de `docs/contexto.md` derivado del
material y el análisis**. El encuadre **no parte de cero**: es revisar ese borrador
con la persona y **cerrar los huecos**. Marca cada dato como `[del material]`,
`[inferido]` o `[FALTA]`, y para cada `[FALTA]` ofrécele elegir el modo: **(a)** tú
le preguntas **una cosa a la vez** y diligencias tú, o **(b)** le entregas esa
sección para que la llene y luego la revisas. No avanzas de una sección sin su
contenido.

Hay partes del encuadre que el material rara vez trae completas —**criterios de
éxito, no-objetivos, set de oro y modelo de despliegue**—: ahí la colaboración con
la persona sigue siendo necesaria; deriva lo que puedas y pregunta dirigido por el
resto. Para **stack y arquitectura**: primero búscalo en `material/`; si no está,
**pregúntalo con base en el contexto, no asumas un default**; si hay opciones,
debátelas y regístralas como ADR (versiones verificadas contra la doc oficial).

**Validador (PASA/FALLA):** en `docs/contexto.md` tienen contenido real —no el
marcador `-` ni el comentario `<!-- -->`— las secciones:
- [ ] Contexto
- [ ] Objetivos
- [ ] No-objetivos
- [ ] Criterios de éxito
- [ ] Set de oro: ≥5 pares `entrada → salida esperada` (orientativo 5–10) que definan
  la calidad aceptable (no solo la funcionalidad), con **al menos un ejemplo concreto
  de entrada y de salida** (inline o como archivo referenciado, no solo el formato).
  Usa los datos de salida de `analisis/` como base cuando existan.
- [ ] **Stack y arquitectura** definidos (lenguaje+versión, framework+versión, build,
  estilo de arquitectura), con versiones verificadas contra la doc oficial.
- [ ] Modelo de despliegue decidido (contenedor/host/serverless).
- [ ] No queda ningún `[FALTA]` ni `[inferido]` sin confirmar con la persona.
- [ ] El encuadre quedó en un **commit** (`Ref: F1`) antes de pedir el gate.

---

## Paso 3 — Diseño (plan mínimo)

**Prerrequisito:** el **stack y la arquitectura** (Paso 2) deben estar resueltos antes
de diseñar; el plan depende de ellos. Si siguen abiertos, ciérralos primero (con ADR).

Propón el enfoque **mínimo** que satisface los criterios de éxito del Paso 2, en
incrementos pequeños y revisables. Marca de forma explícita **qué queda fuera**.
No introduzcas dependencias ni abstracciones sin aprobación (ver `AGENTS.md` §3).

Escribe el plan en `docs/plan.md` (plan vivo: se ajusta con la evidencia y sirve de
bitácora). Lo que no entra ahora va al **backlog** de ese archivo, organizado por
posible incremento futuro.

**Validador (PASA/FALLA):**
- [ ] Existe un plan escrito (enfoque + incrementos) en `docs/plan.md`, acordado.
- [ ] Hay una lista explícita de "fuera de alcance" (en el backlog de `docs/plan.md`).
- [ ] El plan no excede los criterios de éxito (anti-sobredimensionamiento).
- [ ] El plan es coherente con lo visto en el muestreo de insumos reales (Paso 1).

---

## Paso 4 — Revisión funcional (consistencia del encuadre)

Esta revisión **no la hace el agente principal por sí mismo**: la ejecuta el **revisor
funcional** como subagente con **contexto propio** (rol y rúbrica en
`skills/revision-funcional.md`), para no validar el encuadre contra las
racionalizaciones de quien lo redactó. Revisa `contexto.md` y `plan.md` **contra su
fuente** (`material/` y `analisis/`) y verifica que los puntos que deben estar claros
estén resueltos.

El revisor **reporta, no escribe**. Si encuentra un vacío, **indica qué falta** y se
aplica el protocolo de vacíos del skill: la persona lo **escribe** en el `.md` o
**agrega un documento** (con nombre indicado, en la carpeta que el principal le señale:
`material/` o `analisis/`); el principal **valida si ya está** y, de estarlo, re-pasa
el revisor sobre la parte afectada (no se re-corre todo). **No se avanza con vacíos
abiertos.**

**Validador (PASA/FALLA):**
- [ ] El revisor funcional emitió **veredicto PASA** (rúbrica completa en
  `skills/revision-funcional.md`).
- [ ] Cada criterio de éxito (`C#`) del Paso 2 está cubierto por algún incremento del
  plan, reflejado en `docs/trazabilidad.md`.
- [ ] El plan no contradice ningún no-objetivo del encuadre y no excede los criterios
  (anti-exceso).
- [ ] No quedan vacíos (`R-E.n`) en estado `abierto` en `docs/trazabilidad.md`.

---

## Paso 5 — Registro

Confirma que el rastro quedó guardado antes de empezar a construir.

**Validador (PASA/FALLA):**
- [ ] Cada decisión con ≥2 opciones razonables (Pasos 1–4) tiene su ADR en
  `docs/decisiones.md` (con fecha/hora UTC), o se registró "no hubo decisiones de ese
  tipo".
- [ ] El plan, los ADRs y la trazabilidad inicial quedaron en un **commit**
  (`Ref: F2`) antes de pedir el gate de diseño.

---

> Solo cuando el Paso 5 está en PASA y aprobado empieza la **Fase 3 — Ejecución
> iterativa** (la primera línea de código). Antes, no.

> **En cada incremento de la Fase 3:** ciérralo con una **verificación exploratoria
> sobre datos/insumos reales** (no solo fixtures sintéticos: el humano detecta lo que
> un test verde no muestra) y, si toca el despliegue, en **condiciones reales del
> modelo elegido** (empaquetado/datos de producción). Antes del commit, pasa una
> **revisión crítica independiente** (rol juez, `skills/revision-critica.md`): emite
> veredicto + hallazgos (con ID `R-I#.n` y estado en `docs/trazabilidad.md`); los
> bloqueantes se resuelven como subtareas y se marcan `resuelto` antes de continuar.
> Aplica la Definición de Hecho (`docs/definicion-de-hecho.md`), haz **commit enlazado**
> (`Ref:`/`Cierra:`), y anota el avance en `docs/plan.md` y la trazabilidad.
