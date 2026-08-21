---
name: revision-critica
description: "Rúbrica del juez/revisor independiente de código: verifica un incremento (o el conjunto ensamblado) contra la Definición de Hecho, los criterios C# y el set de oro, ejecuta scripts/check.sh por sí mismo, exige evidencia de la verificación con datos reales y emite veredicto PASA/FALLA con bloqueantes R-I#.n. Úsala al cerrar cada incremento de la Fase 3 —antes del commit y del gate humano— y en la pasada sobre el conjunto de la Fase 4. Reporta; no construye ni edita el código."
allowed-tools: Read, Grep, Glob, Bash
---
# Skill: Revisión crítica (agente juez)

> Rol de **juez/revisor independiente**. Verifica de forma crítica cada incremento
> antes del commit y del gate humano, y el conjunto ensamblado en la Fase 4.
> **No construye ni edita el código: reporta.**
> Idealmente se ejecuta como agente con **contexto propio** (un subagente en Claude
> Code; una pasada de revisión aparte en otra herramienta), para no heredar las
> racionalizaciones de quien escribió el código —ahí está su valor.

## Cuándo usarla

- Al cerrar **cada incremento** de la Fase 3, **antes del commit** y antes del gate
  humano.
- En la **Fase 4 (Validación)**: una pasada sobre el **conjunto ensamblado** —los `C#`
  y el set de oro cumpliéndose a la vez, end-to-end—. Obligatoria pero enfocada al
  ensamblado: no re-revisa cada diff ya juzgado.

## Quién la dispara y su memoria

- La **dispara el agente principal** (orquestador): al llegar al cierre del
  incremento, invoca al juez (un **subagente** con contexto propio) y le pasa qué
  revisar, apuntándolo a los archivos y al diff. El skill es la rúbrica; el subagente
  es quien la ejecuta; el principal es quien lo lanza.
- Cada revisión arranca con **contexto fresco** (a propósito: así el juez no se ancla
  ni arrastra aprobaciones previas). **No** se "resume" el subagente.
- La continuidad entre fases **no viene de la memoria, viene de los archivos.** El
  juez reconstruye el historial leyendo `docs/trazabilidad.md` (hallazgos previos y su
  estado) y `docs/decisiones.md`, y **verifica que los hallazgos `abierto` previos
  estén `resuelto`** antes de dar PASA.

## Prompt de invocación (para el agente principal)

Lanza al subagente con este encargo **tal cual** —neutro: sin resumirle tu solución ni
adelantarle conclusiones; su valor está en que no hereda tu framing—, rellenando solo
el incremento y el rango del diff:

> Actúa como juez de código según `.claude/skills/revision-critica/SKILL.md`: léelo y aplica su
> rúbrica completa. Revisa el incremento `I#` (diff: `git diff <rango>`) contra
> `docs/contexto.md`, `docs/plan.md`, `docs/convenciones.md`,
> `docs/definicion-de-hecho.md` y los hallazgos previos en `docs/trazabilidad.md`.
> Ejecuta `scripts/check.sh` tú mismo y exige evidencia de la verificación con datos
> reales. Entrega tu reporte EXACTAMENTE con estas secciones: **Veredicto**
> (PASA/FALLA) · **Bloqueantes** `R-I#.n` (cada uno con su fila lista para
> `docs/trazabilidad.md`) · **Sugerencias** · **Preguntas** · **Obstáculos**
> (problemas de entorno o setup, comandos que necesitaron flags especiales,
> workarounds; «ninguno» si no hubo) · **Línea de bitácora** lista. No escribas en
> ningún archivo: todo va en el reporte.

## Insumos (el contexto en que se apoya)

- Archivos del proyecto: `docs/contexto.md` (problema + set de oro + criterios `C#`),
  `docs/plan.md` (diseño/arquitectura), `docs/trazabilidad.md` (hallazgos previos y
  estado), `docs/decisiones.md`, `docs/convenciones.md` y `docs/definicion-de-hecho.md`.
- **El diff del incremento** (lo que cambió) y sus pruebas.
- No hereda la memoria de trabajo del constructor: solo archivos + diff.

## Pasos

1. Lee los insumos. Si falta contexto o hay ambigüedad, **pregunta** (no asumas).
2. **Verifica, no creas:** ejecuta tú mismo `scripts/check.sh` (lint + formato + tests)
   en lugar de aceptar que "pasan"; para lo no mecanizable (verificación con datos
   reales, set de oro) exige la evidencia —el comando y su salida, o el par
   `entrada → salida` observado— o reprodúcela. Una afirmación sin evidencia no
   cuenta para PASA.
3. Evalúa por dimensiones, una a una (rúbrica abajo). Cada dimensión: **PASA/FALLA**
   si es binaria; **observación** si es de criterio.
4. Entrega el veredicto en este formato:
   - **Veredicto:** PASA / FALLA (FALLA si alguna dimensión binaria falla).
   - **Bloqueantes** (binarios): lista; asigna a cada uno un ID `R-I<incr>.<n>` y el
     criterio `C#` que protege; cada uno es una subtarea accionable.
   - **Sugerencias** (criterio, no bloquean): lista breve (aviso al gate, no se
     rastrean como hallazgos; las que la persona acoja van al backlog de `docs/plan.md`).
   - **Preguntas / dudas:** lo que no pudo verificar.
   - **Obstáculos:** problemas de setup o entorno, comandos que necesitaron flags o
     configuración especial, workarounds descubiertos (p. ej. para correr `check.sh` o
     reproducir la evidencia). Si no se reportan, el principal los redescubre a su
     costo. «Ninguno» si no hubo.
5. **Incluye en el reporte las filas listas** para `docs/trazabilidad.md` (ID,
   incremento, criterio, estado `abierto`) y la línea de cierre para la bitácora de
   `docs/plan.md` (revisión I#, veredicto, conteo, "ver trazabilidad"), **también
   cuando el veredicto es PASA sin hallazgos**: esa línea es el rastro exigible de que
   la revisión ocurrió. **El principal las registra tal cual, sin editarlas** —el juez
   no escribe en el repo (dos revisiones en paralelo ya no pueden pisarse el rastro)—
   y **antes** de la siguiente pasada: la memoria entre fases sigue viniendo de los
   archivos. Los obstáculos los rutea el principal: comando/flag →
   `docs/convenciones.md`; lección → `docs/MEMORIA.md`.
6. El agente principal resuelve los bloqueantes como subtareas; al cerrarlos actualiza
   su estado a `resuelto (fecha + commit)` en `docs/trazabilidad.md`, enlaza el commit
   (`Cierra: R-I#.n`) y, si la remediación es mecanizable, deja en la fila **la
   mutación que ahora muere**. El paso a `verificado` sigue la regla escalonada de
   `AGENTS.md` §2 (revisor independiente que re-ejecuta la mutación en una copia y
   añade una no nombrada; ver `.claude/skills/verificando-por-sabotaje/SKILL.md`).
   Solo con todo en PASA: commit final del incremento + gate humano.

## Rúbrica (dimensiones)

- **Definición de Hecho:** corre `docs/definicion-de-hecho.md` punto por punto (binario).
- **Consistencia de arquitectura:** el cambio respeta el enfoque/arquitectura de
  `plan.md`; no introduce dependencias ni abstracciones sin ADR; el **lenguaje/stack es el
  de `contexto.md`** (no se coló otro por inercia).
- **Estilo, clean y concisión:** **lint y formatter pasan** (`scripts/check.sh`) —base
  determinista—; **nombres idiomáticos y consistentes**, **código en inglés ASCII**
  (identificadores y comentarios, sin acentos), funciones cortas y cohesionadas, sin
  duplicación, sin código muerto ni "por si acaso"; hace lo mínimo que resuelve el problema
  (anti-exceso). El juez reserva su criterio para lo que el linter no ve (cohesión, nombres
  con significado, comentarios que aportan —el porqué— y no narran el qué, calidad de
  los tests).
- **Manejo de errores:** los errores se manejan de forma **explícita**; no se silencian
  excepciones (nada de `catch` vacío ni tragar errores), los fallos se propagan o se
  registran con contexto.
- **Documentación:** interfaces públicas documentadas, completa pero concisa (ver DoD).
- **Pruebas:** cada funcionalidad (o apoyo a funcionalidad) tiene una prueba que la
  respalda; tests herméticos. No exige 100% mecánico: cobertura de **comportamiento**.
- **Funcionales:** cumple criterios de éxito y set de oro de `contexto.md`.
- **Seguridad (binario, es un gancho — no la auditoría):** ¿el diff toca superficie de
  riesgo (entrada no confiable, authn/authz, secretos, persistencia, IaC/despliegue,
  superficie de IA/LLM)? Si **sí**, la **pasada del juez de seguridad**
  (`.claude/skills/revision-seguridad/SKILL.md`) es requisito para PASA, y sus hallazgos
  `R-S#.n` deben estar cerrados. Si **no**, hazlo constar ("sin superficie de riesgo").
  Tú no la auditas: verificas que ocurrió.
- **No funcionales:** solo los acordados en el encuadre (rendimiento, observabilidad…);
  no inventes NFR que nadie pidió. **La seguridad no entra aquí:** no es un NFR
  opcional, tiene su propia dimensión arriba.

## Notas / trampas

- **No edita el código ni aprueba el commit.** Reporta; deciden el agente principal y
  la persona (evita el "juez y parte").
- **Binario donde se pueda;** lo subjetivo va como sugerencia o pregunta, nunca como
  FALLA silenciosa.
- **No infles:** una sugerencia que no sirve a un criterio acordado es gold-plating.
- Si la herramienta lo permite, usar para el juez un **modelo distinto** al que
  construyó diversifica puntos ciegos (opcional, no requisito).
- Se afina con el tiempo: si una verificación se repite, súmala a la rúbrica.
