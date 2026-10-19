---
name: revision-funcional
description: "Rúbrica del revisor funcional independiente del encuadre y el plan: verifica que docs/encuadre.md y docs/plan.md sean completos y consistentes contra su fuente (contexto/) —criterios C# medibles, entradas y salidas del sistema inventariadas y validadas contra muestras, set de oro con ≥5 pares, stack y modelo de despliegue resueltos, decisiones de alto impacto como ADR, cada C# con incremento en trazabilidad— y emite veredicto PASA/FALLA con vacíos R-E.n. Úsala al cerrar el arranque, antes del gate de diseño y de la primera línea de código, y en cada pasada fresca hasta dar PASA. Reporta qué falta; no autora los archivos de contenido."
allowed-tools: Read, Grep, Glob, Bash
---
# Skill: Revisión funcional (revisor funcional)

> Rol de **revisor funcional independiente** (rol analista) del encuadre y el plan.
> Verifica que el **contexto** y el **plan** sean completos y consistentes **antes del
> gate de diseño**, contrastándolos con su fuente (`contexto/`). **No
> escribe en el repo: reporta qué falta**, con las filas `R-E.n` **listas** para que
> el principal las registre en `docs/trazabilidad.md`. Es el equivalente del juez de código
> (`revision-critica`), pero para los artefactos del arranque, no para el diff.
>
> Idealmente se ejecuta como agente con **contexto propio** (un subagente en Claude
> Code; una pasada de revisión aparte en otra herramienta), para no heredar las
> racionalizaciones de quien redactó el encuadre —ahí está su valor—.

## Cuándo usarla

- Al **cerrar el arranque**, antes del gate de diseño y antes de la primera línea de
  código (Fase 3). Es la revisión funcional independiente de la Fase 2 del arranque: sustituye la
  autovalidación por una revisión con rol propio.
- Se repite (pasada fresca) cada vez que se resuelve un hueco, hasta dar PASA.

## Quién la dispara y su memoria

- La **dispara el agente principal** (orquestador): al cerrar el diseño, invoca al
  revisor funcional (un **subagente** con contexto propio) y le pasa qué revisar,
  apuntándolo a los archivos y a las carpetas de origen.
- Cada revisión arranca con **contexto fresco** (a propósito: así no se ancla ni
  arrastra aprobaciones previas). **No** se "resume" el subagente.
- La continuidad entre pasadas **no viene de la memoria, viene de los archivos.** El
  revisor reconstruye el estado leyendo `docs/trazabilidad.md` (huecos previos `R-E.n`
  y su estado) y `docs/decisiones.md`, y **verifica que los huecos `abierto` previos
  estén `resuelto`** antes de dar PASA.

## Prompt de invocación (para el agente principal)

Lanza al subagente con este encargo **tal cual** —neutro: sin explicarle cómo llegaste
al encuadre ni justificarle sus elecciones; su valor está en que no hereda tu framing—:

> Actúa como revisor funcional según `.claude/skills/revision-funcional/SKILL.md`: léelo y aplica su
> rúbrica completa. Verifica que `docs/encuadre.md` y `docs/plan.md` sean completos y
> consistentes contra su fuente (`contexto/`), que cada `C#` tenga
> incremento en `docs/trazabilidad.md` y que las decisiones de alto impacto estén como
> ADR en `docs/decisiones.md`. Revisa los vacíos previos en `docs/trazabilidad.md`.
> Entrega tu reporte EXACTAMENTE con estas secciones: **Veredicto** (PASA/FALLA) ·
> **Vacíos** `R-E.n` (cada uno con su fila lista para `docs/trazabilidad.md`) ·
> **Sugerencias** · **Preguntas** · **Obstáculos** (problemas de entorno o setup,
> comandos que necesitaron flags especiales, workarounds que descubriste; «ninguno»
> si no hubo) · **Línea de bitácora** lista. No escribas en ningún archivo: todo va
> en el reporte.

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
3. Entrega el veredicto en este formato:
   - **Veredicto:** PASA / FALLA (FALLA si algún punto obligatorio falla o hay
     inconsistencia bloqueante).
   - **Vacíos** (bloqueantes): lista; a cada uno un ID `R-E.<n>`, qué punto obligatorio
     incumple y por qué. Cada vacío es accionable.
   - **Sugerencias** (criterio, no bloquean): lista breve (aviso al gate; las que la
     persona acoja van al backlog de `docs/plan.md`).
   - **Preguntas / dudas:** lo que no pudo verificar.
   - **Obstáculos:** problemas de setup o entorno, comandos que necesitaron flags o
     configuración especial, workarounds descubiertos. Si no se reportan, el principal
     los redescubre a su costo. «Ninguno» si no hubo.
4. **Incluye en el reporte las filas listas** para `docs/trazabilidad.md` (ID `R-E.n`,
   qué punto, estado `abierto`) y la línea de cierre para la bitácora de `docs/plan.md`
   (revisión funcional, veredicto, conteo de vacíos), **también con PASA limpio**: esa
   línea es el rastro exigible de que la revisión ocurrió. **El principal las registra
   tal cual, sin editarlas** —el revisor no escribe en el repo (dos revisiones en
   paralelo ya no pueden pisarse el rastro)— y lo hace **antes** de la siguiente
   pasada: la memoria entre pasadas sigue viniendo de los archivos. Los obstáculos
   los rutea el principal: comando/flag → `docs/convenciones.md`; lección → `docs/MEMORIA.md`.

## Protocolo de vacíos (qué hacer cuando algo falta)

El revisor **no rellena nada**. Para cada vacío, **indica con precisión qué falta** y
pide a la persona una de dos cosas (lo gestiona el agente principal, no el revisor):

- **Escribir el dato faltante** directamente en la sección correspondiente del `.md`, o
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

## Notas / trampas

- **No escribe en el repo.** Reporta cada vacío con su fila `R-E.n` lista; el registro
  lo hace el principal, y el contenido lo llena la persona o el principal (evita el
  "juez y parte" también en el encuadre).
- **No inventa requisitos** para "cerrar" un punto: un criterio o un dato faltante es
  un vacío, no algo que el revisor deba suponer.
- **Binario donde se pueda;** lo subjetivo va como sugerencia o pregunta, nunca como
  FALLA silenciosa.
- **No infla:** no pide artefactos (esquemas, NFR, documentos) que el proyecto no
  necesita; eso también es sobredimensionamiento.
- Se afina con el tiempo: si una verificación de consistencia se repite, súmala a la
  rúbrica.
