# Arranque (guion del agente)

> **Para el agente.** Este es el primer punto de entrada del proyecto: ejecútalo
> ANTES de cualquier diseño o línea de código. Empiezas directamente en el
> encuadre. Tú conduces a la persona paso a paso; no es una lista para que ella
> lea sola.

## REGLA DURA

No se pasa al Paso N+1 hasta que **(a)** el validador del Paso N esté en **PASA**
(condición binaria y verificable, no a tu juicio) **y (b)** la persona lo
**apruebe** explícitamente. Si un validador da FALLA, te detienes, dices qué
falta y qué archivo ajustar, y vuelves a validar. La aprobación es por paso.

## Transversal (durante todo el arranque)

- Cada decisión con **más de una opción razonable** → regístrala en
  `docs/decisiones.md` (ADR-lite). **Esto aplica también durante la ejecución
  (Fase 3)**, no solo en el diseño.
- Cada dato o lección importante que surja → guárdalo en `MEMORIA.md`.
- Ante una bifurcación de diseño, **presenta opciones, no elijas en silencio**.
- Git configurado desde el inicio; **commit por fase/incremento**, con mensaje
  concreto y suficiente (ver `docs/convenciones.md`).

---

## Paso 1 — Encuadre (modo híbrido)

Llena `docs/contexto.md`. Para cada sección, ofrécele a la persona elegir el modo:
**(a)** tú le preguntas **una cosa a la vez** y diligencias tú a partir de sus
respuestas, o **(b)** le entregas esa sección del `.md` estándar para que la llene
y luego tú la revisas. La persona elige por sección; tú no avanzas de una sección
sin su contenido.

**Validador (PASA/FALLA):** en `docs/contexto.md` tienen contenido real —no el
marcador `-` ni el comentario `<!-- -->`— las secciones:
- [ ] Contexto
- [ ] Objetivos
- [ ] No-objetivos
- [ ] Criterios de éxito
- [ ] Set de oro: ≥5 pares `entrada → salida esperada` (orientativo 5–10) que definan
  la calidad aceptable (no solo la funcionalidad).
- [ ] **Stack y arquitectura** definidos (lenguaje+versión, framework+versión, build,
  estilo de arquitectura): **primero búscalo en `material/`** (los requisitos); si no
  está, **pregúntalo con base en el contexto, no asumas un default**; si hay opciones,
  debátelas y regístralas como ADR. Versiones verificadas contra la doc oficial.
- [ ] Modelo de despliegue decidido (contenedor/host/serverless): **pregúntalo**,
  porque condiciona rutas, paridad dev/prod y el bucle de cambios.

---

## Paso 2 — Ingesta de material (entrada → ruteo)

**Pregunta primero:** *"¿Hay material de contexto que deba leer?"* y revisa la
carpeta `material/` (puede haber **varios archivos** de análisis). Sus reglas de
ingesta están en `material/README.md`.

Si la persona aporta material (en `material/` o de otra forma), clasifícalo y
ubícalo con su razón: los **antecedentes y la motivación** van a `docs/contexto.md`;
el **stack, las tecnologías y la arquitectura** que el material defina van a la
sección "Stack y arquitectura" de `docs/contexto.md`; los **datos o decisiones** que
implique, a `docs/decisiones.md`. No metas material
externo directo al proyecto sin clasificarlo. **Propón el ruteo y espera el OK**
(gate) antes de escribir en los archivos oficiales. Si el material **contradice**
algo ya escrito (un criterio, una decisión), no lo archives en silencio: señala qué
queda inconsistente y resuélvelo con la persona.

**No borres la fuente:** el archivo original se queda en `material/` para
trazabilidad; solo se elimina si la persona lo pide. Tras rutear cada archivo,
**registra una fila en el manifiesto** de `material/README.md` (archivo, fecha,
a dónde fue, nota).

**Muestreo de insumos reales (obligatorio antes del gate de diseño).** No diseñes
solo contra la especificación: abre **1–3 muestras reales de cada insumo** (datos,
archivos, respuestas de API) y valida contra ellas los supuestos del spec —formato,
nombres, numeración, casos límite, datos ya pre-extraídos, etc. El trabajo
exploratorio (notebooks, scripts de inspección) vive en `analisis/`. Cada
discrepancia con el spec se registra como decisión en `docs/decisiones.md`. Es
barato y evita rediseñar en plena ejecución.

**Validador (PASA/FALLA):**
- [ ] Se preguntó por material y se revisó `material/`.
- [ ] Todo material aportado quedó clasificado y ubicado (con gate), o se registró
  explícitamente "no hay material externo".
- [ ] Cada archivo procesado tiene su fila en el manifiesto de `material/README.md`.
- [ ] Se muestrearon 1–3 ejemplos reales de cada insumo y se validaron los supuestos
  del spec contra ellos, o se registró "no hay insumos reales disponibles aún".
- [ ] Las discrepancias spec↔realidad quedaron como decisión en `docs/decisiones.md`.

---

## Paso 3 — Diseño (plan mínimo)

**Prerrequisito:** el **stack y la arquitectura** (Paso 1) deben estar resueltos antes
de diseñar; el plan depende de ellos. Si siguen abiertos, ciérralos primero (con ADR).

Propón el enfoque **mínimo** que satisface los criterios de éxito del Paso 1, en
incrementos pequeños y revisables. Marca de forma explícita **qué queda fuera**.
No introduzcas dependencias ni abstracciones sin aprobación (ver `AGENTS.md` §3).

Escribe el plan en `docs/plan.md` (plan vivo: se ajusta con la evidencia y sirve de
bitácora). Lo que no entra ahora va al **backlog** de ese archivo, organizado por
posible incremento futuro.

**Validador (PASA/FALLA):**
- [ ] Existe un plan escrito (enfoque + incrementos) en `docs/plan.md`, acordado.
- [ ] Hay una lista explícita de "fuera de alcance" (en el backlog de `docs/plan.md`).
- [ ] El plan no excede los criterios de éxito (anti-sobredimensionamiento).
- [ ] El plan es coherente con lo visto en el muestreo de insumos reales (Paso 2).

---

## Paso 4 — Validación de consistencia

Revisa estos checks. **No avanzas si alguno da FALLA**: señala cuál falló y qué
archivo ajustar, corrige y vuelve a revisar.

**Validador (PASA/FALLA):**
- [ ] Cada criterio de éxito (`C#`) del Paso 1 está cubierto por algún incremento del
  plan, reflejado en `docs/trazabilidad.md`.
- [ ] El plan no contradice ningún no-objetivo del encuadre.
- [ ] No hay componentes en el plan sin un objetivo que los justifique (anti-exceso).

---

## Paso 5 — Registro

Confirma que el rastro quedó guardado antes de empezar a construir.

**Validador (PASA/FALLA):**
- [ ] Cada decisión con ≥2 opciones razonables (Pasos 1–4) tiene su ADR en
  `docs/decisiones.md`, o se registró "no hubo decisiones de ese tipo".

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
