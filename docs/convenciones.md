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
  F2 o posterior, su ausencia **bloquea** el commit (antes, solo avisa). Desde el primer `Ref: F2`,
  cambiar su cuerpo (qué pruebas, lint y comparador corren) es código: `Ref: I<n>` con recibo. Un solo worker o
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
  Desde que `check.sh` existe, en cualquier fase (también en el Paso 0 de una adopción y en F1),
  `check_docs.sh` lo exige **al principio** (antes solo shebang, comentarios o blancos), **idéntico** a
  esta definición, que es la única canónica. Compara los dos archivos como bytes y rechaza NUL y CR en
  cualquiera de ellos; si el bloque falta, difiere o tiene delimitadores duplicados, falla sin ejecutarlo.
  Eso rechaza un bloque alterado respecto a esta referencia local; no autentica este archivo ni
  `suite.py`. Después lo
  **prueba aislado**: en un proyecto temporal con una copia de `suite.py` y un `check.sh` ficticio (el
  bloque + un eco del identificador), con registro propio, sin las `SUITE_*` heredadas y con un límite
  propio de 60 s; comprueba que corre vigilado y que una llamada anidada se rechaza. El cuerpo real de
  `check.sh` nunca se ejecuta en esa prueba.

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

**El cierre (de fase, de incremento o un gate) es un resumen ejecutivo** (`AGENTS.md` §2) y se
escribe copiando esta plantilla, que es su única definición; las actualizaciones intermedias no
la usan:

```text
**Estado:** <terminado técnicamente; pendiente de tu aprobación — o bloqueado: qué falta>
**Resultado:** <qué se consiguió y lo decidido con su enunciado>
**Verificación:** <qué pasó y qué no se comprobó>
**README y rama:** <resultado de la revisión del README; rama: integrar, mantener o ya incorporada>
**Pendiente:** <decisiones y trabajo restante, por separado>
**Siguiente paso:** <la acción concreta recomendada>
**Acción tuya:** <la pregunta exacta>
**Detalle:** <dónde está>
```

En el gate de cierre (F4/F5) de un **cierre del ciclo** (recibo con `excluye=`), «Resultado» dice «cierre del ciclo,
no del producto»: los criterios de `cubre=` como vigentes y cada excluido como pendiente con su motivo, nunca como
garantía; el estado global es el de `docs/estado.md` §Criterios.

Los ocho campos van siempre, en este orden; uno sin contenido lleva «—» o «no aplica». **≤15
líneas lógicas** (separadas por saltos de línea; el ancho de pantalla no cuenta), y cada campo en
una o dos frases: un párrafo largo dentro de un campo incumple la brevedad aunque cumpla el
contador. «Resultado» dice qué se consiguió y qué se pide aprobar; el inventario y los
antecedentes van al Detalle. Las preguntas de datos y las decisiones pendientes que el gate
necesite van después, en bloques propios. Ejemplo de enunciado: «C3 «exportar-excel»: el reporte mensual se exporta a Excel
con las columnas de la vista»; de acción: «¿Apruebas I3 «exportar-excel» y empiezo I4?»; de
detalle: «`docs/plan.md` §Incrementos, ADR «Exportar con openpyxl»».

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

### Hechos pendientes

Rige en el arranque, en la adopción y en la reentrada; es la única definición. Un **hecho pendiente**
es un dato que ninguna fuente accesible sostiene (el repositorio, `contexto/`, la conversación o una
comprobación al alcance del agente) y que solo la persona, operación o un tercero pueden dar. No se
rellena con `[inferido]` ni `[supuesto]` para no preguntarlo, y esta regla no relaja la de las
inferencias: todo `[inferido]` se confirma con la persona antes del gate.

- **Preguntar no lo resuelve.** Un hecho preguntado y todavía sin respuesta sigue abierto; si la
  siguiente decisión lo necesita, esa decisión no se toma hasta tenerlo. «No lo sé» es una respuesta
  válida y lo deja diferido.
- **Diferido, con tres datos:** quién lo confirma; cuándo se resuelve; qué decisión o trabajo bloquea.
  En el arranque se escribe `[FALTA · diferido: quién; cuándo; qué bloquea]` y en la adopción
  `[pendiente: quién; cuándo; qué bloquea]`: son la misma marca en dos notaciones, y un hecho lleva
  solo una.
- **Cruza un gate solo si se cumplen las cuatro condiciones:** figura en el campo «Pendiente» del gate;
  la siguiente decisión no necesita resolverlo; ningún trabajo que dependa de él se construye antes de
  resolverlo; y ninguna garantía declarada verificada depende de él. Si falla una, el gate no se pide con
  él abierto: se pregunta y se espera, o la decisión, el trabajo o la garantía que dependen de él quedan
  fuera del gate, dicho explícitamente.
- **Hecho ≠ elección.** Un hecho pendiente no es un ADR; solo una elección entre opciones lo es
  (`propuesta`, con la actividad donde se resuelve).

**Pendiente de seguridad física** (un dato del que depende que el sistema actúe o no sobre equipos,
personas o el mundo real: configuración desplegada, a qué alcanza un mando, si un automatismo está
encendido) lleva cuatro partes: **qué** falta confirmar y **quién** puede hacerlo; **qué decisión**
queda bloqueada hasta conocerlo; **cuándo** debe resolverse (p. ej. «antes del gate de la Fase 2»); y
**qué medida provisional** se propone, **quién la autoriza** y **cómo se comprueba**. Una medida
provisional es **candidata**: se dice si es suficiente o qué otros caminos persisten. **Al vencer sin
resolverse**, la decisión bloqueada **no se toma** en ese gate: la persona puede aprobar el resto, pero el
gate dice explícitamente qué decisión queda fuera, y `docs/estado.md` distingue la **revisión documental
aprobada** del **gate pendiente** de esa decisión; el pendiente sigue con un nuevo «cuándo». El cierre
documental de una fase **no autoriza** operar, desplegar ni declarar seguro el sistema, y un documento
del proyecto (README) no acredita la configuración desplegada. Cambiar producción nunca ocurre sin la autorización puntual de la persona (`AGENTS.md` §3).

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
  revisión nueva se añade debajo. Un registro corrupto se recupera según «Replay, remoto y CI»
  (§Git, recuperación), con su lección en `MEMORIA.md`.
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
- **Ejecuciones vigiladas y carpetas propias** (`scripts/suite.py`): toda corrida de la suite queda
  registrada en `<git common dir>/suite-runs`. Una ejecución que no se pudo cerrar de forma comprobada
  (abierta, incompleta, no comprobable) **bloquea** la siguiente hasta resolverse: `python3
  scripts/suite.py estado --abiertas` la explica y `terminar <id>` la cierra cuando su pertenencia es
  demostrable. Las carpetas temporales donde corre la suite (la instantánea del `pre-commit`, la copia
  del sabotaje) se **reclaman** recién creadas; si hay que conservarlas, `suite.py` las **recupera
  sola** (al empezar la siguiente ejecución, o con `recuperar`) cuando su dueño y sus lanzadores
  terminaron, ninguna ejecución sigue abierta en ellas y siguen siendo la misma carpeta. Lo que no
  puede resolver con certeza lo conserva y lo explica en `estado`; nada se borra por su nombre.
  `check_docs.sh` avisa al inicio de sesión de lo que siga abierto o conservado.
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
  `scripts/check.sh` + `scripts/check_docs.sh`, y `pre-merge-commit` lo ejecuta en un merge que
  termina solo). Un fast-forward no ejecuta hooks, y un `cherry-pick` o un `rebase` no ejecutan los del
  método: el replay comprueba después el contrato de esos commits, pero no ejecuta `check.sh` sobre ellos.
- **Sin `assume-unchanged` ni `skip-worktree`:** esos flags hacen que git dé por idéntico
  un archivo que cambió; la huella y los hooks se calcularían sobre contenido viejo. El
  `pre-commit`, `huella.sh` y el doctor los rechazan; si aparecen, `git update-index
  --no-assume-unchanged / --no-skip-worktree <archivo>`.
- **Ramas:** en un proyecto nuevo, trunk-based: rama principal, commits pequeños y enlazados; una
  rama solo si la persona la pide. En uno existente se identifica y respeta su estrategia real
  (inventario de `adoptar.sh inspeccionar`, `docs/arranque-existente.md` paso A). Al cerrar cada
  incremento se dice una de tres: integración recomendada ahora (destino y motivo), mantener la
  rama (qué falta) o ya incorporado (referencia). Fusionar, publicar y borrar ramas tienen su propia
  autorización; la antigüedad sola no justifica borrar.
- **Replay, remoto y CI (regla principal).** Los hooks son locales: `--no-verify` o unos hooks desactivados los esquivan. El
  *replay* (`scripts/pruebas/validar_historial.sh`) vuelve a validar los commits ya hechos, y puede detectar esos
  incumplimientos cuando se ejecuta sobre el rango completo que corresponde. Esta regla exige ejecutarlo como procedimiento:
  no impide mecánicamente omitirlo ni autentica sus validadores.
  - **Replay anclado en cada gate.** Desde el primer incremento, cada gate de incremento, hito, F4 y F5 ejecuta el replay
    anclado y dice en «Verificación»: ancla, rango, commit final evaluado (SHA completo) y resultado. FALLA o «sin veredicto»
    bloquean el gate.
    - **Ancla:** el commit final aprobado en el gate anterior, con el SHA completo que consta en su «Verificación». Sus
      validadores juzgan el rango; los del checkout no, así que el candidato no puede debilitar las reglas que lo juzgan. No se
      toma `origin/main` ni otra referencia en su lugar.
    - **Rango:** `<ancla>..<final>`. El inicio puede ser anterior al ancla, nunca posterior. `HEAD` se resuelve a un SHA completo
      al empezar. El rango no se elige para dejar fuera un commit que falla. En un proyecto adoptado, el script excluye por sí
      mismo lo anterior a la «Base del método».
    - **Orden de entrada.** Se escribe tal cual, sustituyendo el ancla. Hasta extraer el ancla solo intervienen `git` y la shell;
      del checkout no se ejecuta nada:

      ```sh
      ancla=<SHA completo del commit aprobado en el gate anterior>
      inicio=$ancla
      fin=HEAD
      if ! printf '%s\n' "$ancla" | grep -Eqx '[0-9a-f]{40}([0-9a-f]{24})?' || [ "$(git cat-file -t "$ancla" 2>/dev/null)" != commit ]; then
        echo "Ancla inválida: debe ser el SHA completo de un commit aprobado en un gate." >&2; false
      elif ! git cat-file -e "${ancla}:scripts/pruebas/replay_anclado.sh" 2>/dev/null; then
        echo "El ancla no contiene scripts/pruebas/replay_anclado.sh: no uses la copia del candidato ni otra ancla; sigue «Primera ancla» (docs/convenciones.md §Git)." >&2; false
      else
        d=$(mktemp -d "${TMPDIR:-/tmp}/replay-anclado.XXXXXX") &&
        git cat-file blob "${ancla}:scripts/pruebas/replay_anclado.sh" > "$d/entrada.sh" &&
        sh "$d/entrada.sh" "$ancla" "$inicio" "$fin" "$d"
      fi
      ```

      Las llaves de `${ancla}:` son necesarias: en zsh, `$ancla:s…` se leería como un modificador.
    - **Validadores modificados en el rango.** El informe los lista. Pasar con el contrato del ancla no acredita las reglas
      nuevas: su comportamiento se prueba aparte, con los casos de la regresión del método, y rigen desde que el gate que las
      acepta deja su commit como ancla. Lo que dependa de ellas se juzga con esa ancla nueva.
    - **Primera ancla.** Si el ancla no contiene `scripts/pruebas/replay_anclado.sh` (primera adopción o transición desde una
      versión anterior del método), la orden se detiene y no se sustituye por otra ancla ni por la copia del candidato. En ese
      gate:
      1. los validadores se comparan por blob con los de la entrega de la plantilla de la que vienen (`git rev-parse
         <commit>:<ruta>`), o la adaptación local se presenta con su diff;
      2. se ejecuta el replay sin ancla (`sh scripts/pruebas/validar_historial.sh <rango>`), declarando que juzga con los
         validadores del checkout;
      3. se cita la evidencia de la plantilla para esa entrega.

      Al aprobarse, su «Verificación» dice «Ancla de validación: `<sha>` (primera)».
    - **Historia reescrita.** Si el ancla no es antecesora del final (force-push, rebase o una rama que no sale de ella), el
      replay se detiene sin veredicto y da la base común solo como dato. No se elige otra ancla por cuenta propia: la persona
      revisa el rango desde esa base y decide la nueva ancla en un gate.
    - **Límites.** La raíz de confianza es el SHA aprobado, más `git`, la configuración local y el entorno de la máquina: no
      protege frente a quien los controla. La CI (`metodo.yml`) sigue ejecutando el workflow y los validadores del checkout,
      así que el replay anclado no da garantía remota.
  - **El replay no es la suite.** Valida el contrato de los commits (trailers, recibos, guardas, doctor por commit) y no corre las
    pruebas del producto, que se informan aparte (`check.sh`).
    - Con fallos previos **declarados y comprobados** según `docs/arranque-existente.md` §G, `check.sh` pasa, pero
      `CHECK_ESTRICTO=1`, que es como lo corre la CI, termina en 2. Una CI estricta en rojo **solo** por esos fallos se informa
      así, sin presentar la CI como aprobada.
    - Para avanzar un gate de incremento o de hito, el replay y los demás controles exigibles cumplen sus reglas. Un fallo nuevo,
      una ejecución incompleta o un control necesario que no se ejecutó no quedan dispensados porque la CI tenga también fallos
      previos.
    - F4 y F5 siguen bloqueados mientras queden fallos declarados, igual que el cierre.
  - **Exclusivamente local:** si el destino del encuadre es solo local y nadie más trabaja en el repositorio, se trabaja sin
    remoto. La decisión y su límite (los commits se verifican con los hooks y el replay en la misma máquina) quedan una vez en
    `docs/estado.md` y en el ADR del modelo de despliegue. Si la persona ya lo expresó, se cita, sin pedirle que lo apruebe otra
    vez.
  - **Compartido o desplegado en remoto:**
    - Antes del primer push de código a un repositorio compartido (otra persona o un remoto común) o del primer despliegue
      remoto, se preparan el remoto y la CI.
    - Un remoto propio que solo guarda una copia (respaldo personal) no es un repositorio compartido, y un remoto por sí solo no
      es CI independiente.
    - Después del primer push autorizado y antes del gate que lo sigue, se comprueba la ejecución. La evidencia nombra el commit
      o árbol que la CI evaluó, la ejecución (id o URL) y su conclusión. Una referencia local `origin/*` o un workflow presente no
      demuestran que la ejecución ocurrió.
    - Consultar esa evidencia es una lectura. Publicar, fusionar y desplegar conservan cada uno su autorización, que esta regla
      no da.
  - **Alcance:** esta regla dice cuándo se ejecutan y se comprueban los controles. No acredita que el workflow funcione en Linux,
    que los validadores sean auténticos (el replay aplica los del checkout actual; la CI, los del commit) ni que la rama esté
    protegida.
  - **`--no-verify`** sigue siendo el escape autorizado. Un commit correcto hecho sin hooks pasa el replay; uno que incumple el
    contrato o una guarda falla y bloquea el gate. `--no-verify` no vuelve válida una modificación de un registro ni permite
    dejarla fuera de la validación.
  - **Recuperación de un commit que falla el replay** (p. ej. una línea corrupta en `docs/revisiones.log`, que bloquea además
    todos los commits siguientes):
    - **Historia no publicada:** la recuperación puede requerir reescribir los commits locales afectados, con autorización
      explícita de la persona para ese caso. La regla no autoriza al agente a hacerlo por su cuenta. Antes se conservan una
      referencia recuperable (una rama con la historia anterior) y la evidencia del fallo. Después se valida el rango resultante
      desde el último commit validado.
    - **Historia compartida:** el gate queda bloqueado y se presenta a la persona una propuesta de recuperación para que
      decida. No hay autorización implícita de force-push ni excepción que salte commits del replay.
  **Al montar el CI**: la política de rango de commits está en la
  cabecera de `.github/workflows/metodo.yml` y los comandos, en sus pasos (`steps`); en otro CI se
  copian ambos. Un merge limpio no lleva trailer; lo que se añade al fusionar es contenido nuevo
  (cabecera del `commit-msg`, texto «MERGE LIMPIO»). Las guardas de contenido son una sola, `scripts/guardas.sh`.
- **Base del método (solo proyectos adoptados):** el Paso 0 añade aquí una línea
  `- **Base del método:** <sha>` con el **último commit previo a la adopción**. **Nace una vez y no
  cambia.** Qué hacen con ella el replay y el `commit-msg`, y qué archivos que colisionaron son producto:
  `docs/arranque-existente.md` §Paso 0, H. Ahí se interpreta un rechazo que la nombre.
- **Plantilla de origen (proyectos nuevos):** el Bootstrap añade aquí `- **Plantilla de origen:**
  <sha>`, el commit de la plantilla que se extrajo (la receta del README lo deja en
  `.git/plantilla-origen`). Si falta y nadie lo sabe con evidencia, se declara `desconocida`: no se
  deduce del HEAD actual de la plantilla. Es el **origen**, no el estado actual: las adaptaciones
  locales y las actualizaciones posteriores no las describe este SHA. Tampoco fija la versión de cada
  contrato, que la dan sus marcadores (`CHANGELOG.md` de la plantilla). Depende del procedimiento: el
  doctor no la exige. En un proyecto adoptado no se añade: lo dicen `contexto/adopcion.md` y
  `contexto/adopcion-actualizaciones.md`.
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
  - **Gates intermedios del arranque** (completitud y ruteo, antes del cierre de F1): la regla
    también rige; su commit preparatorio `Ref: F1` y qué guarda cada uno, en `docs/arranque.md` §Fase 1 a.
  - **Entrada con versionado pendiente** (datos personales, volumen): no se commitea antes de que
    la persona decida. Antes del commit se ignora como provisional por su **ruta concreta**, con
    el comentario en su propia línea (en `.gitignore` un `#` a mitad de línea no comenta), y se
    comprueba que la regla la cubre (`git check-ignore -v <ruta>`) y que no está ya rastreada ni
    preparada para commit (`git ls-files --error-unmatch <ruta>` debe fallar). `.gitignore` no
    protege un archivo rastreado o ya en el índice: si lo está, **detente** y presenta el
    tratamiento; no lo retires del índice ni reescribas la historia por tu cuenta. La entrada se
    nombra en `docs/estado.md` y en la pregunta del gate.
  - **Secretos** (credenciales, claves, tokens): no son una decisión de versionar o no; nunca
    entran al historial. Si llegan a `contexto/`, se excluyen por ruta con la misma comprobación y
    se avisa a la persona; para trabajar se usa una muestra saneada o una configuración de ejemplo
    sin valores secretos.
- Mensaje concreto y suficiente: qué cambió y por qué (no "varios cambios"). **Asunto
  con alias** cuando resuelve un ID: `I5 «motor-indicadores»: qué cambió y por qué`.
  Con el trailer, `git log --oneline` queda como índice legible y
  `git log --grep="Cierra: R-I9.1"` recupera cualquier cierre puntual. Git es
  **archivo**, no contexto de trabajo: la operación diaria no lo relee.
- **Enlaza** cada commit en el footer con la gramática cerrada de la cabecera del
  `commit-msg`: `Ref: F1|F2|F4|F5`, `Ref: I<n>`, `Ref: hito:I<a>-I<b>`, `Cierra: R-<ID>` (familias
  de IDs: `docs/trazabilidad.md` §IDs). **Transiciones:** ningún hallazgo con fila o entrada del
  Histórico en HEAD desaparece, ningún `C<n>` del último `Ref: F2` desaparece del encuadre (`docs/arranque.md` §Reentrada), donde «el último `Ref: F2`» es el más cercano por ascendencia, no por fecha (si se integran dos paralelos con contratos distintos, nadie revisó la combinación: hace falta un `Ref: F2` sobre ella), y una fila que pasa a `resuelto` o `verificado` lleva en «Resuelto»
  una referencia que **resuelve** (ruta `archivo:línea` del índice o commit del historial); que
  **demuestre** la resolución lo juzga el revisor. **El código del producto** —todo lo que no es
  rastro, plantilla ni configuración del repositorio: lista `SIN_REVISION` del `commit-msg`; la
  configuración operativa del producto (sus workflows de `.github/`, cualquier `CODEOWNERS`,
  también en `docs/`), sus pruebas propias en `scripts/pruebas/`, sus hooks propios
  en `.githooks/` y, desde el primer `Ref: F2`, el cuerpo de `scripts/check.sh` (lo posterior al bloque de la
  suite vigilada; actualizar solo el bloque no lo es) cuentan como producto; un renombrado cuenta por su origen y su destino— entra solo
  con `Ref: I<n>` y recibo del juez; ampliar esa lista es un ADR. En un proyecto adoptado
  hay más producto (archivos propios que colisionaron, `scripts/adoptar.sh` y su regresión):
  `docs/arranque-existente.md` §Paso 0, H.

## Revisores y sandbox

- **Por defecto:** filtro preventivo de revisores (`.claude/hooks/guarda-revisor.py`) y
  modalidades de escritura según `.claude/skills/dirigiendo-revisiones/SKILL.md`. No es frontera.
- **Sandbox de Bash** (opcional, por proyecto; ADR): la única restricción efectiva de escritura
  y red para los comandos de shell, en toda la sesión. **Antes de activarlo o de declararlo en
  un informe**: alcance, configuración y cómo verificarlo en `dirigiendo-revisiones` §Modalidades.

## Pruebas
- **Herméticas:** sin dependencia de `.env` real ni de servicios externos; inyectar
  o mockear. Un test cuyo resultado cambia por un `.env` es frágil.
- **Dónde escribe la suite:** _<rutas, todas ignoradas por git; se llena cuando nace
  `scripts/check.sh`>_. Fuera de ellas, o si llama servicios o lee un `.env` real, se corre
  en copia aislada (`.claude/skills/dirigiendo-revisiones/SKILL.md` §Chequeos autorizados).
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
