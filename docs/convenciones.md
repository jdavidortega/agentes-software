# Convenciones

> El "cómo hacemos las cosas aquí". El agente lo lee al inicio de cada sesión.
> Manténlo corto y específico. "Usa indentación de 2 espacios" > "formatea bien".

## Stack y herramientas
<!-- Lenguajes, frameworks, gestor de paquetes (¿npm/pnpm/uv?), versiones.
La DECISIÓN de stack y arquitectura se toma en el encuadre (docs/contexto.md);
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
  `pre-commit`. Es **salida obligatoria del diseño**; hasta que exista, el hook solo avisa.
  Debe **tolerar la suite de tests vacía** (p. ej. `pytest` sale con código 5 sin tests;
  `jest` necesita `--passWithNoTests`): si no, bloquea los commits del arranque (`Ref: F2`)
  cuando aún no hay código. Con el primer test, falla de verdad.
- **`scripts/check_docs.sh`** — integridad del rastro documental (viene con la
  plantilla; también lo corre el `pre-commit`). Al cierre de F4/F5 se ejecuta con
  chequeos completos: `scripts/check_docs.sh cierre`.

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
documentos de cara a terceros (README, ADRs, `contexto.md`) se escriben para un lector
**externo al proyecto**. Concreto > elegante.

## Contexto por sesión y compactación

- **Lectura por sesión:** `docs/estado.md` + este archivo + la rebanada que la tarea
  toca. No se releen los 6 documentos vivos por sesión.
- **Dato en un solo lugar:** cifras, umbrales y conteos viven en un documento canónico;
  el resto **referencia** (`ID «alias»`), no copia. Sin copias no existe la clase de
  errores de "propagación documental".
- **Señal de poda:** un documento vivo con más de ~2 páginas de contenido operativo se
  compacta al cierre del incremento (ver la DoD): bitácora de incrementos cerrados a
  una línea, hallazgos `verificado` al Histórico de `docs/trazabilidad.md`,
  `docs/estado.md` regenerado. Nada se pierde: el detalle completo queda en git y el
  porqué, en los ADR.

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
<!-- Llénalo al inicio. Casi todos los "funciona en mi máquina" salen de aquí. -->
- **Modelo de despliegue:** _[se decide en el encuadre — ver la sección «Modelo de
  despliegue» de `contexto.md`: contenedor (Docker/compose), host directo,
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
  `commit-msg` exige el trailer de enlace, `pre-commit` bloquea `.env`/secretos y corre
  `scripts/check.sh` + `scripts/check_docs.sh`).
- **Trunk-based:** se trabaja sobre la rama principal, con commits pequeños y
  enlazados; una rama solo si la persona la pide (experimento, cambio grande), no por
  defecto. Con **remoto compartido**, `scripts/check.sh` se cablea además en un **CI
  mínimo** (se decide en el diseño): los hooks locales se pueden esquivar
  (`--no-verify`); el CI no.
- **Commit al cierre de CADA fase, no solo en los incrementos de código.** El error
  típico es no commitear nada hasta el primer incremento de la Fase 3 y dejar las
  Fases 1–2 sin guardar. Concretamente, hay al menos un commit:
  - al aprobar el **encuadre** (Fase 1 → `docs/contexto.md` y la ingesta sembrada);
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
  Fase 3), `Cierra: R-I3.1` (hallazgo del juez) o `Cierra: R-E.1` (vacío del revisor
  funcional, si su resolución amerita commit propio). Es la trazabilidad en el
  historial (ver `docs/trazabilidad.md`).

## Pruebas
- **Herméticas:** sin dependencia de `.env` real ni de servicios externos; inyectar
  o mockear. Un test cuyo resultado cambia por un `.env` es frágil.
- **El camino principal siempre en la suite** y estrategia completa en
  `skills/probando-con-datos-reales.md` (flujos reales, tests que aportan, mutation
  testing en Fase 4).

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
