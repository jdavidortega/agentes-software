---
name: revision-critica
description: "Rúbrica del juez/revisor independiente de código: verifica un incremento (o el conjunto ensamblado) contra la Definición de Hecho, los criterios C# y el set de oro, ejecuta scripts/check.sh por sí mismo, exige evidencia de la verificación con datos reales y emite veredicto PASA/FALLA con bloqueantes R-I#.n. Úsala al cerrar cada incremento de la Fase 3 —antes del commit y del gate humano— y en la pasada sobre el conjunto de la Fase 4. Reporta; no construye ni edita el código."
allowed-tools: Read, Grep, Glob, Bash
---
# Skill: Revisión crítica (agente juez)

> Rúbrica del **juez de código** (incrementos) y del **juez de conjunto** (hitos y Fase 4).
> Cómo se dispara, con qué contexto, qué puede hacer, el formato exacto del reporte y
> cómo se registra: **protocolo de revisión independiente, `AGENTS.md` §9**. Aquí vive
> solo la rúbrica.

## Cuándo usarla

- Al cerrar **cada incremento** de la Fase 3, **antes del commit** y antes del gate
  humano.
- En la **Fase 4 (Validación)**: una pasada sobre el **conjunto ensamblado** —los `C#`
  y el set de oro cumpliéndose a la vez, end-to-end—. Obligatoria pero enfocada al
  ensamblado: no re-revisa cada diff ya juzgado.

## Prompt de invocación (para el agente principal)

Lanza al subagente con este encargo **tal cual** —neutro: sin resumirle tu solución ni
adelantarle conclusiones; su valor está en que no hereda tu framing—, rellenando solo
el incremento y el rango del diff:

> Actúa como juez de código según `.claude/skills/revision-critica/SKILL.md`: léelo y aplica su
> rúbrica completa. Revisa el incremento `I#` (diff: `git diff <rango>`) —o, si el alcance es
> un **hito** (`hito:I<a>-I<b>`: solo lo construido hasta ahí y sus interacciones, excluyendo
> por nombre los criterios futuros) o el **conjunto** (`F4`), el ensamblado completo— contra
> `docs/encuadre.md`, `docs/plan.md`, `docs/convenciones.md`,
> `docs/definicion-de-hecho.md` (lista A) y los hallazgos previos en `docs/trazabilidad.md`.
> Sigue el protocolo de `AGENTS.md` §9: ejecuta `scripts/check.sh` tú mismo, exige
> evidencia de la verificación con datos reales, y entrega el reporte con su formato
> exacto (Veredicto · Bloqueantes `R-I#.n` —`R-F4.n` si revisas el conjunto— con filas
> listas · Sugerencias · Preguntas · Obstáculos · Recibo para `docs/revisiones.log` con
> `seguridad=requerida|no-aplica` y tu `sh scripts/huella.sh`). No escribas en
> ningún archivo ni uses la red: todo va en el reporte.

## Insumos (el contexto en que se apoya)

- Archivos del proyecto: `docs/encuadre.md` (problema + set de oro + criterios `C#`),
  `docs/plan.md` (diseño/arquitectura), `docs/trazabilidad.md` (hallazgos previos y
  estado), `docs/decisiones.md`, `docs/convenciones.md` y `docs/definicion-de-hecho.md`.
- **El diff del incremento** (lo que cambió) y sus pruebas.
- No hereda la memoria de trabajo del constructor: solo archivos + diff.

## Pasos

1. Lee los insumos. Si falta contexto o hay ambigüedad, **pregunta** (no asumas).
2. **Verifica, no creas:** ejecuta tú mismo `scripts/check.sh` (lint + formato + tests)
   en lugar de aceptar que "pasan"; para lo no mecanizable (verificación con datos
   reales, set de oro) exige la evidencia —el comando y su salida, o el par
   `entrada → salida` observado— o reprodúcela.
3. Evalúa por dimensiones, una a una (rúbrica abajo). Cada dimensión: **PASA/FALLA**
   si es binaria; **observación** si es de criterio.
4. Entrega el reporte en el **formato del protocolo** (`AGENTS.md` §9). Los bloqueantes
   llevan ID `R-I<incr>.<n>` (incremento) o `R-F4.<n>` (conjunto) y el criterio `C#` que
   protegen; cada uno es una subtarea accionable. El principal registra, resuelve y el
   paso a `verificado` sigue la regla escalonada de `AGENTS.md` §2. Si un bloqueante es una
   instancia de una **familia** (la misma omisión en otros estados, campos, dependencias o
   rutas), dilo («familia: …») y nombra las instancias que viste; si la familia ya aparece en
   `docs/trazabilidad.md`, es una corrección incompleta, no un hallazgo nuevo aislado.
5. **Repasada** (tras un FALLA): revisa el cambio desde el recibo anterior y sus efectos, corre
   la suite completa y comprueba las filas de interacción del plan de pruebas; no re-revises lo
   ya juzgado sin cambios. Acotar no es ignorar: un defecto relevante que encuentres al
   comprobar se reporta. Si el alcance exige ejecutar mutaciones, eso pide modalidad
   experimentos; en lectura, dilo como pendiente.

## Rúbrica (dimensiones)

- **Definición de Hecho:** corre la **lista A** de `docs/definicion-de-hecho.md` punto por
  punto (binario). La lista B (commit, compactación, gate) es del principal, después.
- **Consistencia de arquitectura:** el cambio respeta el enfoque/arquitectura de
  `plan.md`; no introduce dependencias ni abstracciones sin ADR; el **lenguaje/stack es el
  de `encuadre.md`** (no se coló otro por inercia).
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
- **Pruebas:** las del **plan de pruebas** del incremento (`docs/plan.md`), ni menos ni
  más: ≥1 flujo end-to-end por criterio cubierto con datos de forma real, unitarios solo
  donde el flujo no llega, herméticos, y cada uno capaz de fallar. **El exceso es
  hallazgo:** una prueba que no protege un criterio, que duplica otra o que no puede
  fallar (assert trivial, repite la implementación) se reporta igual que una faltante.
  No exige 100% mecánico: cobertura de **comportamiento**.
- **Funcionales:** cumple criterios de éxito y set de oro de `encuadre.md`.
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

- **Recibo de un hito:** lleva `cubre=`, `excluye=` y `componentes=`. **Al escribirlo**, su
  gramática (qué criterio va en cada lista, partición del encuadre, rango) está en la cabecera de
  `scripts/recibos.sh` §HITO.
- **En el conjunto (hito / Fase 4)** la pregunta central es de composición: ¿qué
  invariante de un módulo deja de valer cuando otro falla o cuando ambos corren juntos?
  Orden de efectos, encadenamientos transitivos, simetrías a medio cubrir: no se
  re-revisa cada diff ya juzgado.
- **No infles:** una sugerencia que no sirve a un criterio acordado es gold-plating.
- Se afina con el tiempo: si una verificación se repite, súmala a la rúbrica.
