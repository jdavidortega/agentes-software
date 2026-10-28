---
name: revision-funcional
description: "Rúbrica del revisor funcional independiente del encuadre y el plan: verifica que docs/encuadre.md y docs/plan.md sean completos y consistentes contra su fuente (contexto/) —criterios C# medibles, entradas y salidas del sistema inventariadas y validadas contra muestras, set de oro con ≥5 pares, stack y modelo de despliegue resueltos, decisiones de alto impacto como ADR, cada C# con incremento en trazabilidad— y emite veredicto PASA/FALLA con vacíos R-E.n. Úsala al cerrar el arranque, antes del gate de diseño y de la primera línea de código, y en cada pasada fresca hasta dar PASA. Reporta qué falta; no autora los archivos de contenido."
allowed-tools: Read, Grep, Glob, Bash
---
# Skill: Revisión funcional (revisor funcional)

> Rúbrica del **revisor funcional** (rol analista): verifica que el **encuadre** y el
> **plan** sean completos y consistentes **antes del gate de diseño**, contrastándolos
> con su fuente (`contexto/`). Es el equivalente del juez de código para los artefactos
> del arranque. Cómo se dispara, con qué contexto, qué puede hacer, el formato exacto
> del reporte y cómo se registra: **`AGENTS.md` §9**. Aquí vive solo la rúbrica.

## Cuándo usarla

- Al **cerrar el arranque**, antes del gate de diseño y antes de la primera línea de
  código (Fase 3). Es la revisión funcional independiente de la Fase 2 del arranque: sustituye la
  autovalidación por una revisión con rol propio.
- Se repite (pasada fresca) cada vez que se resuelve un hueco, hasta dar PASA.

## Prompt de invocación (para el agente principal)

Lanza al subagente con este encargo **tal cual** —neutro: sin explicarle cómo llegaste
al encuadre ni justificarle sus elecciones; su valor está en que no hereda tu framing—:

> Actúa como revisor funcional según `.claude/skills/revision-funcional/SKILL.md`: léelo y aplica su
> rúbrica completa. Verifica que `docs/encuadre.md` y `docs/plan.md` sean completos y
> consistentes contra su fuente (`contexto/`), que cada `C#` tenga
> incremento en `docs/trazabilidad.md` y que las decisiones de alto impacto estén como
> ADR en `docs/decisiones.md`. Revisa los vacíos previos en `docs/trazabilidad.md`.
> Sigue el protocolo de `AGENTS.md` §9 y entrega el reporte con su formato exacto
> (Veredicto · Vacíos `R-E.n` con filas listas · Sugerencias · Preguntas · Obstáculos ·
> Recibo generado con `sh scripts/recibos.sh linea …`: tú declaras veredicto, bloqueantes,
> ejecutor y modalidad; la herramienta pone fecha y huella). No escribas en ningún
> archivo ni uses la red: todo va en el reporte.

## Insumos (el contexto en que se apoya)

- **Los derivados:** `docs/encuadre.md` (problema, objetivos, no-objetivos, criterios
  `C#`, set de oro, stack/arquitectura, despliegue) y `docs/plan.md` (enfoque,
  incrementos, fuera de alcance).
- **La fuente:** `contexto/` (documentos, datos y artefactos aportados por la persona;
  `contexto/exploracion/` es trabajo del agente, no fuente). Aquí está la
  independencia: no validar el documento contra sí mismo, sino verificar que **el
  encuadre se deriva de las entradas** y **el plan se deriva del encuadre** —cazando lo
  inferido o alucinado—. Contrasta en particular `docs/encuadre.md` §Entradas y salidas
  contra la carpeta: cada fila cita una muestra que existe (o un bosquejo validado con
  `[supuesto]` diferido); una entrada o salida sin muestra ni bosquejo es un vacío.
- `docs/decisiones.md` (¿las decisiones de alto impacto quedaron como ADR?) y
  `docs/trazabilidad.md` (¿cada `C#` tiene incremento?).
- No hereda la memoria de trabajo de quien redactó: solo archivos + carpetas de
  origen.

## Pasos

1. Lee los insumos. Si falta contexto o hay ambigüedad, **pregunta** (no asumas, no
   completes tú).
2. Evalúa por dimensiones (rúbrica abajo). Cada punto obligatorio: **PASA/FALLA**
   (binario); la coherencia derivada: **observación** de criterio.
3. Entrega el reporte en el **formato del protocolo** (`AGENTS.md` §9): cada vacío con ID
   `R-E.<n>`, qué punto obligatorio incumple y por qué; cada uno accionable.

## Protocolo de vacíos (qué hacer cuando algo falta)

El revisor **no rellena nada**. Para cada vacío, **indica con precisión qué falta** y
pide a la persona una de dos cosas (lo gestiona el agente principal, no el revisor):

- **Darlo en el chat**: el principal lo escribe en la sección que corresponde (si la persona
  prefiere escribirlo ella misma, se le indica dónde), o
- **Agregar un documento** que lo aporte: la persona indica el **nombre del archivo** y
  lo deja en `contexto/` (el agente principal lo tipifica y lo anota en el manifiesto).
- Si el vacío es una **decisión con opciones** (p. ej. stack abierto), se resuelve con
  la persona y queda como **ADR** en `docs/decisiones.md` —no hace falta un documento—.

Después, el agente principal **valida si el dato ya está presente**:

- **Si está** → rutea/actualiza lo afectado (el principal, no el revisor) y se vuelve a
  pasar el revisor sobre **la parte afectada** (no se re-corre todo el arranque).
- **Si no está** → **informa que el vacío sigue abierto y se detiene.** No se avanza al
  gate de diseño con vacíos: hay que llenarlos. No se asume ni se inventa el contenido.

## Rúbrica (dimensiones)

**Completitud (binario — los puntos que DEBEN estar claros):**

- Contexto, objetivos y no-objetivos con contenido real (no marcador ni `<!-- -->`).
- Criterios de aceptación `C#` medibles.
- **Set de oro con ≥5 pares `entrada → salida esperada`**, e incluye **al menos un
  ejemplo concreto de entrada y de salida** —inline en el `.md` o como archivo
  referenciado en `contexto/`)—. No basta describir el formato: tiene que haber
  un ejemplo real.
- **Stack y arquitectura resueltos** (lenguaje+versión, framework+versión, build,
  estilo), con versiones verificadas contra la doc oficial.
- Modelo de despliegue decidido: **destino** (¿solo local, o local + remoto?) y
  **empaquetado** (contenedor / host directo / serverless).
- Si no hubo insumo real (caso 2 de la ingesta): el **bosquejo del modelo de datos**
  está en `docs/plan.md`, con ejemplo concreto por entrada/salida, y fue validado por
  la persona.
- Decisiones de alto impacto registradas como ADR.
- Sin marcas `[FALTA]` ni `[inferido]` sin confirmar.

**Consistencia (criterio):**

- El **encuadre se deriva de `contexto/`**: no hay objetivos, restricciones ni datos
  que no se apoyen en la fuente (lo inferido está marcado y confirmado).
- **Entradas y salidas validadas:** cada fila de §Entradas y salidas apunta a una
  muestra real en `contexto/` (o acceso) y está marcada validada, o es `[supuesto]` con
  validación diferida anotada; toda salida inventariada tiene ejemplo en el set de oro.
- El **plan se deriva del contexto**: cada incremento sirve a un criterio; nada del
  plan excede los criterios ni contradice un no-objetivo.

**Trazabilidad (binario):**

- Cada `C#` está cubierto por al menos un incremento (`docs/trazabilidad.md`).

## En una adopción (proyecto existente)

Aplica cuando el principal pide la revisión **en modo adopción** e indica la **fase y el
alcance** (`docs/arranque-existente.md`). No basta con que exista `contexto/adopcion.md`:
ese archivo sigue ahí en todas las fases posteriores, donde rige la rúbrica normal.

**Alcance Fase 1 (reconocimiento):** se revisa `docs/encuadre.md`, `docs/convenciones.md` y
`docs/decisiones.md`. **La rúbrica es el validador de la Fase 1 de `docs/arranque-existente.md`,
ítem por ítem, con sus actividades como definición**: no se copia aquí, para que no diverja.
Sustituye a la rúbrica de arriba en lo que esta exija distinto: no se exige `docs/plan.md` ni
incrementos en trazabilidad (nacen en la Fase 2), ni un mínimo fijo de pares del set de oro
(el «≥5» de arriba no aplica), ni «versiones verificadas contra la doc oficial» (el stack se
documenta, no se decide). Lo propio del revisor en este modo:
- **Fuente:** el **código** del repositorio, además de `contexto/`. Cada `C#` y cada hallazgo
  se contrasta con el código, muestreando sus citas `archivo:línea`; lo falso o sobredeclarado
  es vacío.
- **Recalcula** al menos una cifra del set de oro desde su artefacto persistido y re-ejecuta un
  script de `contexto/exploracion/` si corre sin red.
- **Observado frente a inferido:** lo marcado `observado en código` tiene que estar literalmente
  en su cita; un comportamiento que exige juntar piezas es `inferido`, y marcarlo como observado
  o comprobado es vacío.
- **Desconocidos:** un hecho pendiente con impacto y responsable no es vacío si ninguna
  garantía declarada verificada depende de él; solo una **elección** exige ADR `propuesta`.
- **Decisiones:** ADR retrospectivos con evidencia, explicación confirmada o hipótesis; no se
  juzgan como decisiones nuevas.
- **Alcance proporcional** (ruta de trabajo elegido): contrasta con el código que el mapa del área
  afectada incluya lo que depende del cambio y aquello con lo que interactúa; una dependencia o
  interacción omitida, o un `C#` `conserva` que solo cubre lo que se edita, es vacío.

**Alcance Fase 2 (diagnóstico y plan):** la rúbrica es el **validador de la Fase 2** del mismo
guion, ítem por ítem, más la **síntesis contra sus fuentes**: cada fila del diagnóstico se
contrasta con el encuadre y con los informes de línea base (`contexto/exploracion/linea-base-*.md`);
un hallazgo relevante omitido, un duplicado sin consolidar, una discrepancia sin justificar o un
incremento que no protege un `C#` ni trata un hallazgo son vacíos. Sustituye a la rúbrica de
arriba en lo que esta exija distinto (los `C#` `conserva` describen lo vigente; solo los `nuevo`
de la ruta de trabajo elegido originan construcción).

## Notas / trampas

- **No inventa requisitos** para "cerrar" un punto: un criterio o un dato faltante es
  un vacío, no algo que el revisor deba suponer.
- **No infla:** no pide artefactos (esquemas, NFR, documentos) que el proyecto no
  necesita; eso también es sobredimensionamiento.
- Se afina con el tiempo: si una verificación de consistencia se repite, súmala a la
  rúbrica.
