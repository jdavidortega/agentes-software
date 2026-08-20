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
detente y pídelo. Se hace **un commit al cierre de cada fase y de cada incremento**
—no solo en la Fase 3—: el encuadre, el plan, cada incremento, la validación y el
cierre quedan cada uno en su commit. Ningún gate se cruza con cambios sin commitear
(ver `docs/convenciones.md`).

**Reentrada al contexto (proyecto en marcha):** en cada sesión, lee `docs/estado.md`
(el resumen vivo) y `docs/convenciones.md`, y abre los demás documentos **solo en la
rebanada que la tarea toca**. No se relee todo el rastro por sesión: el detalle vive
en los documentos por rebanada y la historia, en git.

## 1. Qué es este proyecto

<!-- Una o dos frases. El detalle vive en docs/contexto.md -->
- **Proyecto:** _[nombre]_
- **Propósito:** _[qué problema resuelve, en una frase]_
- **Contexto y objetivos completos:** ver `docs/contexto.md`

## 2. Cómo trabajamos: las 5 fases

El trabajo avanza por fases, con una **compuerta humana** entre cada una. No se
pasa a la siguiente fase sin aprobación explícita de la persona.

**Cómo se cierra una fase:** (a) su trabajo queda en un **commit** (ver §0 y
`docs/convenciones.md`), (b) se pide aprobación de forma **concreta**, y (c) el
`README.md` quedó **verificado contra la realidad del código** (qué hace, cómo se
ejecuta, entradas/salidas) y corregido en ese mismo commit si estaba desfasado —el
agente lo hace por defecto, sin que la persona lo pida; ningún gate se solicita con
el README desactualizado (formato: `skills/escribiendo-readme/SKILL.md`)—. Si no
mostraste el contenido en el chat —está bien no hacerlo, por eficiencia de tokens—,
no pidas un OK en abstracto: dile a la persona **qué documentos revisar** (p. ej.
`docs/contexto.md`, `docs/plan.md`, `docs/decisiones.md`) y **qué información
concreta** contiene cada uno (los criterios `C#`, el set de oro, los incrementos, la
decisión registrada…), y que **debe validarlos antes de continuar**. El mensaje del
gate debe ser accionable: "revisa X, que contiene Y", no "ya terminé, ¿seguimos?".

1. **Encuadre** — contexto, objetivos, criterios de éxito, *no-objetivos*, **set de
   oro** (ejemplos de salida esperada), **stack y arquitectura** y **modelo de
   despliegue** (dos preguntas: **destino** —¿solo local, o también remoto?; el
   despliegue local siempre existe— y **empaquetado** —contenedor recomendado—).
   **Arranca por la ingesta de las entradas, no por el encuadre en
   frío:** `material/` es **obligatorio** (≥1 archivo) y `analisis/` opcional pero de
   revisión obligatoria; el encuadre se **deriva** de ahí y luego se completan los
   huecos. Incluye muestrear insumos reales. No asumas un stack por defecto:
   pregúntalo. Detalle operativo en `docs/arranque.md`.
   → Antes del gate: **commit del encuadre** (`Ref: F1`).
   → Gate: la persona confirma que el encuadre es correcto.
2. **Diseño / plan** — el enfoque elegido y las decisiones de alcance, en
   `docs/plan.md` (plan vivo + bitácora + backlog). La arquitectura propuesta se
   **socializa antes del gate**: diagrama gerencial sembrado en el `README.md` y
   validado con la persona, iterando hasta su OK
   (`skills/escribiendo-readme/SKILL.md`). Antes del gate, el encuadre y el
   plan pasan una **revisión funcional independiente** (el agente principal invoca al
   **revisor funcional** como subagente con contexto propio; reporta, no escribe; ver
   `skills/revision-funcional/SKILL.md`): verifica completitud y consistencia contra la
   fuente (`material/`, `analisis/`) y no se avanza con vacíos abiertos.
   → Antes del gate: **commit del plan** (`Ref: F2`), con ADRs y trazabilidad inicial.
   → Gate: la persona aprueba el plan antes de escribir código.
3. **Ejecución iterativa** — incrementos pequeños y revisables, no de un golpe. Cada
   incremento: verificación sobre datos reales, **revisión crítica independiente
   antes del commit** (el agente principal invoca al juez como subagente con contexto
   propio; ver `skills/revision-critica/SKILL.md`) —más la **pasada del juez de
   seguridad** si el incremento toca superficie de riesgo: entrada no confiable,
   authn/authz, secretos, persistencia, IaC/despliegue o IA/LLM (ver
   `skills/revision-seguridad/SKILL.md`)—, ADR si hubo decisión, commit **enlazado**
   (`Ref:`/`Cierra:`), y trazabilidad al día (`docs/plan.md` + `docs/trazabilidad.md`).
   **Salida de la fase (cuándo termina el bucle):** cuando **todos los criterios `C#`
   están en estado `verificado`** en `docs/trazabilidad.md` y todo hallazgo `R-I#.n` y
   `R-S#.n` cerró su ciclo completo (ninguno `abierto`). **Cómo se pasa a `verificado`**
   depende de qué sea la remediación, y la regla es escalonada:

   - **Remediación mecanizable** (código, SQL, un chequeo): quien la resuelve **deja escrita
     en su fila la mutación exacta que ahora muere**, y el hallazgo pasa a `verificado`
     cuando un **revisor independiente** —no necesariamente quien lo levantó— la deshace en
     una **copia** del árbol, la suite se pone en rojo, y **añade al menos una mutación que
     el autor del arreglo no nombró**. Esa última cláusula es la que hace que la regla
     funcione: sin ella es marcarse la tarea con el examen que uno eligió. El procedimiento y
     sus trampas están en `skills/verificando-por-sabotaje/SKILL.md`.
   - **Remediación que es una decisión, un proceso o una ausencia** (un ADR, que una pasada
     ocurrió, un dato medido): no se finge una mutación. La fila declara qué la sostiene, y
     el ciclo lo cierra **quien lo levantó**; si ya no está, lo cierra **la persona en el
     gate**, nunca un juez nuevo — desde fuera no se distingue una pasada real de un trámite,
     ni si un ADR resuelve la tensión que el otro juez vio o solo una adyacente.

   **Nunca a mano.** Marcar `verificado` sin una de esas dos vías es la forma más barata de
   perder el rastro. Recién entonces se pasa a la Fase 4.
4. **Validación** — la DoD por incremento revisa **cada pieza al construirla**; esta
   fase valida **el conjunto ensamblado**: que todos los `C#` y el set de oro se
   cumplen **a la vez**, integrados, sobre datos reales (end-to-end), sin regresiones.
   Incluye una **pasada del juez sobre el conjunto** (la misma revisión independiente
   de la Fase 3, enfocada al ensamblado, no a cada diff ya juzgado; ver
   `skills/revision-critica/SKILL.md`) y, si el sistema tiene superficie de riesgo, una
   **pasada de seguridad sobre el conjunto** —los defectos de composición no aparecen
   incremento a incremento (`skills/revision-seguridad/SKILL.md`)—.
   Ver `docs/definicion-de-hecho.md`.
   - Si **el conjunto NO cumple lo acordado**, no se sigue: se vuelve atrás según la
     causa. **Defecto / regresión / cobertura faltante** (los requisitos están bien) →
     **Fase 3**, incremento de corrección. **El encuadre estaba mal o falta un
     requisito** (cambian criterios o set de oro) → **Fase 1**, se ajusta
     `docs/contexto.md`, se registra como **ADR**, re-pasa el **revisor funcional** y
     el gate. Una **mejora nueva** más allá de lo acordado **no es falla**: va al
     **backlog** de `docs/plan.md` (y, si se decide perseguirla, abre un nuevo ciclo
     de encuadre). La Fase 4 valida contra lo **acordado**, no contra ideas nuevas.
   → Gate: la persona confirma que el conjunto cumple la Definición de Hecho.
5. **Cierre y aprendizaje** — retrospectiva breve; lecciones a `docs/MEMORIA.md`. **Su
   ligereza es deliberada:** un cierre no debe cargar ceremonial pesado (sería
   contradecir la guarda anti-sobredimensionamiento). No le falta estructura; no la
   necesita.
   → **Handoff:** al confirmar que todos los `C#` quedaron verificados, el agente **se lo
   dice a la persona** ("lo planeado está cumplido") y deja claro que, de aquí en adelante,
   cualquier trabajo nuevo se **clasifica y reentra** (ver *Reentrada*). El cierre dispara
   la reentrada; **no hay que volver a invocar el arranque.**

**Operación / Despliegue (rebanada, cuando aplica).** Todo trabajo que impacte
producción —deploy, migración, config, secretos— es una rebanada del método, nunca
trabajo "aparte": tiene bitácora, ADRs, su propia DoD (runbook verificado contra el
entorno real, réplica local del entorno, pruebas exhaustivas en local **antes** de
tocar producción, plan de reversión escrito, autorización explícita) y **pasada de
juez**. Con servicios o bases de datos reales, los resultados se validan primero en un
**entorno de prueba** con OK de la persona; el plan de despliegue **protege los datos
de producción** (respaldo verificado antes de cualquier operación destructiva). El
procedimiento vive en `skills/desplegando-a-produccion/SKILL.md` (núcleo común + la sección
del modelo de despliegue que el encuadre decidió).
→ Gate: la persona autoriza el impacto a producción de forma explícita y puntual.

### Reentrada — trabajo nuevo después del cierre

El **cierre (Fase 5) dispara la reentrada**: cuando llega trabajo nuevo —en ese momento o
en una sesión futura— **no se re-ejecuta el arranque ni se abre un flujo aparte**; se
reentra en este mismo ciclo y se abre **solo la rebanada que el cambio necesita**. (Lo
pedido **con el plan aún vivo** no es reentrada: va por el bucle de la Fase 3.) Antes de
tocar nada, clasifica el pedido con **una sola pregunta** —el mismo pivote que ya usa la
Fase 4—: **¿cambia la verdad acordada, es decir un `C#` o el set de oro de
`docs/contexto.md`?**

- **No la cambia** (defecto que incumple un `C#` vigente, regresión, cobertura faltante,
  o un ajuste interno/cosmético que el criterio ya permitía) → el requisito ya existe:
  **Fase 3**, incremento de corrección (juez + DoD). No se reabre el encuadre.
- **Sí la cambia** → reentra por el **Encuadre**, con peso proporcional y **solo sobre lo
  afectado** (no se re-ingiere todo ni se rehace el encuadre completo): un **ajuste**
  *edita* un `C#` o un par del set de oro (pesa poco); un **requisito nuevo** *añade* uno
  (pesa lo normal). En ambos: ADR del cambio, revisor funcional sobre lo afectado, gate y
  luego Fase 3.
- **Pregunta/soporte** → respóndela; **mejora opcional** más allá de lo acordado →
  **backlog** de `docs/plan.md` (si se decide perseguirla, se vuelve requisito nuevo).

El insumo del trabajo nuevo aterriza como documento en `material/` (si solo se describe
en el chat, **captúralo como brief corto ahí**). Clasifica **por aspecto, no por ticket**
(la parte rota va a Fase 3; la que cambia un criterio, al Encuadre), y la reentrada que
tocó código **revalida la Fase 4 sobre el conjunto** (sin regresiones). El detalle
operativo está en `docs/arranque.md`.

## 3. Cuándo DETENERTE y preguntar

Antes de hacer cualquiera de estas cosas, **párate y pide aprobación explícita**.
No las generalices: una aprobación es por acción, no permanente.

- Agregar una nueva dependencia o librería.
- Introducir una abstracción nueva (capa, patrón, framework).
- Cambiar la estructura del proyecto o interfaces públicas.
- Cualquier acción destructiva o irreversible (borrar datos, force-push, migraciones).
- Cualquier acción contra **producción**: autorización explícita de la persona **en
  ese momento** (no heredada de una aprobación anterior). Los scripts de despliegue
  exigen confirmación explícita (`--confirm-prod`; ver
  `skills/desplegando-a-produccion/SKILL.md`).
- Cuando el alcance vaya a exceder los criterios de éxito definidos.
- Cuando haya más de una opción razonable: **presenta opciones, no elijas en silencio.**

**Toda propuesta de cambio cita su evidencia:** qué dato de referencia se examinó y si
el efecto es significativo o marginal; sin datos, se declara supuesto y se trata como
tal. Ninguna decisión de **arquitectura o stack** se toma sobre un `[supuesto]` que un
insumo real **existente y accesible** resolvería (incluye pedir conexión/credenciales a
servicios o bases de datos): pide el insumo y detente. Si aún no existe (diseño desde
cero, PoC), acuerda con la persona la entrada/salida esperada —si el sistema tiene
entradas o salidas, como **bosquejo del modelo de datos** diseñado y validado (ver
`docs/arranque.md`, caso 2)— y marca el supuesto con **validación diferida al primer
insumo real**. Un supuesto **técnico** que condiciona un incremento se confirma con un
**experimento mínimo** en `analisis/` antes de construir sobre él: rehacer cuesta más
que el experimento. En contratos de integración, la fuente de verdad es **lo que el
consumidor ejecuta**, no la spec.

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
`docs/decisiones.md` (formato ADR-lite), **con fecha y hora en UTC** tomada del
reloj real (`date -u`), no de memoria. Esto sirve para dos cosas: trazabilidad
y aprendizaje. La misma regla de marca de tiempo aplica a `docs/trazabilidad.md`.

**Hallazgo ≠ decisión.** Un hallazgo (un hecho observado, p. ej. en el muestreo) se
**registra como dato** en `docs/contexto.md`; no es una decisión. Solo cuando hay ≥2
opciones razonables nace una decisión. Y una decisión que **no toca decidir todavía**
no se deja como promesa en prosa: se abre **ya** como ADR en estado `propuesta` con la
actividad donde se resolverá, y el gate de esa actividad la obliga a cerrar
(`aceptada`). Al comunicar a la persona, **etiqueta el estado** (`REGISTRADO` /
`PROPUESTO — pendiente de tu OK` / `PENDIENTE — se decide en <actividad>`).

## 6. Convenciones

El "cómo hacemos las cosas aquí" (estilo, patrones, comandos) vive en
`docs/convenciones.md`. Léelo al inicio de cada sesión.

## 7. Memoria y skills (ciclo de aprendizaje)

- Una lección puntual va a `docs/MEMORIA.md`, en la lista cronológica.
- **Al cerrar el ciclo, la lista se sintetiza.** Treinta lecciones en orden de llegada son
  materia prima: nadie las lee antes de trabajar. El cierre deja una sección **§Lo crítico**
  al principio de `docs/MEMORIA.md` con las pocas que **cambiaron el método**, y cada una
  atada al **mecanismo concreto** que dejó a cambio —un ADR, una regla en
  `docs/convenciones.md`, un chequeo en `check_docs.sh`, una skill—. Una lección sin
  mecanismo se olvida en la siguiente sesión; con mecanismo, no hace falta recordarla.
- Cuando una lección se repite y se vuelve un patrón estable, **promuévela a una
  skill** en `skills/` (un procedimiento reutilizable): una **carpeta** por skill con
  su `SKILL.md` (frontmatter `name` + `description`) y su symlink en `.claude/skills/`.
  Ver `skills/README.md`.

## 8. Reglas que no pueden fallar (enforcement)

Este archivo moldea el comportamiento típico del agente; **no lo garantiza**. Una regla
que no puede permitirse ser "mayormente seguida" se refuerza con un mecanismo **duro**, no
solo con prosa. La plantilla **trae** ese mínimo en `.githooks/` —actívalo una vez con
`git config core.hooksPath .githooks` (parte del Bootstrap del arranque)—:

- **`commit-msg`** exige el trailer de enlace (`Ref:`/`Cierra:`) y que todo `Cierra:`
  nombre un hallazgo **con fila** en `docs/trazabilidad.md`: un `Cierra:` es una afirmación
  sobre otro documento, y las afirmaciones cruzadas se mecanizan o se vuelven prosa.
- **`pre-commit`** bloquea versionar un `.env`/secreto, corre `scripts/check.sh` (lint +
  formato + tests del stack, definido en el diseño): ningún commit con el estilo roto o
  tests en rojo; y corre **`scripts/check_docs.sh`** (integridad del rastro: `C#` sin fila
  de trazabilidad, ADRs referenciados inexistentes, placeholders sin llenar). En el cierre
  (F4/F5) se ejecuta `scripts/check_docs.sh cierre`, con los chequeos completos (hallazgos
  sin cerrar su ciclo, plantilla ADR-000 viva).

**Regla del segundo hallazgo:** cuando un hallazgo de convención **mecanizable** se
repite, no se corrige a mano otra vez: la regla se añade al linter/hook **en ese mismo
incremento** y el juez verifica que quedó cableada.

Lo que **no** es mecanizable —que la revisión independiente (juez / revisor funcional /
juez de seguridad) ocurrió— se vuelve obligatorio por su **artefacto**: cada revisión deja su línea de
cierre en la bitácora de `docs/plan.md` (qué revisó, veredicto y conteo de hallazgos,
**también cuando es PASA limpio**) y sus bloqueantes/vacíos como filas en
`docs/trazabilidad.md`; no se cierra un incremento sin ese rastro ni con hallazgos
`abierto`. El gate humano lo verifica.
