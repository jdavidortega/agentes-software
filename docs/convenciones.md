# Convenciones

> El "cómo hacemos las cosas aquí". El agente lo lee al inicio de cada sesión.
> Manténlo corto y específico. "Usa indentación de 2 espacios" > "formatea bien".

## Stack y herramientas
<!-- Lenguajes, frameworks, gestor de paquetes (¿npm/pnpm/uv?), versiones.
La DECISIÓN de stack y arquitectura se toma en el encuadre (docs/encuadre.md);
aquí va el detalle operativo (comandos, versiones exactas). No la dupliques. -->
-

> **Verifica la documentación oficial y vigente** de cada dependencia antes de fijar
> sus comandos o su API. El conocimiento del modelo puede estar desactualizado (p. ej.
> el comando de arranque de un framework cambió y la doc oficial ya no usa el viejo).
> Ante la duda, consulta la doc, no la memoria.

## Comandos clave
<!-- Cómo se construye, se prueba, se ejecuta. El agente debe usar ESTOS.
Verificados contra la doc oficial actual de cada herramienta. -->
- Instalar:
- Probar:
- Ejecutar:
- **Aplicar y verificar un cambio** (reload / restart / rebuild, según el modelo de
  despliegue — p. ej. recrear el contenedor). Hazlo explícito: muchas confusiones de
  "no veo el cambio" son por no reiniciar/reconstruir el proceso.
- Lint / formato:
- **`scripts/check.sh`** — agrega lint + formato + tests en un solo comando; lo ejecuta el
  `pre-commit`. Es **salida obligatoria del diseño**: desde que `docs/estado.md` declara
  F2 o posterior, su ausencia **bloquea** el commit (antes, solo avisa). Un solo worker o
  un máximo fijo y timeouts (§Recursos). Debe **tolerar la suite de tests vacía** (p. ej. `pytest` sale con código 5 sin tests;
  `jest` necesita `--passWithNoTests`): si no, bloquea los commits del arranque (`Ref: F2`)
  cuando aún no hay código. Con el primer test, falla de verdad.
- **`scripts/check_docs.sh`** — integridad del rastro documental (viene con la
  plantilla). El `pre-commit` lo corre sobre la exportación del índice; el `commit-msg`
  corre el modo `cierre` cuando el trailer es `Ref: F4|F5`; y el agente lo corre **a mano
  al inicio de cada sesión** (`sh scripts/check_docs.sh`), que es cuando también verifica
  que los hooks están activos y son ejecutables.

## Identificadores y alias

- Todo `C#`, `I#` y hallazgo (`R-…`) nace con un **alias**: slug de 2–4 palabras
  (`C3 «exportar-excel»`, `I5 «motor-indicadores»`, `R-I9.1 «proxy-trunca-binarios»`).
  El agente lo propone al crearlo (y pregunta si hay duda).
- El alias vive en **un solo lugar**: la columna Alias de `docs/trazabilidad.md` para
  `C#` y hallazgos; junto al incremento en `docs/plan.md` para los `I#`. Desde ahí se
  **referencia**; no se copia su descripción a otros documentos.
- Se cita siempre `ID «alias»` juntos — así referirse a algo no obliga a releer
  documentos. Los ADR usan su título, que ya cumple ese rol.

## Redacción

Aplica a todo lo que el agente redacta (documentos y chat): frases directas y en voz
activa, sin relleno ni adornos; una sigla se define la primera vez que aparece; los
documentos de cara a terceros (README, ADRs, `encuadre.md`) se escriben para un lector
**externo al proyecto**. Concreto > elegante.

**Concreto también en los IDs.** `C3 «exportar-excel»`, `I5 «motor-indicadores»` o
`R-I3.1` sirven para **referenciar entre documentos** y compactar contexto; **no** son
una forma de hablar con la persona ni de redactar una decisión. Cuando un ID aparece
en el chat, en un gate, en un ADR o en un reporte de revisión, va **con su enunciado
completo** la primera vez ("C3 «exportar-excel»: el reporte mensual se exporta a Excel
con las columnas de la vista") y las siguientes al menos con el alias. Un documento o un
mensaje que solo cita siglas se vuelve ilegible cuando el proyecto crece; el seguimiento
de un requerimiento tiene que poder hacerse leyendo, no descifrando.

## Contexto por sesión y compactación

- **Lectura por sesión:** `docs/estado.md` + este archivo + la rebanada que la tarea
  toca. No se releen los 6 documentos vivos por sesión.
- **Dato en un solo lugar:** cifras, umbrales y conteos viven en un documento canónico;
  el resto **referencia** (`ID «alias»`), no copia. Sin copias no existe la clase de
  errores de "propagación documental".
- **`estado.md` en cada parada:** además de los cierres, se regenera al terminar una
  sesión, al dejar un gate pendiente o al quedar bloqueado, con la sección «Pendiente»
  en frases completas. Es lo único que se escribe fuera de los momentos fijos.
- **Hito:** tres incrementos cerrados desde el último hito, o el momento previo a un
  despliegue. En cada hito: pasada del juez de conjunto sobre lo ensamblado, síntesis
  de `docs/MEMORIA.md` §Lo crítico, mutation testing informativo si hay camino crítico.
- **Momentos de compactación (fijos, no a criterio):** al cierre de **cada incremento**
  (ver la DoD: `docs/estado.md` regenerado, bitácora del incremento a una línea,
  hallazgos `verificado` al Histórico de `docs/trazabilidad.md`), al cierre de **cada
  fase** (mismo barrido sobre lo que la fase dejó) y al cierre del **ciclo** (F5:
  `estado.md` queda en modo reentrada — criterios verificados, backlog vivo, nada "en
  curso"). Nada se pierde: el detalle queda en git y el porqué, en los ADR.
- **Qué preserva un buen resumen:** decisiones, estado, supuestos abiertos y próximo
  paso. **Qué descarta:** el detalle de ejecución (vive en git) y lo que ya no informa
  la fase actual. Compactar no es truncar: es reescribir corto sin perder lo que decide.
- **Señal de poda adicional:** un documento vivo con más de ~2 páginas de contenido
  operativo se compacta en el siguiente cierre, sin esperar la fase.
- **Consumo por rebanada (no invasivo: una línea):** al cierre de cada incremento y de
  cada fase, corre `python3 scripts/consumo.py` (acumulado por modelo desde los
  transcripts locales) y registra **una línea** en la bitácora de `docs/plan.md`:
  `Consumo I5 «alias»: +X entrada / +Y salida (acum X'/Y')` — el delta se calcula contra
  la línea anterior. La retro de F5 arma la tabla por fase y la **evalúa**: es el dato
  que detecta sobredimensionamiento del método, no ceremonia. Si el script falla
  (formato interno cambió), regístralo con `/usage` y anota el hallazgo.
- **Lecturas masivas y barridos → subagente de búsqueda:** inventarios, lecturas de
  archivos grandes o barridos exploratorios se delegan a un subagente con contexto
  propio (p. ej. el agente Explore integrado) y el principal consume **solo las
  conclusiones**: el contexto del principal es el recurso más caro del método.

## Recursos de la máquina (RAM, CPU)

Lección aprendida a precio completo: varios agentes o sabotajes a la vez **tumbaron la
máquina**. Las reglas son duras, no preferencias:

- **Un subagente a la vez por defecto.** Los revisores (funcional, juez de código, juez de
  conjunto, seguridad) corren **en serie**; lanzar dos o más en paralelo es una acción
  que requiere aprobación explícita de la persona (`AGENTS.md` §3) y solo tiene sentido
  si ninguno ejecuta la suite.
- **Una suite a la vez.** Nunca coinciden: la suite del `pre-commit`, un sabotaje
  (`sabotear.py`), mutation testing, o un revisor ejecutando `scripts/check.sh`. El que
  llega espera a que termine el que corre.
- **`scripts/check.sh` acotado:** tests con **un solo worker** o un máximo fijo
  (`pytest -p no:xdist` o `-n 1`; `jest --maxWorkers=2`; `go test -p 1`; `cargo test -j 1`;
  `mvn -T 1`…), **timeout** por test y por suite, y debe respetar `SABOTAJE_SERIE=1`
  (lo exporta el arnés): con esa variable, un solo worker siempre. Nada de `watch`.
- **Mutation testing** solo en la Fase 4 y por hito, con la máquina libre; nunca en el
  `pre-commit` ni en paralelo con otra cosa.
- **Copias del árbol** (sabotaje) sin dependencias ni builds (`node_modules`, `.venv`,
  `dist`, `target`…) y con tope de tamaño (`--max-mb`); si el proyecto necesita las
  dependencias dentro de la copia, se declara en el plan de pruebas con su costo.
- **Antes de un trabajo pesado** (suite completa, mutation testing, varios subagentes),
  el agente mira la memoria disponible y, si está justa, lo dice y degrada (en serie,
  menos workers) en lugar de lanzar y esperar.

## Estilo de código
<!-- El estándar NO se debate por proyecto: se usa la convención de nombres IDIOMÁTICA del
lenguaje elegido (p. ej. camelCase en Java/TS, snake_case en Python/Rust) de forma
CONSISTENTE, más prácticas clean (nombres con significado, funciones cortas y cohesionadas,
sin duplicación ni código muerto). Esto es BASE en todo proyecto, no una decisión de
diseño. El formatter/linter del stack lo aplica automáticamente. -->
- Nombres y estilo: los **idiomáticos del lenguaje**, aplicados por el formatter (ver «Lint / formato»).
- **Idioma del código: inglés.** Identificadores **y** comentarios/docstrings en inglés
  ASCII (sin acentos ni ñ). El texto **de cara al usuario** va en el idioma del producto y
  **externalizado** (no quemado en el código).
- **Comentarios y docstrings: concretos y con propósito.** Se comenta el **porqué** o una
  restricción que el código no puede mostrar, no el *qué* línea a línea; nada de código
  muerto comentado ni comentarios que repiten el nombre de la función. Las interfaces
  públicas se documentan según `docs/definicion-de-hecho.md` (completo pero conciso).
- Estructura de carpetas / imports:
- Desviaciones del estándar idiomático (solo con razón documentada):

**Toolchain idiomático por stack** (referencia; verifica versiones en la doc oficial vigente):

| Stack | Formatter + linter | Naming |
|-------|--------------------|--------|
| Java | google-java-format + Checkstyle | camelCase métodos, PascalCase clases |
| TS/JS | Prettier + ESLint | camelCase |
| Python | Ruff (o Black) + isort | snake_case (PEP 8) |
| Go | gofmt + golangci-lint | MixedCaps |
| Rust | rustfmt + clippy | snake_case |
| C# | dotnet format | PascalCase métodos |

El elegido se cablea en `scripts/check.sh` y el `pre-commit`.

## Patrones que SÍ usamos
-

## Patrones que NO usamos
<!-- Anti-patrones explícitos. Igual de útil que lo anterior. -->
-

## Entorno y paridad dev ↔ producción
<!-- Llénalo al inicio. Casi todos los "funciona en mi máquina" salen de aquí. Aquí van
las REGLAS de paridad; el runbook (dónde está cada cosa, cómo desplegar, verificar y
revertir) vive en docs/despliegue.md. -->
- **Modelo de despliegue:** _[se decide en el encuadre — ver la sección «Modelo de
  despliegue» de `encuadre.md`: contenedor (Docker/compose), host directo,
  serverless…]_. Condiciona rutas, montajes y el bucle de cambios.
- **Config anclada a un punto fijo, nunca al `cwd`** (datos, `.env`, índices/bases
  locales): toda ruta relativa al directorio de trabajo es un **bug latente**; ánclala
  a la raíz del proyecto o a una ruta de entorno explícita. En contenedor, anclar a
  rutas internas del contenedor.
- Rutas de insumos/salidas (dev vs prod):
- Nombres de archivos/insumos (dev vs prod):
- Comando de arranque (dev vs prod): el del stack elegido (su `dev` / `start` / `run`).

## Configuración por capas
<!-- No mezclar lo que el operador edita con lo que no debe tocar. -->
- **Despliegue/host:** rutas y montajes del entorno (p. ej. volúmenes del contenedor).
- **Constantes internas del runtime:** lo que el operador NO debe tocar; no lo
  expongas en el archivo que el operador edita.
- **Secretos/ajustes de la app:** vía `.env`.
- Regla: una variable que el operador no debe cambiar **no vive donde el operador
  edita**. Distingue siempre "ruta del host" de "ruta interna".

## Variables de entorno y secretos
- **Solo si el proyecto maneja secretos o config de entorno.** Si no los hay, **no se crea
  `.env` ni `.env.example`** (no van por defecto); se introducen cuando se necesitan.
- **Nada de variables, rutas ni secretos quemados en el código:** cuando existan, van a `.env`.
- `.env` **no se versiona** (está en `.gitignore`). Lo que se versiona, si aplica, es
  `.env.example`: la lista de variables **sin valores reales**.
- **Acota las variables:** suelen sobrar; **valida con el desarrollador** cuáles son
  realmente necesarias. No metas variables "por si acaso".
- En pasos futuros del desarrollo, si surge una propuesta de **nueva variable o
  secreto**, **consúltala antes** de añadirla (no la introduzcas en silencio).
- Secretos **solo por entorno**, nunca en el repo ni en el chat. Si uno se expone
  (aunque sea en una conversación), **rótalo**.

## Marcas de tiempo
<!-- Una sola regla, para que decisiones y trazabilidad sean auditables. -->
- Toda fecha/hora que se escriba en `docs/decisiones.md` y `docs/trazabilidad.md`
  (decisiones, cierres de vacíos, resolución de hallazgos) va en **UTC**, formato
  `AAAA-MM-DD HH:MM`.
- **Tómala del reloj real** (`date -u`), nunca de memoria: el modelo no conoce la hora.

## Git
<!-- Disciplina mínima de control de versiones. -->
- Git **configurado desde el inicio** del proyecto, **con los hooks de la plantilla
  activos**: `git config core.hooksPath .githooks` (versionados en `.githooks/`;
  `commit-msg` exige el trailer de enlace —y que todo `Cierra:` nombre un hallazgo
  con fila en `docs/trazabilidad.md`—, `pre-commit` bloquea `.env`/secretos y corre
  `scripts/check.sh` + `scripts/check_docs.sh`).
- **Trunk-based:** se trabaja sobre la rama principal, con commits pequeños y
  enlazados; una rama solo si la persona la pide (experimento, cambio grande), no por
  defecto. Con **remoto compartido**, `scripts/check.sh` se cablea además en un **CI
  mínimo** (se decide en el diseño): los hooks locales se pueden esquivar
  (`--no-verify`); el CI no.
- **Commit al cierre de CADA fase, no solo en los incrementos de código.** El error
  típico es no commitear nada hasta el primer incremento de la Fase 3 y dejar las
  Fases 1–2 sin guardar. Concretamente, hay al menos un commit:
  - al aprobar el **encuadre** (Fase 1 → `docs/encuadre.md` y la ingesta sembrada);
  - al aprobar el **plan** (Fase 2 → `docs/plan.md`, ADRs, trazabilidad inicial);
  - en **cada incremento** de la Fase 3 (no de un golpe al final);
  - al cerrar la **validación** (Fase 4) y el **cierre/aprendizaje** (Fase 5).
- Regla operativa: **ningún gate se cruza con cambios sin commitear**. Antes de pedir
  aprobación, el trabajo de esa fase ya está en un commit.
- Mensaje concreto y suficiente: qué cambió y por qué (no "varios cambios"). **Asunto
  con alias** cuando resuelve un ID: `I5 «motor-indicadores»: qué cambió y por qué`.
  Con el trailer, `git log --oneline` queda como índice legible y
  `git log --grep="Cierra: R-I9.1"` recupera cualquier cierre puntual. Git es
  **archivo**, no contexto de trabajo: la operación diaria no lo relee.
- **Enlaza** cada commit a lo que resuelve, en el footer: `Ref: F#` (cierre de fase:
  `F1` encuadre, `F2` plan, `F4` validación, `F5` cierre), `Ref: I3` (incremento de la
  Fase 3), `Cierra: R-I3.1` (hallazgo del juez), `Cierra: R-S3.1` (seguridad),
  `Cierra: R-F4.1` (juez de conjunto) o `Cierra: R-E.1` (vacío del revisor funcional,
  si su resolución amerita commit propio). Es la trazabilidad en el
  historial (ver `docs/trazabilidad.md`).

## Pruebas
- **Herméticas:** sin dependencia de `.env` real ni de servicios externos; inyectar
  o mockear. Un test cuyo resultado cambia por un `.env` es frágil.
- **El camino principal siempre en la suite** y estrategia completa en
  `.claude/skills/probando-con-datos-reales/SKILL.md` (flujos reales, tests que aportan, mutation
  testing en Fase 4).
- **Cada garantía nueva se sabotea antes de cerrar el incremento:** se deshace a propósito
  en una **copia** del árbol y se comprueba que la suite se pone en rojo (procedimiento y
  arnés: `.claude/skills/verificando-por-sabotaje/SKILL.md`). Una garantía que ninguna prueba puede
  romper es un comentario. En una copia, no en el árbol de trabajo: con revisiones en
  paralelo, una mutación sin commitear pone la suite en rojo para todos.

## Robustez operativa
- **Usable, no solo presente:** un chequeo de salud valida que el recurso *sirve*
  (archivo legible, esquema correcto), no solo que existe. Un `disponible: true` que
  no distingue ambos miente. Expón banderas observables (conteos, "se usó X") para
  diagnosticar sin leer logs.
- **Estado derivado:** al corregir un insumo, regenera explícitamente sus artefactos
  derivados (cachés, índices, volúmenes persistentes); no se actualizan solos.
- **Archivos generados acotados:** logs y otros archivos que el sistema crea no deben
  crecer indefinidamente. Define rotación/retención o un tope. Si no hay un servidor
  de logs externo donde consultarlos, el límite local es obligatorio.
