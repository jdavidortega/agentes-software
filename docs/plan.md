# Plan y diseño (vivo)

> Fase 2 — Diseño / plan. Aquí vive la **solución** (el problema está en
> `encuadre.md`). No es estático: nace en el diseño y se ajusta con la evidencia.
> Reúne el diseño, el plan por incrementos, la bitácora y el backlog. Manténlo conciso.

## Enfoque y arquitectura

<!-- El enfoque MÍNIMO que satisface los criterios de éxito. Por qué este y no otro.
Si el proyecto lo amerita, describe aquí la arquitectura: componentes y cómo se
relacionan. OPCIONAL: en proyectos pequeños basta el enfoque + los ADR; no la
inventes si no aporta (anti-sobredimensionamiento). -->
-

## Modelo de datos (entradas/salidas)

<!-- OBLIGATORIO si el sistema produce salida estructurada; si no, no lo inventes
(anti-sobredimensionamiento). El esquema de SALIDA se define ANTES de construir:
campos, tipos y UN ejemplo concreto, coherente con el set de oro de encuadre.md.
Si no hubo insumo real (caso 2 de la ingesta), aquí aterriza el bosquejo diseñado y
validado con la persona. Es un CONTRATO: el revisor funcional lo verifica contra lo
que el consumidor real ejecuta, y cambiarlo después requiere ADR. -->
-

## Incrementos

<!-- Pasos pequeños y revisables, en orden. ID I# con su alias «slug» (aquí vive el
alias de los incrementos); indica qué criterio(s) C# satisface (enlace en
docs/trazabilidad.md). La casilla pasa a [x] al cerrar el incremento, antes de pedir la
revisión final, para que entre en la huella (el commit-msg rechaza `Ref: I#` sin ella). Por sí
sola no significa revisión en PASA, commit aceptado ni gate aprobado: eso lo acreditan el recibo
vigente en docs/revisiones.log, el commit `Ref: I#` y la aprobación de la persona. Con una
revisión en FALLA o una aprobación pendiente, la casilla sigue en [x] y docs/estado.md lo dice en
«Pendiente». -->
- [ ] I1 «…» — _…_ (satisface: C_)
- [ ] I2 «…» — _…_ (satisface: C_)

## Plan de pruebas

<!-- OBLIGATORIO: se decide en el diseño y se ajusta por incremento. Responde "qué
pruebas son necesarias", no "cuántas": ≥1 flujo por criterio C# (por su entrada real, con datos de
forma real) y las demás por grupo, en el nivel donde reside su garantía (unidad, contrato,
integración), con el sabotaje previsto y, al cerrar, el observado; qué pares del set de oro
se automatizan como regresión y cuáles quedan como verificación manual explícita (con su
procedimiento y su límite). La DoD exige exactamente estas; una prueba que no proteja un
criterio o que repita otra sin evidencia adicional es exceso y el juez la señala.
Selección y redundancia: .claude/skills/probando-con-datos-reales/SKILL.md regla 7 -->

| Incremento | Criterio | Flujo por la entrada real (qué entrada, con qué datos) | Otras por garantía (garantía · nivel · sabotaje previsto → observado) | Set de oro automatizado | Manual explícita (procedimiento · límite) |
|------------|----------|----------------------------------------|------------------------------------------------------------------------|-------------------------|-------------------------------------------|
| I_ «…» | C_ | _…_ | _…_ · _unidad/contrato/integración_ · _…_ → _…_ | pares _…_ | pares _…_ |

## Bitácora

<!-- Una línea por avance o ajuste. Lo que cambió respecto al plan y por qué.
Las decisiones con alternativas van a docs/decisiones.md; aquí queda el rastro.
La línea del incremento se escribe ANTES de pedir la revisión y termina con el resultado de
la revisión del README (`README: actualizado | revisado, sin cambios | desfase previo
pendiente`, con su motivo; docs/definicion-de-hecho.md): este archivo forma parte
del contenido que el revisor juzga (arquitectura, contratos, plan de pruebas, bitácora).
Los RECIBOS de las revisiones NO van aquí: van a docs/revisiones.log (una línea
estructurada por pasada, append-only; AGENTS.md §9), que el commit-msg lee y que la
compactación nunca toca. Aquí, como mucho, una referencia ("revisión I3: ver recibo"). El detalle de
hallazgos y su estado vive en docs/trazabilidad.md.
COMPACTACIÓN: al cerrar un incremento, sus líneas se colapsan a UNA (resumen del
incremento) ANTES de pedir la revisión final (este archivo entra en la huella); el
detalle queda en git y los recibos siguen intactos en revisiones.log. El consumo va a
MEMORIA.md §Consumo, no aquí. -->
- [AAAA-MM-DD] _…_

## Fuera de alcance / backlog

<!-- Lo que NO entra ahora pero podría hacerse después, organizado por posible
incremento futuro. Aquí quedan guardadas las mejoras que van surgiendo (incluidas
las sugerencias del juez o del revisor funcional que la persona acoja, y las
reversiones futuras previstas en las Consecuencias de un ADR).
Si la decisión de "hasta dónde cubrir" tuvo alternativas, regístrala además como
ADR en docs/decisiones.md (la lista va aquí; el porqué, allá). -->
- _…_
