---
name: probando-con-datos-reales
description: "Estrategia de pruebas del proyecto: el camino principal siempre en la suite (servicios externos por fixtures/grabación, nunca vivos ni sustituidos por el camino degradado), ≥1 test de flujo por criterio C# con datos de forma real, tests capaces de fallar (sin asserts triviales), set de oro como regresión, binarios verificados de verdad y mutation testing sobre el camino crítico en la Fase 4. Úsala al decidir en el diseño qué pares del set de oro se automatizan, al escribir las pruebas de cada incremento, y en la validación end-to-end del conjunto."
---
# Skill: Probando con datos reales

> La estrategia de pruebas del proyecto: flujos y datos con forma real, tests que
> aportan (capaces de fallar) y el camino principal siempre cubierto. Complementa
> las reglas base de `docs/convenciones.md` §Pruebas y la DoD; el juez la usa para
> evaluar la dimensión de pruebas.

## Cuándo usarla

- En el **diseño** (Fase 2): al decidir qué pares del set de oro se automatizan y
  cómo se cubre el camino principal.
- En cada **incremento** (Fase 3): al escribir las pruebas de lo nuevo.
- En la **validación** (Fase 4): mutation testing y verificación end-to-end del
  conjunto.

## Reglas

1. **El camino principal siempre está en la suite.** Si el camino real depende de un
   servicio externo (LLM, API de terceros, BD remota), se cubre con
   **fixtures/grabación** de respuestas reales — nunca llamando al servicio vivo
   (lento, frágil, costoso), pero **nunca sustituyéndolo por el camino degradado**.
   La lección: 163 tests verdes validando el camino que casi nunca se ejecuta,
   mientras el principal se validaba a mano.
2. **≥1 test de flujo end-to-end por criterio `C#`**, con datos de **forma real**
   (estructura, nombres, volúmenes y casos límite tomados del muestreo de insumos;
   los fixtures se refrescan si el insumo real cambia).
3. **Cada test debe poder fallar.** Si el comportamiento que protege se rompe y el
   test sigue verde, el test no aporta: prohibido el assert trivial
   (`assert result is not None`), el test que repite la implementación y el que solo
   sube el porcentaje de cobertura.
4. **Set de oro como regresión:** los pares automatizables (decisión del diseño) se
   implementan como tests de regresión; los no automatizables quedan como
   verificación manual **explícita** en la DoD del incremento que los cubre.
5. **Herméticos** (regla base de convenciones): nada depende de `.env` real ni llama
   servicios externos; lo externo se inyecta o se graba.
6. **Binarios y descargas se verifican de verdad:** un archivo generado/servido se
   valida con su herramienta (`unzip -t` para Excel/zip, `%%EOF` para PDF, abrir la
   imagen) — la lección `R-I9.1`: el proxy corrompía binarios y todos los tests
   unitarios estaban verdes.
7. **Mutation testing en la Fase 4 (informativo).** Sobre el código del camino
   crítico, con la herramienta del stack —verifica la vigente en la doc oficial;
   referencia: `mutmut` (Python), Stryker (JS/TS), PIT (Java)—. Los **mutantes
   sobrevivientes en el camino crítico se registran como hallazgos del juez** (test
   decorativo o comportamiento sin proteger). Sin umbral duro de arranque: se
   calibra tras 2–3 proyectos; hoy el reporte informa y el juez decide.

## Pasos

1. **Diseño:** clasifica el set de oro (automatizable / manual), define cómo se
   graba/fixturea el servicio externo del camino principal, y déjalo en el plan.
2. **Por incremento:** escribe primero el test de flujo del criterio que cubre;
   añade unitarios donde el flujo no llega; verifica que cada test falla si rompes
   el comportamiento (rómpelo a propósito una vez).
3. **Fase 4:** corre la suite completa + verificación e2e con insumos y binarios
   reales + mutation testing sobre el camino crítico; entrega el reporte al juez.

## Notas / trampas

- El **porcentaje de cobertura no es la métrica**: cubre comportamiento, no líneas.
  100% de cobertura con asserts triviales protege nada.
- Fixtures que envejecen mienten: si el muestreo de una reentrada muestra que el
  insumo real cambió de forma, los fixtures se actualizan en ese mismo incremento.
- Si un caso del set de oro no se puede automatizar, se dice explícitamente y queda
  como verificación manual **rastreada** — no desaparece en silencio.
- El mutation testing es **lento**: corre en Fase 4 (y en CI nocturno si existe), no
  en el pre-commit.
