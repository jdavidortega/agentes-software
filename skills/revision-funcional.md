# Skill: Revisión funcional (revisor funcional)

> Rol de **revisor funcional independiente** del encuadre y el plan. Verifica que el
> **contexto** y el **plan** sean completos y consistentes **antes del gate de
> diseño**, contrastándolos con su fuente (`material/` y `analisis/`). **No escribe ni
> autora los archivos oficiales: reporta qué falta.** Es el equivalente del juez de
> código (`revision-critica.md`), pero para los artefactos del arranque, no para el
> diff.
>
> Idealmente se ejecuta como agente con **contexto propio** (un subagente en Claude
> Code; una pasada de revisión aparte en otra herramienta), para no heredar las
> racionalizaciones de quien redactó el encuadre —ahí está su valor—.

## Cuándo usarla

- Al **cerrar el arranque**, antes del gate de diseño y antes de la primera línea de
  código (Fase 3). Es la revisión independiente del Paso 4 del arranque: sustituye la
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

## Insumos (el contexto en que se apoya)

- **Los derivados:** `docs/contexto.md` (problema, objetivos, no-objetivos, criterios
  `C#`, set de oro, stack/arquitectura, despliegue) y `docs/plan.md` (enfoque,
  incrementos, fuera de alcance).
- **La fuente:** `material/` (lo ingerido) y `analisis/` (hallazgos y datos de
  salida). Aquí está la independencia: no validar el documento contra sí mismo, sino
  verificar que **el contexto se deriva del material** y **el plan se deriva del
  contexto** —cazando lo inferido o alucinado—.
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
   - **Sugerencias** (criterio, no bloquean): lista breve (aviso al gate).
   - **Preguntas / dudas:** lo que no pudo verificar.
4. **Registra los vacíos en `docs/trazabilidad.md`** (ID `R-E.n`, qué punto, estado
   `abierto`). Es la memoria entre pasadas.

## Protocolo de vacíos (qué hacer cuando algo falta)

El revisor **no rellena nada**. Para cada vacío, **indica con precisión qué falta** y
pide a la persona una de dos cosas (lo gestiona el agente principal, no el revisor):

- **Escribir el dato faltante** directamente en la sección correspondiente del `.md`, o
- **Agregar un documento** que lo aporte: la persona indica el **nombre del archivo** y
  el agente principal le indica **en qué carpeta** dejarlo (`material/` para insumos de
  contexto; `analisis/` si es un artefacto/datos).
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
  referenciado (p. ej. en `analisis/`)—. No basta describir el formato: tiene que haber
  un ejemplo real.
- **Stack y arquitectura resueltos** (lenguaje+versión, framework+versión, build,
  estilo), con versiones verificadas contra la doc oficial.
- Modelo de despliegue decidido.
- Decisiones de alto impacto registradas como ADR.
- Sin marcas `[FALTA]` ni `[inferido]` sin confirmar.

**Consistencia (criterio):**

- El **contexto se deriva del material/análisis**: no hay objetivos, restricciones ni
  datos que no se apoyen en la fuente (lo inferido está marcado y confirmado).
- El **plan se deriva del contexto**: cada incremento sirve a un criterio; nada del
  plan excede los criterios ni contradice un no-objetivo.

**Trazabilidad (binario):**

- Cada `C#` está cubierto por al menos un incremento (`docs/trazabilidad.md`).

## Notas / trampas

- **No escribe ni autora los archivos oficiales.** Reporta el vacío; lo llena la
  persona o el agente principal (evita el "juez y parte" también en el encuadre).
- **No inventa requisitos** para "cerrar" un punto: un criterio o un dato faltante es
  un vacío, no algo que el revisor deba suponer.
- **Binario donde se pueda;** lo subjetivo va como sugerencia o pregunta, nunca como
  FALLA silenciosa.
- **No infla:** no pide artefactos (esquemas, NFR, documentos) que el proyecto no
  necesita; eso también es sobredimensionamiento.
- Se afina con el tiempo: si una verificación de consistencia se repite, súmala a la
  rúbrica.
