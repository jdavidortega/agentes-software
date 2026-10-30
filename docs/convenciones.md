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
  cuando aún no hay código. Con el primer test, falla de verdad. El `pre-commit` la corre en una
  **instantánea** de lo que se commitea (repositorio git temporal propio): un archivo ignorado o sin
  stagear no la sostiene. Lo que necesite sin versionarse (p. ej. el entorno virtual) se declara
  abajo: carpeta existente e ignorada, sin instalaciones editables que apunten al repositorio.

  | Ruta | Propósito | Cómo se reproduce |
  |------|-----------|-------------------|
- **Plazo de la suite:** 600 s
  Fuente única del plazo de `scripts/check.sh` en todos sus recorridos (directo, `pre-commit`,
  sabotaje); `SUITE_PLAZO` o `--plazo`/`--timeout` lo sobrescriben de forma explícita. 600 s es un
  valor inicial: ajústalo con la duración medida de la suite. Unas tres veces lo habitual orienta,
  no garantiza. Al vencer, la ejecución se termina entera (`scripts/suite.py`, §Recursos).
- **Arranque protegido de `scripts/check.sh`:** sus primeras líneas, tras el `#!/bin/sh`, son este
  bloque, sin cambios. Lo corre siempre bajo `scripts/suite.py` (plazo, una ejecución a la vez,
  grupo de procesos terminado al vencer), también cuando se invoca a mano o desde otra carpeta;
  dentro de la ejecución se salta, y un `check.sh` lanzado desde dentro de otro se rechaza (75).

```sh
# --- suite vigilada: no la quites (docs/convenciones.md §Comandos clave) ---
SUITE_RAIZ=$(cd "$(dirname "$0")/.." && pwd -P)
if [ "${SUITE_ENVUELTO:-}" != 1 ] || [ -z "${SUITE_ID:-}" ]; then
  exec env SUITE_ENVUELTO=1 python3 "$SUITE_RAIZ/scripts/suite.py" correr --dir "$SUITE_RAIZ" \
    ${SUITE_INFORME:+--informe "$SUITE_INFORME"} -- sh "$SUITE_RAIZ/scripts/check.sh" "$@"
fi
unset SUITE_ENVUELTO
# --- fin suite vigilada ---
```

- **`scripts/huella.sh`** — huella de **vigencia** (lo revisable; va en el recibo y el
  `commit-msg` la exige igual a la del índice) e **integridad** (árbol completo; el principal la
  toma antes y después de cada revisor). Qué excluye y sus modos: cabecera del script.
- **`scripts/check_docs.sh`** — integridad del rastro documental. El agente lo corre **a mano al
  inicio de cada sesión** (verifica también que los hooks están activos y son ejecutables); el
  `pre-commit` y el `commit-msg` (modo `cierre` con `Ref: F4|F5`) lo corren solos.

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

**El cierre (de fase, de incremento o un gate) es un resumen ejecutivo** (≤15 líneas,
`AGENTS.md` §2), con esta forma; las actualizaciones intermedias no la usan:
**Estado:** terminado técnicamente; pendiente de tu aprobación. **Resultado:** qué se consiguió
y lo decidido con su enunciado («C3 «exportar-excel»: el reporte mensual se exporta a Excel con
las columnas de la vista»); un ejemplo si ayuda. **Verificación:** qué pasó y qué no se comprobó.
**README y rama:** el resultado de la revisión del README; integración recomendada, mantener o ya
incorporado. **Pendiente:** decisiones y trabajo restante, por separado. **Siguiente paso:** la
acción concreta recomendada. **Acción tuya:** la pregunta exacta («¿Apruebas I3 «exportar-excel»
y empiezo I4?»). **Detalle:** dónde está (`docs/plan.md` §Incrementos, ADR «Exportar con openpyxl»).

Todo mensaje que no es un cierre dice en qué caso está: **en curso** («Sigo trabajando; no
necesitas responder»), **bloqueado** («Necesito X para continuar con Y») o **finalizado** («Lo
acordado está terminado. No queda trabajo activo ni decisiones pendientes»). Con una
autorización previa para continuar, se dice y se sigue sin pedir otra; fusionar, publicar y
desplegar conservan la suya. Nada de "ya terminé, ¿seguimos?".

**Una decisión** se plantea con problema, opciones, recomendación y consecuencia, y un ejemplo
cuando aclara la diferencia: «Recomiendo mantener esta rama hasta probar la facturación: el
cálculo ya pasa, pero aún no comprobamos que la factura use el importe correcto» dice más que
«pendiente validación de integración».

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
  en frases completas. Es lo único que se escribe fuera de los momentos fijos. Regenerar
  es comprobar cada afirmación contra su fuente, retirar lo cerrado y conservar lo pendiente
  vigente aunque sea de una fase anterior (reglas en la cabecera de `docs/estado.md`).
- **Hito:** tres incrementos cerrados desde el último hito, o antes de un despliegue. Es un
  commit `Ref: hito:I<a>-I<b>` con recibo del juez de conjunto (y de seguridad si la requiere);
  el `commit-msg` rechaza el cuarto incremento sin él. En cada hito: pasada del juez de conjunto
  sobre lo ensamblado, síntesis de `docs/MEMORIA.md` §Lo crítico y mutation testing informativo si
  hay camino crítico. **Al pedir o registrar el recibo del hito**, la gramática de `cubre=`,
  `excluye=`, `componentes=` y del rango está en la cabecera de `scripts/recibos.sh` §HITO.
  **Si el hito exige corregir código**, se reabre un incremento del rango: ruta en
  `.claude/skills/dirigiendo-revisiones/SKILL.md` §Notas.
- **Plan:** un incremento es `- [ ] I<n> «alias» — …` (o `- [x]`); la casilla pasa a `[x]` al
  cerrar **cada** incremento (el `commit-msg` lo exige) y al cierre ningún `- [ ]` queda fuera del
  backlog. Gramática completa (comentarios, cercos, formas rechazadas): `scripts/check_docs.sh`,
  «Lector ÚNICO del plan».
- **Momentos de compactación (fijos, no a criterio):** al cierre de **cada incremento**
  (la bitácora del incremento se colapsa a una línea y su casilla pasa a `[x]` **antes** de
  pedir la revisión final,
  porque `plan.md` entra en la huella; tras el PASA solo se tocan registros: `estado.md`
  regenerado, hallazgos `verificado` al Histórico de `docs/trazabilidad.md`, consumo y
  lecciones en `MEMORIA.md`), al cierre de **cada
  fase** (mismo barrido sobre lo que la fase dejó) y al cierre del **ciclo** (F5:
  `estado.md` queda en modo reentrada — criterios verificados, backlog vivo, nada "en
  curso"). Nada se pierde: el detalle queda en git y el porqué, en los ADR.
- **Qué preserva un buen resumen:** decisiones, estado, supuestos abiertos y próximo
  paso. **Qué descarta:** el detalle de ejecución (vive en git) y lo que ya no informa
  la fase actual. Compactar no es truncar: es reescribir corto sin perder lo que decide.
- **Señal de poda adicional:** un documento vivo con más de ~2 páginas de contenido
  operativo se compacta en el siguiente cierre, sin esperar la fase.
- **Consumo por rebanada:** al cierre de cada incremento y de cada fase, una línea en
  `docs/MEMORIA.md` §Consumo con `python3 scripts/consumo.py` (formato, fuente, cobertura y qué
  hacer si falla: `dirigiendo-revisiones` paso 8b). La retro de F5 la evalúa: detecta
  sobredimensionamiento. Solo se comparan cifras de la misma fuente y el mismo campo.
- **Presupuesto de escritura (la ventana de contexto es finita y la calidad cae antes
  de llenarla):** todo lo que el agente escribe lo volverá a leer él mismo, muchas veces,
  en sesiones futuras. Topes que se respetan salvo razón escrita: reporte de revisión
  ≤40 líneas (sin narrativa; bloqueantes aparte); recibo = 1 línea; bitácora del
  incremento = 1 línea; resumen ejecutivo del gate ≤15 líneas; ADR ≤20 líneas; `estado.md`
  ≤1 página; `MEMORIA.md` §Lo crítico ≤10 ítems; `AGENTS.md` ≤24 KB (`check_docs` lo
  vigila: Codex limita las instrucciones combinadas a 32 KiB). Un documento que crece se
  compacta en el siguiente cierre; si una regla necesita más espacio, va a una skill que
  se carga solo cuando aplica, no al canon que se lee siempre.
- **Lo que no decide no se escribe:** ni justificaciones largas, ni historia repetida, ni
  listas de lo que no se hizo. El porqué va en el ADR (una vez); el detalle, en git.
- **Recibos aparte y para siempre:** `docs/revisiones.log` es append-only (el
  `pre-commit` exige que lo ya guardado en HEAD sea prefijo exacto de lo nuevo) y no
  entra en ninguna compactación; es lo que el `commit-msg` lee. Un FALLA no se borra: la
  revisión nueva se añade debajo. Reparar un registro corrupto es una excepción con
  `--no-verify` y su lección escrita en `MEMORIA.md`.
- **Obstáculos de una revisión → `docs/MEMORIA.md` §Operativa**, no a este archivo en
  ese momento: `convenciones.md` es contenido revisado y cambiarlo tras el PASA
  invalidaría el recibo; su promoción aquí va en el siguiente incremento.
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
- **Sin `assume-unchanged` ni `skip-worktree`:** esos flags hacen que git dé por idéntico
  un archivo que cambió; la huella y los hooks se calcularían sobre contenido viejo. El
  `pre-commit`, `huella.sh` y el doctor los rechazan; si aparecen, `git update-index
  --no-assume-unchanged / --no-skip-worktree <archivo>`.
- **Ramas:** en un proyecto nuevo, trunk-based: rama principal, commits pequeños y enlazados; una
  rama solo si la persona la pide. En uno existente se identifica y respeta su estrategia real
  (inventario de `adoptar.sh inspeccionar`, `docs/arranque-existente.md` paso A). Al cerrar cada
  incremento se dice una de tres: integración recomendada ahora (destino y motivo), mantener la
  rama (qué falta) o ya incorporado (referencia). Fusionar, publicar y borrar ramas tienen su propia
  autorización; la antigüedad sola no justifica borrar. Con **remoto compartido**, CI mínimo (se decide en el diseño): los hooks locales se
  esquivan con `--no-verify`, el CI no. **Al montar el CI**: la política de rango de commits está en la
  cabecera de `.github/workflows/metodo.yml` y los comandos, en sus pasos (`steps`); en otro CI se
  copian ambos. Un merge limpio no lleva trailer; lo que se añade al fusionar es contenido nuevo
  (cabecera del `commit-msg`, texto «MERGE LIMPIO»). Las guardas de contenido son una sola, `scripts/guardas.sh`.
- **Base del método (solo proyectos adoptados, `docs/arranque-existente.md`):** el Paso 0
  añade aquí una línea `- **Base del método:** <sha>` con el **último commit previo a la
  adopción**. `validar_historial.sh` resta lo alcanzable desde ahí: el historial anterior no
  se juzga y el commit de instalación sí. Una sola declaración; duplicada, malformada, ajena
  a la historia o movida a un commit con fase, falla. Sin ella, el replay es el de siempre.
- **Contrato revisado y límites del modelo de cierre:** la *verdad acordada* son las líneas
  `- C<n>:` y la sección «Set de oro» de `docs/encuadre.md` tal como quedaron en el **último
  commit `Ref: F2`** (en un proyecto adoptado, posterior a la «Base del método»). Todo commit de
  trabajo dependiente (`Ref: I<n>`, `Ref: hito`, `Ref: F4`, `Ref: F5`) exige ese contrato
  **idéntico**; `Ref: F1` edita el encuadre libremente (borrador, reencuadre, Fase 1 de una
  adopción) y `Ref: F2` fija el nuevo con recibo del revisor funcional (alcance `F2`, o
  `reentrada:C<n>` si solo cambió ese criterio o el set de oro). La fase de `estado.md` sigue
  siendo un resumen vivo, no una máquina de estados, con una excepción: **entrar a F5 exige
  `Ref: F5`**. Varios commits `Ref: I3` cuentan como **un** incremento cerrado (una corrección
  reabre el mismo `I#`, un alcance nuevo exige otro). La aprobación humana vive en el chat.
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
- **Enlaza** cada commit en el footer con la gramática cerrada de la cabecera del
  `commit-msg`: `Ref: F1|F2|F4|F5`, `Ref: I<n>`, `Ref: hito:I<a>-I<b>`, `Cierra: R-<ID>` (familias
  de IDs: `docs/trazabilidad.md` §IDs). **Transiciones:** ningún hallazgo con fila o entrada del
  Histórico en HEAD desaparece, y una fila que pasa a `resuelto` o `verificado` lleva en «Resuelto»
  una referencia que **resuelve** (ruta `archivo:línea` del índice o commit del historial); que
  **demuestre** la resolución lo juzga el revisor. **El código del producto** —todo lo que no es
  rastro, plantilla ni configuración: lista `SIN_REVISION` del `commit-msg`— entra solo con
  `Ref: I<n>` y recibo del juez; ampliar esa lista es un ADR.

## Revisores y sandbox

- **Por defecto:** filtro preventivo de revisores (`.claude/hooks/guarda-revisor.py`) y
  modalidades de escritura según `.claude/skills/dirigiendo-revisiones/SKILL.md`. No es frontera.
- **Sandbox de Bash** (opcional, por proyecto; ADR): la única restricción efectiva de escritura
  y red para los comandos de shell, en toda la sesión. **Antes de activarlo o de declararlo en
  un informe**: alcance, configuración y cómo verificarlo en `dirigiendo-revisiones` §Modalidades.

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
