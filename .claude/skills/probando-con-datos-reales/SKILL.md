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
   Origen: una suite entera en verde validando el camino degradado mientras el
   principal se validaba a mano.
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
   valida con su herramienta (`unzip -t` para Excel/zip; para PDF, que un lector lo abra
   —`qpdf --check`, `pdfinfo`—: un `%%EOF` al final no prueba que sea válido; abrir la
   imagen). Origen: un proxy corrompía los binarios servidos y todos los tests
   unitarios estaban verdes.
7. **Las necesarias, no más, elegidas por garantía.** El exceso de pruebas también cuesta
   (tiempo de suite, RAM, mantenimiento, ruido al refactorizar). El **plan de pruebas** de
   `docs/plan.md` fija, por incremento, qué pruebas lleva cada criterio y qué del set de oro se
   automatiza; la DoD exige **exactamente esas**. Una prueba fuera del plan que no protege un
   criterio, que repite otra sin evidencia adicional o que no puede fallar es un hallazgo del
   juez (dimensión Pruebas), no mérito. Esta metodología **no es TDD**: el test de flujo va
   primero, pero no se escribe un test por cada línea.
   - **Nivel según dónde reside la garantía:** *unidad* para lógica pura y determinista
     (cálculo, parseo, validación, las filas de la tabla de la regla 9); *contrato* para la forma
     que intercambian dos componentes o un SDK, con un fixture grabado de una respuesta real;
     *integración* cuando la garantía vive en una frontera real (motor de base de datos,
     migración, sistema de archivos, procesos); *flujo* para el camino que recorre el usuario.
     Un contrato acredita el comportamiento frente a su fixture, no la compatibilidad con el
     servicio o SDK real y actual. Una grabación, aunque se refresque, acredita la interacción
     capturada y sus condiciones, no por sí sola la compatibilidad actual completa: si esa
     compatibilidad es la garantía, hace falta evidencia obtenida frente al componente real en
     la versión relevante (fuera de la suite hermética si es un servicio externo, regla 5), y el
     plan dice cuál y cuándo se obtiene.
   - **El piso no se sustituye:** la regla 2 sigue valiendo aunque otro nivel cubra la
     garantía. Las variantes de un criterio no multiplican flujos: bajan al nivel donde residen.
   - **Redundancia:** que dos pruebas detecten el mismo sabotaje es una señal para revisar, no
     motivo suficiente para quitar una. Se comparan la garantía, la frontera, las condiciones y
     los defectos que cada una puede detectar; si aportan evidencia distinta se conservan las dos
     y el plan dice por qué en una línea; la que solo repite a otra se retira.
   - **Sabotaje que sobrevive:** se investiga si la mutación era pertinente (toca la garantía),
     alcanzable (el código mutado corre en la prueba) y observable (su efecto llega a una
     aserción), y si falta una aserción o un caso. Una revisión adicional no convierte ese
     resultado en garantía comprobada. Lo que solo se puede comprobar a mano se declara con su
     procedimiento y su límite.
   - **Plan proporcionado:** por grupo de pruebas, no por aserción: la garantía, el nivel elegido
     y el sabotaje que la mata, *previsto* en el diseño y referenciado como *observado* al cerrar
     el incremento. Las combinaciones van por la regla 9.
8. **Mutation testing en la Fase 4 y por hito (informativo).** Sobre el código del camino
   crítico, con la herramienta del stack —verifica la vigente en la doc oficial;
   referencia: `mutmut` (Python), Stryker (JS/TS), PIT (Java)—. Los **mutantes
   sobrevivientes en el camino crítico se registran como hallazgos del juez** (test
   decorativo o comportamiento sin proteger). Sin umbral duro de arranque: se
   calibra tras 2–3 proyectos; hoy el reporte informa y el juez decide.
9. **La forma del comportamiento, antes de implementar (cuando la tiene).** Si el incremento
   combina estados, fuentes o precedencias, o varios componentes comparten un dato, el plan de
   pruebas lo enumera **antes** de escribir código: una **tabla de decisión** corta (una fila por
   condición o precedencia que cambia el comportamiento, aunque dos filas compartan salida —p. ej.
   dos errores del SDK que terminan en la misma respuesta—; no el producto cartesiano) y,
   entre componentes, un **contrato compartido** (presencia frente a contenido, vacío, nulo, y
   las clases de error que cada dependencia puede lanzar, comprobadas en su SDK). Cada fila tiene
   su prueba o su razón para no tenerla. Un comportamiento simple no la necesita. Origen: hallazgos
   que eran variantes de una misma tabla de estados aparecieron uno por revisión.
10. **Validación proporcional.** La calidad es la condición de aceptación; el tiempo y el costo
    orientan qué evidencia basta, no justifican omitir un control necesario.
    - Primero los casos focalizados de la garantía que cambia; después las comprobaciones que el
      método exige (las de la DoD y las revisiones obligatorias de cada gate, que se conservan) y
      las adicionales que el impacto y el riesgo justifican.
    - La evidencia se reutiliza cuando ningún cambio relevante de código, dependencias,
      configuración, entorno o alcance invalida lo que acredita: se cita con su versión (commit o
      diff) y una frase de por qué sigue siendo aplicable, sin otro inventario.
    - Ampliar o repetir una corrida, o pedir una revisión adicional, se justifica por el impacto,
      el riesgo, un cambio, un fallo o una incertidumbre concreta, y se nombra cuál resuelve.
      «Una corrida» y «un revisor» no son límites ni mínimos generales: su necesidad y su
      repetición dependen de los requisitos aplicables y de la incertidumbre que resuelven.
    - Un hallazgo ajeno al alcance se registra aparte, salvo que contradiga la garantía o revele
      una regresión relevante.

## Pasos

1. **Diseño:** escribe el **plan de pruebas** en `docs/plan.md` (por incremento: flujo
   end-to-end por criterio, las demás pruebas por grupo con su garantía, nivel y sabotaje
   previsto (regla 7), set de oro automatizable / manual con su procedimiento,
   cómo se graba/fixturea el servicio externo del camino principal, y la tabla o el contrato
   de la regla 9 cuando el comportamiento lo requiere).
2. **Por incremento:** escribe primero el test de flujo del criterio que cubre;
   añade las demás en el nivel donde reside su garantía; verifica que cada test falla si rompes
   el comportamiento (el sabotaje previsto, una vez) y anota el resultado observado.
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
