# AGENTS.md — Manual de operación del agente

> Este es el archivo canónico de instrucciones para cualquier agente de IA que
> trabaje en este proyecto (Claude Code, Codex, Cursor, etc.). Es la fuente de
> verdad. `CLAUDE.md` solo lo importa; no dupliques contenido aquí en otros
> archivos de herramienta.

## 0. Punto de entrada obligatorio

Antes de cualquier diseño o línea de código, abre y ejecuta el guion de arranque que
corresponde: `docs/arranque.md` si el proyecto nace con el método, o
`docs/arranque-existente.md` si el repositorio ya tiene código que funciona. Es un guion
determinista: conduce a la persona paso a paso, con una condición de salida binaria por
paso y un gate humano entre cada uno. No empieces por otro lado.

Verifica también que **git esté configurado** antes de empezar; si no lo está,
detente y pídelo. Se hace **un commit al cierre de cada fase y de cada incremento**
—no solo en la Fase 3—: el encuadre, el plan, cada incremento, la validación y el
cierre quedan cada uno en su commit. Ningún gate se cruza con cambios sin commitear
(ver `docs/convenciones.md`).

**Reentrada al contexto (proyecto en marcha):** en cada sesión, corre
`sh scripts/check_docs.sh` (rastro íntegro, hooks activos y ejecutables; si FALLA, eso es
lo primero que se arregla), lee `docs/estado.md` (el resumen vivo) y
`docs/convenciones.md`, y abre los demás documentos **solo en la rebanada que la tarea
toca**. No se relee todo el rastro por sesión: el detalle vive
en los documentos por rebanada y la historia, en git. **Al parar** —fin de sesión, gate
pendiente, bloqueo—, regenera `docs/estado.md` con lo **pendiente** escrito en frases
completas (qué falta del incremento y qué se espera de la persona): lo que no queda
escrito al parar se pierde.

## 1. Qué es este proyecto

<!-- Una o dos frases. El detalle vive en docs/encuadre.md -->
- **Proyecto:** _[nombre]_
- **Propósito:** _[qué problema resuelve, en una frase]_
- **Contexto y objetivos completos:** ver `docs/encuadre.md`

## 2. Cómo trabajamos: las 5 fases

El trabajo avanza por fases, con una **compuerta humana** entre cada una. No se
pasa a la siguiente fase sin aprobación explícita de la persona.

**Cómo se cierra una fase:** (a) su trabajo queda en un **commit** (ver §0 y
`docs/convenciones.md`), (b) se pide aprobación de forma **concreta**, y (c) el
`README.md` quedó **verificado contra la realidad del código** (qué hace, cómo se
ejecuta, entradas/salidas) y corregido en ese mismo commit si estaba desfasado —el
agente lo hace por defecto, sin que la persona lo pida; ningún gate se solicita con
el README desactualizado (formato: `.claude/skills/escribiendo-readme/SKILL.md`)—.

**El gate es un resumen ejecutivo en el chat** (≤15 líneas), no un índice de archivos:
(1) qué se decidió, **en texto completo**, no por siglas; (2) el cambio o la arquitectura
en cinco líneas; (3) qué se pide aprobar y qué pasa después; (4) dónde está el detalle.
El resumen representa al documento, no lo sustituye: antes de enviarlo se verifica que
dicen lo mismo. Igual para cualquier decisión que se pida fuera de un gate. Formato y
ejemplo en `docs/convenciones.md` §Redacción.

1. **Encuadre** — contexto, objetivos, criterios de éxito, *no-objetivos*, **set de
   oro** (ejemplos de salida esperada), **stack y arquitectura** y **modelo de
   despliegue** (dos preguntas: **destino** —¿solo local, o también remoto?; el
   despliegue local siempre existe— y **empaquetado** —contenedor recomendado—).
   **Arranca por la ingesta de las entradas, no por el encuadre en
   frío:** `contexto/` es la **única carpeta de entrada** y es **obligatoria** (≥1
   archivo): documentos, datos y artefactos conviven ahí sin que la persona los
   clasifique; el encuadre se **deriva** de ahí y luego se completan los huecos.
   Incluye inventariar las **entradas y salidas del sistema** (todo proceso las tiene)
   y muestrear 1–3 ejemplos reales de cada una (`docs/encuadre.md` §Entradas y salidas). No asumas un stack por defecto:
   pregúntalo. Detalle operativo en `docs/arranque.md`.
   → Antes del gate: **commit del encuadre** (`Ref: F1`).
   → Gate: la persona confirma que el encuadre es correcto.
2. **Diseño / plan** — el enfoque elegido y las decisiones de alcance, en
   `docs/plan.md` (plan vivo + bitácora + backlog). La arquitectura propuesta se
   **socializa antes del gate**: diagrama gerencial sembrado en el `README.md` y
   validado con la persona, iterando hasta su OK
   (`.claude/skills/escribiendo-readme/SKILL.md`). Antes del gate, el encuadre y el
   plan pasan una **revisión funcional independiente** (el agente principal invoca al
   **revisor funcional** como subagente con contexto propio; reporta, no escribe; ver
   `.claude/skills/revision-funcional/SKILL.md`): verifica completitud y consistencia contra la
   fuente (`contexto/`) y no se avanza con vacíos abiertos.
   → Antes del gate: **commit del plan** (`Ref: F2`), con ADRs y trazabilidad inicial.
   → Gate: la persona aprueba el plan antes de escribir código.
3. **Ejecución iterativa** — incrementos pequeños y revisables, no de un golpe. Cada
   incremento: verificación sobre datos reales, **revisión crítica independiente
   antes del commit** (el agente principal invoca al juez como subagente con contexto
   propio; ver `.claude/skills/revision-critica/SKILL.md`) —más la **pasada del juez de
   seguridad** si el incremento toca superficie de riesgo: entrada no confiable,
   authn/authz, secretos, persistencia, IaC/despliegue o IA/LLM (ver
   `.claude/skills/revision-seguridad/SKILL.md`)—, ADR si hubo decisión, commit **enlazado**
   (`Ref:`/`Cierra:`), y trazabilidad al día (`docs/plan.md` + `docs/trazabilidad.md`).
   **Salida de la fase (cuándo termina el bucle):** cuando **todos los criterios `C#`
   están en estado `verificado`** en `docs/trazabilidad.md` y todo hallazgo `R-I#.n`,
   `R-S#.n` (y `R-F4.n`, si la Fase 4 devolvió trabajo) cerró su ciclo completo (ninguno
   `abierto`). **`verificado` nunca se marca a mano.** Regla escalonada: si la remediación
   es **mecanizable**, la fila lleva la mutación exacta que ahora muere y un revisor
   independiente la re-ejecuta en una copia **añadiendo una que el autor no nombró**
   (`.claude/skills/verificando-por-sabotaje/SKILL.md`); si es una **decisión, un proceso o
   una ausencia**, la fila declara qué la sostiene y cierra quien la levantó o la persona
   en el gate, nunca un juez nuevo. Recién entonces se pasa a la Fase 4.
4. **Validación** — la DoD por incremento revisa **cada pieza al construirla**; esta
   fase valida **el conjunto ensamblado**: que todos los `C#` y el set de oro se
   cumplen **a la vez**, integrados, sobre datos reales (end-to-end), sin regresiones.
   Incluye una **pasada del juez de conjunto** (rol juez, agente propio: la rúbrica de
   `.claude/skills/revision-critica/SKILL.md` enfocada al ensamblado —qué invariante deja de
   valer cuando dos piezas corren juntas—, no a cada diff ya juzgado; sus bloqueantes son
   `R-F4.n`, misma tabla y ciclo que los `R-I#.n`, y se corrigen en la Fase 3) y, si el
   sistema tiene superficie de riesgo, una
   **pasada de seguridad sobre el conjunto** —los defectos de composición no aparecen
   incremento a incremento (`.claude/skills/revision-seguridad/SKILL.md`)—.
   Ver `docs/definicion-de-hecho.md`.
   **También por hito** (tres incrementos cerrados o antes de un despliegue): la misma
   pasada sobre **lo ensamblado hasta ahí y sus interacciones**, excluyendo por nombre los
   criterios de incrementos futuros; lo que encuentra vuelve a la Fase 3. La Fase 4 cubre
   todos (`docs/convenciones.md` §Contexto, «Hito»).
   - Si **el conjunto NO cumple lo acordado**, no se sigue: se vuelve atrás según la
     causa. **Defecto / regresión / cobertura faltante** (los requisitos están bien) →
     **Fase 3**, incremento de corrección. **El encuadre estaba mal o falta un
     requisito** (cambian criterios o set de oro) → **Fase 1**, se ajusta
     `docs/encuadre.md`, se registra como **ADR**, re-pasa el **revisor funcional** y
     el gate. Una **mejora nueva** más allá de lo acordado **no es falla**: va al
     **backlog** de `docs/plan.md` (y, si se decide perseguirla, abre un nuevo ciclo
     de encuadre). La Fase 4 valida contra lo **acordado**, no contra ideas nuevas.
   → Gate: la persona confirma que el conjunto cumple la Definición de Hecho.
5. **Cierre y aprendizaje** — retrospectiva breve; lecciones a `docs/MEMORIA.md`. La
   retro incluye la **tabla de consumo de tokens por fase** (de las líneas de
   `docs/MEMORIA.md` §Consumo; formato en `.claude/skills/dirigiendo-revisiones/SKILL.md` paso 8b): es el dato que permite afinar el
   método y detectar sobredimensionamiento. **El aprendizaje no espera al cierre:** las
   lecciones se anotan al cerrar cada incremento, y la síntesis «Lo crítico» de
   `docs/MEMORIA.md` (§7) se rehace en cada hito y al cierre de cada fase, porque un
   cierre que tarda meses no puede ser el único momento en que el método aprende. **Su ligereza es deliberada:** un cierre no debe cargar ceremonial pesado (sería
   contradecir la guarda anti-sobredimensionamiento). No le falta estructura; no la
   necesita.
   → **Handoff:** al confirmar que todos los `C#` quedaron verificados, el agente **se lo
   dice a la persona** ("lo planeado está cumplido") y deja claro que, de aquí en adelante,
   cualquier trabajo nuevo se **clasifica y reentra** (ver *Reentrada*). El cierre dispara
   la reentrada; **no hay que volver a invocar el arranque.**

**Operación / Despliegue (rebanada, cuando aplica).** Todo trabajo que impacte
producción —deploy, migración, config, secretos— es una rebanada del método, nunca
trabajo "aparte": bitácora, ADRs, su propia DoD y **pasada de juez**. **Antes de tocar
producción**, lee `docs/despliegue.md` (el runbook vivo del proyecto; lectura obligatoria también
en toda reentrada que lo toque) y sigue `.claude/skills/desplegando-a-produccion/SKILL.md`
§Núcleo común —réplica local, entorno de prueba con OK de la persona, respaldo verificado,
reversión escrita, `--confirm-prod`— más la sección del modelo de despliegue del encuadre.
→ Gate: la persona autoriza el impacto a producción de forma explícita y puntual.

### Reentrada — trabajo nuevo después del cierre

El **cierre (Fase 5) dispara la reentrada**: el trabajo nuevo no re-ejecuta el arranque; se
abre **solo la rebanada que el cambio necesita** (con el plan aún vivo, lo mismo vía Fase 3).
**Antes de tocar nada**, una sola pregunta: **¿cambia la verdad acordada —un `C#` o el set de
oro de `docs/encuadre.md`?**

- **No** (defecto, regresión, cobertura faltante, ajuste que el criterio ya permitía) →
  **Fase 3**, incremento de corrección. No se reabre el encuadre.
- **Sí** → reentra por el **Encuadre**, solo sobre lo afectado: ADR, revisor funcional
  (recibo `reentrada:C<n>`, o `F2` si cambia más de uno), commit `Ref: F2` y gate; hasta
  entonces el `commit-msg` no cierra trabajo que dependa de ese criterio.
- **Pregunta** → respóndela; **mejora opcional** → backlog de `docs/plan.md`.

**Al reentrar**, abre `docs/arranque.md` §Reentrada: el insumo como brief en `contexto/`, la
clasificación por aspecto (no por ticket) y la revalidación de la Fase 4 si tocó código.


## 3. Cuándo DETENERTE y preguntar

Antes de hacer cualquiera de estas cosas, **párate y pide aprobación explícita**.
No las generalices: una aprobación es por acción, no permanente.

- Agregar una nueva dependencia o librería.
- Introducir una abstracción nueva (capa, patrón, framework).
- Cambiar la estructura del proyecto o interfaces públicas.
- Cualquier acción destructiva o irreversible (borrar datos, force-push, migraciones).
- **Lanzar más de un subagente a la vez**, o una suite/sabotaje/mutation testing mientras
  otra corre: por defecto todo va **en serie** (`docs/convenciones.md` §Recursos). Varios
  agentes en paralelo agotaron la memoria de la máquina en proyectos reales.
- Cualquier acción contra **producción**: autorización explícita de la persona **en
  ese momento** (no heredada de una aprobación anterior). Los scripts de despliegue
  exigen confirmación explícita (`--confirm-prod`; ver
  `.claude/skills/desplegando-a-produccion/SKILL.md`).
- Cuando el alcance vaya a exceder los criterios de éxito definidos.
- Cuando haya más de una opción razonable: **presenta opciones, no elijas en silencio.**

**Toda propuesta de cambio cita su evidencia:** qué dato de referencia se examinó y si
el efecto es significativo o marginal; sin datos, se declara supuesto y se trata como
tal. Ninguna decisión de **arquitectura o stack** se toma sobre un `[supuesto]` que un
insumo real **existente y accesible** resolvería (incluye pedir conexión/credenciales a
servicios o bases de datos): pide el insumo y detente. Si aún no existe (diseño desde
cero), acuerda con la persona la entrada/salida esperada —si el sistema tiene
entradas o salidas, como **bosquejo del modelo de datos** diseñado y validado (ver
`docs/arranque.md`, caso 2)— y marca el supuesto con **validación diferida al primer
insumo real**. Un supuesto **técnico** que condiciona un incremento se confirma con un
**experimento mínimo** en `contexto/exploracion/` antes de construir sobre él: rehacer cuesta más
que el experimento. En contratos de integración, la fuente de verdad es **lo que el
consumidor ejecuta**, no la spec.

**Decisiones de alto impacto** (requisitos, alcance, stack, tecnologías, arquitectura,
despliegue): son tan relevantes como los requisitos. Se **discuten explícitamente y
quedan claras y registradas** (en el encuadre o como ADR) antes de avanzar.

**Proporcionalidad — sé concreto, no hagas mil preguntas:** agrupa lo relacionado y
presenta opciones con tu **recomendación** en una sola pasada. Reserva las preguntas
para lo de alto impacto; lo de bajo impacto y reversible, decídelo con un **default
sensato**, dilo, y sigue.

**Límite de iteraciones.** Tres intentos sobre el mismo problema sin avance
**verificable** (un test que pasa, un dato nuevo, un hallazgo cerrado) → párate, resume
en cinco líneas qué probaste y qué falta, y **pregunta**. Antes de iterar, clasifica:
**relevante** es lo que toca un criterio `C#`, un gate, producción o seguridad;
**irrelevante** es lo cosmético o reversible, que se decide con un default y se anota.
Si no sabes en cuál cae, esa es la pregunta. Iterar mucho sobre lo irrelevante gasta
contexto y degrada lo relevante (`docs/convenciones.md` §Contexto).

## 4. Guardas anti-sobredimensionamiento

Antes de añadir algo, pregúntate:

- ¿Resuelve un problema **presente** o uno **hipotético**?
- ¿Cuál es lo **mínimo** que satisface los criterios de éxito?
- Regla de oro: se introduce cuando se necesita, **no antes**.

Riesgo típico: abstracción prematura y dependencias especulativas.

Lo mismo aplica a la **documentación**: lean en dos ejes. Prefiere ampliar un
archivo a crear uno nuevo, pero no contamines los archivos base (`encuadre.md`,
`convenciones.md`, `AGENTS.md`…) con exceso de detalle. Si un contenido los infla,
un archivo nuevo es lo correcto: propónlo con explicación y pide autorización.

## 5. Registro de decisiones

Toda decisión con más de una opción razonable se documenta en
`docs/decisiones.md` (formato ADR-lite), **con fecha y hora en UTC** tomada del
reloj real (`date -u`), no de memoria. Esto sirve para dos cosas: trazabilidad
y aprendizaje. La misma regla de marca de tiempo aplica a `docs/trazabilidad.md`.

**Hallazgo ≠ decisión.** Un hallazgo (un hecho observado, p. ej. en el muestreo) se
**registra como dato** en `docs/encuadre.md`; no es una decisión. Solo cuando hay ≥2
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
- **En cada hito y al cerrar cada fase, la lista se sintetiza** (no solo al cierre del
  ciclo, que puede tardar meses). Treinta lecciones en orden de llegada son materia
  prima: nadie las lee antes de trabajar. La síntesis deja una sección **§Lo crítico**
  al principio de `docs/MEMORIA.md` con las pocas que **cambiaron el método**, y cada una
  atada al **mecanismo concreto** que dejó a cambio —un ADR, una regla en
  `docs/convenciones.md`, un chequeo en `check_docs.sh`, una skill—. Una lección sin
  mecanismo se olvida en la siguiente sesión; con mecanismo, no hace falta recordarla.
- Cuando una lección se repite y se vuelve un patrón estable, **promuévela a una
  skill** en `.claude/skills/` (su ubicación nativa, donde Claude Code la autodescubre):
  una **carpeta** por skill con su `SKILL.md` (frontmatter `name` + `description`).
  Ver `.claude/skills/README.md`.

## 8. Reglas que no pueden fallar (enforcement)

Este archivo moldea el comportamiento típico del agente; **no lo garantiza**. Una regla
que no puede permitirse ser "mayormente seguida" se refuerza con un mecanismo **duro**, no
solo con prosa. La plantilla **trae** ese mínimo en `.githooks/` —actívalo una vez con
`git config core.hooksPath .githooks` (parte del Bootstrap del arranque)—:

- **`commit-msg`** valida **todos** los trailers contra una gramática cerrada, resuelve cada ID
  contra el índice (casilla `[x]` y `docs/estado.md` en `Ref: I<n>`; fila para todo `Cierra:`) y
  exige el recibo vigente de cada transición. **El código del producto entra solo con
  `Ref: I<n>`** y su recibo. **Ata el trabajo al contrato revisado:** `Ref: I<n>|hito|F4|F5`
  exigen los `C#` y el set de oro del último `Ref: F2`; ningún hallazgo desaparece; entrar a F5
  exige `Ref: F5`, y `Ref: F4|F5` dispara el modo cierre de `check_docs`. Qué exige cada
  trailer: la cabecera del hook; resumen en `docs/convenciones.md` §Git.
- **`pre-commit`** bloquea versionar un `.env`/secreto; **rechaza si hay cambios sin
  stagear en archivos rastreados** (lo que se verifica tiene que ser lo que se versiona);
  corre **`scripts/check_docs.sh`** sobre una exportación del **índice** (contrato por fase:
  archivos obligatorios, `C#`/`I#` únicos y existentes, ADRs referenciados, frontmatter
  válido); y corre `scripts/check.sh` (lint + formato + tests) sobre una instantánea de lo que se commitea, **obligatorio desde la
  Fase 2**: ningún commit con el estilo roto o tests en rojo. Ambos scripts se invocan con
  intérprete explícito; su ausencia es fallo.
- **Al inicio de cada sesión** el agente corre `sh scripts/check_docs.sh`: con ello
  verifica también que los hooks están activos (`core.hooksPath`) y son ejecutables.

**Regla del segundo hallazgo:** cuando un hallazgo de convención **mecanizable** se
repite, no se corrige a mano otra vez: la regla se añade al linter/hook **en ese mismo
incremento** y el juez verifica que quedó cableada.

Lo que **no** es mecanizable —que la revisión independiente ocurrió— se vuelve
obligatorio por su **artefacto** (recibo en `docs/revisiones.log` y filas de trazabilidad,
que el revisor trae listos y el principal registra) y por el control de que el revisor no tocó
el árbol. El detalle es el **protocolo de revisión independiente** (§9). No se cierra un
incremento sin ese rastro ni con hallazgos `abierto`. El gate humano lo verifica.

## 9. Revisión independiente: invariantes

Cuatro roles, rúbrica en su skill (`.claude/skills/revision-*/`), rol en
`.claude/agents/`, procedimiento del principal en
`.claude/skills/dirigiendo-revisiones/SKILL.md`. Lo que no cambia:

- **Quién:** revisor funcional (encuadre y plan; `R-E.n`), juez de código (incremento;
  `R-I#.n`), juez de conjunto (hitos y Fase 4; `R-F4.n`), juez de seguridad (superficie de
  riesgo por incremento, `R-S#.n`; y el conjunto, `R-SF4.n`). Los dispara el principal,
  **uno a la vez**.
- **Contexto fresco:** el revisor no hereda la memoria del principal; recibe qué revisar
  y nada más; reconstruye el estado desde `docs/trazabilidad.md` y `docs/decisiones.md`.
- **Sin edición, sin red, sin ataques a sistemas vivos; verifica, no cree:** ejecuta
  `scripts/check.sh` él mismo y exige evidencia. La herramienta no lo garantiza; lo
  **detecta** el principal con dos huellas (`scripts/huella.sh`): la de **integridad**
  (todo el árbol, registros incluidos) igual antes y después del revisor, y la de
  **vigencia** (lo revisable) igual a la del recibo. Ninguna ve la red ni lo ignorado.
- **El recibo ata el veredicto al contenido:** una línea en `docs/revisiones.log`, append-only
  **mecanizado** (el `pre-commit` exige que lo guardado en HEAD sea prefijo exacto; nunca se
  compacta), leída por un solo parser, `scripts/recibos.sh`, cuya cabecera es la gramática
  canónica (campos, modalidad declarada, evidencia, hito). El `commit-msg` exige el **último**
  recibo válido del alcance en PASA con la huella del índice para `Ref: I<n>`, `F2` (o
  `reentrada:C<n>`), `hito:I<a>-I<b>`, `F4` y `F5` (lo mismo que F4, seguridad incluida);
  rechaza `Ref: I<n>` con hallazgos propios abiertos y el cuarto incremento sin hito.
  **Todo lo revisable se escribe antes del PASA**; después, solo registros. La aprobación
  humana es otra cosa: la da la persona en el gate.
- **Reporte breve y exacto:** veredicto, bloqueantes con fila lista, ≤5 sugerencias,
  preguntas, obstáculos, recibo. Sin narrativa. Lo subjetivo es sugerencia, nunca FALLA
  silenciosa; lo que no sirve a un criterio acordado es sobredimensionar.
