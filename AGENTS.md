# AGENTS.md — Manual de operación del agente

> Este es el archivo canónico de instrucciones para cualquier agente de IA que
> trabaje en este proyecto (Claude Code, Codex, Cursor, etc.). Es la fuente de
> verdad. `CLAUDE.md` solo lo importa; no dupliques contenido aquí en otros
> archivos de herramienta.

## 0. Punto de entrada obligatorio

Antes de cualquier diseño o línea de código, abre y ejecuta `docs/arranque.md`.
Es el guion de arranque determinista: conduce a la persona paso a paso, con una
condición de salida binaria por paso y un gate humano entre cada uno. No empieces
por otro lado.

Verifica también que **git esté configurado** antes de empezar; si no lo está,
detente y pídelo. Se hace un commit por fase/incremento (ver `docs/convenciones.md`).

## 1. Qué es este proyecto

<!-- Una o dos frases. El detalle vive en docs/contexto.md -->
- **Proyecto:** _[nombre]_
- **Propósito:** _[qué problema resuelve, en una frase]_
- **Contexto y objetivos completos:** ver `docs/contexto.md`

## 2. Cómo trabajamos: las 5 fases

El trabajo avanza por fases, con una **compuerta humana** entre cada una. No se
pasa a la siguiente fase sin aprobación explícita de la persona.

1. **Encuadre** — contexto, objetivos, criterios de éxito, *no-objetivos*, **set de
   oro** (ejemplos de salida esperada), **stack y arquitectura** y **modelo de
   despliegue**. Incluye muestrear insumos reales. No asumas un stack por defecto:
   pregúntalo.
   → Gate: la persona confirma que el encuadre es correcto.
2. **Diseño / plan** — el enfoque elegido y las decisiones de alcance, en
   `docs/plan.md` (plan vivo + bitácora + backlog).
   → Gate: la persona aprueba el plan antes de escribir código.
3. **Ejecución iterativa** — incrementos pequeños y revisables, no de un golpe. Cada
   incremento: verificación sobre datos reales, **revisión crítica independiente
   antes del commit** (el agente principal invoca al juez como subagente con contexto
   propio; ver `skills/revision-critica.md`), ADR si hubo decisión, commit **enlazado**
   (`Ref:`/`Cierra:`), y trazabilidad al día (`docs/plan.md` + `docs/trazabilidad.md`).
4. **Validación** — ver `docs/definicion-de-hecho.md`.
   → Gate: la persona confirma que se cumple la Definición de Hecho.
5. **Cierre y aprendizaje** — retrospectiva breve; lecciones a `MEMORIA.md`.

## 3. Cuándo DETENERTE y preguntar

Antes de hacer cualquiera de estas cosas, **párate y pide aprobación explícita**.
No las generalices: una aprobación es por acción, no permanente.

- Agregar una nueva dependencia o librería.
- Introducir una abstracción nueva (capa, patrón, framework).
- Cambiar la estructura del proyecto o interfaces públicas.
- Cualquier acción destructiva o irreversible (borrar datos, force-push, migraciones).
- Cuando el alcance vaya a exceder los criterios de éxito definidos.
- Cuando haya más de una opción razonable: **presenta opciones, no elijas en silencio.**

**Decisiones de alto impacto** (requisitos, alcance, stack, tecnologías, arquitectura,
despliegue): son tan relevantes como los requisitos. Se **discuten explícitamente y
quedan claras y registradas** (en el encuadre o como ADR) antes de avanzar.

**Proporcionalidad — sé concreto, no hagas mil preguntas:** agrupa lo relacionado y
presenta opciones con tu **recomendación** en una sola pasada. Reserva las preguntas
para lo de alto impacto; lo de bajo impacto y reversible, decídelo con un **default
sensato**, dilo, y sigue.

## 4. Guardas anti-sobredimensionamiento

Antes de añadir algo, pregúntate:

- ¿Resuelve un problema **presente** o uno **hipotético**?
- ¿Cuál es lo **mínimo** que satisface los criterios de éxito?
- Regla de oro: se introduce cuando se necesita, **no antes**.

Riesgo típico: abstracción prematura y dependencias especulativas.

Lo mismo aplica a la **documentación**: lean en dos ejes. Prefiere ampliar un
archivo a crear uno nuevo, pero no contamines los archivos base (`contexto.md`,
`convenciones.md`, `AGENTS.md`…) con exceso de detalle. Si un contenido los infla,
un archivo nuevo es lo correcto: propónlo con explicación y pide autorización.

## 5. Registro de decisiones

Toda decisión con más de una opción razonable se documenta en
`docs/decisiones.md` (formato ADR-lite). Esto sirve para dos cosas: trazabilidad
y aprendizaje.

## 6. Convenciones

El "cómo hacemos las cosas aquí" (estilo, patrones, comandos) vive en
`docs/convenciones.md`. Léelo al inicio de cada sesión.

## 7. Memoria y skills (ciclo de aprendizaje)

- Una lección puntual va a `MEMORIA.md`.
- Cuando una lección se repite y se vuelve un patrón estable, **promuévela a una
  skill** en `skills/` (un procedimiento reutilizable). Ver `skills/README.md`.

## 8. Nota sobre reglas que no pueden fallar

Este archivo moldea el comportamiento típico del agente; **no lo garantiza**. Si
una regla no puede permitirse ser "mayormente seguida" (un test obligatorio, un
escaneo de seguridad), refuérzala en CI / pre-commit / hooks, no solo aquí.
