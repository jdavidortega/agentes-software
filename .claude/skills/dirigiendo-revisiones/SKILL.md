---
name: dirigiendo-revisiones
description: "Procedimiento del agente PRINCIPAL para pedir, recibir y registrar una revisión independiente (revisor funcional, juez de código, juez de conjunto, juez de seguridad): bitácora escrita antes, huella del contenido antes y después, invocación con contexto fresco y en serie, formato y presupuesto del reporte, recibo estructurado en docs/revisiones.log, registro de filas, ruteo de obstáculos y repetición si la huella cambia. Úsala cada vez que vayas a cerrar el arranque (F2), un incremento (F3), un hito o la Fase 4, antes de invocar al revisor. Los invariantes están en AGENTS.md §9; aquí está el cómo."
allowed-tools: Read, Grep, Glob, Bash
---

# Skill: Dirigiendo revisiones (para el principal)

> `AGENTS.md` §9 fija lo que no cambia: quién revisa, con qué contexto, qué no puede
> hacer y que el recibo ata el veredicto al contenido. Esta skill es el procedimiento
> paso a paso para el **principal**; se carga solo al cerrar una actividad revisable.

## Antes de invocar

1. **Deja escrito todo lo revisable**: la bitácora del incremento en `docs/plan.md`
   **ya colapsada a su línea** (qué cambió y por qué) y su casilla en `- [x]`, el `README.md` al día si cambió
   comportamiento, ADRs si hubo decisión. `plan.md` y `convenciones.md` cuentan en la
   huella: después del PASA no se tocan. Lo que sí se escribe después son los
   **registros** fuera de la huella (recibo, filas, evidencia en `docs/revisiones/`, `estado.md`,
   consumo y lecciones en `MEMORIA.md`). **Nada de la revisión va a `contexto/` después del PASA**:
   `contexto/` es contenido revisado y caducaría el recibo. El `commit-msg` rechaza `Ref: I<n>` sin la casilla en `[x]` o sin
   `estado.md` en el commit.
2. **Stagea todo** (`git add -A`) y toma las dos huellas: `V0=$(sh scripts/huella.sh)`
   (vigencia: lo revisable) e `I0=$(sh scripts/huella.sh integridad)` (integridad: todo,
   registros incluidos).
3. Decide **qué rol** toca y su **alcance** (`AGENTS.md` §9): encuadre `F2` → revisor
   funcional; incremento `I<n>` → juez de código (+ seguridad si toca superficie de
   riesgo); hito `hito:I<a>-I<b>` → juez de conjunto (+ seguridad); Fase 4 `F4` → juez de
   conjunto (+ seguridad). **Uno a la vez**; nunca con una suite o un sabotaje corriendo.
3b. Fija la **modalidad de escritura** (procedimiento de control, no garantía; ver §Modalidades).
   El filtro la lee de `.git/revision-modalidad` del **proyecto de la sesión**
   (`$CLAUDE_PROJECT_DIR`), no del repositorio revisado: si son distintos (p. ej. el principal
   revisa otro repositorio desde la sesión de la plantilla), escríbela en el de la sesión y
   decláralo en el informe. El rechazo de la prueba de bloqueo muestra qué archivo se leyó.
   - **lectura** (por defecto): el revisor no escribe en ningún sitio. Borra
     `.git/revision-modalidad` o escribe en él `lectura`.
   - **experimentos** (reproducir, sabotear, correr algo que genera archivos):
     `D=$(mktemp -d)` y `printf 'experimentos %s\n' "$D" > .git/revision-modalidad`. Es el
     **único** lugar donde el revisor está autorizado a escribir.
   La modalidad depende de la **operación**, no del rol: si la revisión necesita una herramienta
   que escribe temporales (`validar_historial.sh`, `sabotear.py`, una suite que crea archivos),
   es **experimentos**, y el revisor la corre con `TMPDIR="$D"` delante para que sus temporales
   caigan en el directorio autorizado. El filtro reconoce el directorio solo si el comando lo
   **nombra literalmente**: una variable (`> "$X/out"`) se rechaza aunque apunte a él. Dilo en
   el prompt; es un límite conocido del filtro, no un error del revisor.

## Invocación

4. Lanza el agente declarado (`.claude/agents/<rol>.md`) o, sin subagentes, el «Prompt
   de invocación» de su skill. Pásale **solo** qué revisar: rol, alcance, rango del diff
   (`git diff <base>..HEAD` o árbol de trabajo) y los archivos. **No** le resumas tu
   solución ni le adelantes conclusiones. Dile la **modalidad** con su regla literal: «no
   escribas en ningún sitio, tampoco en directorios temporales» o «escribe solo en `<D>`»; y
   pídele, como primer comando y **solo** (en un comando propio, sin nada más en la línea), la
   **prueba de bloqueo** `touch .git/prueba-de-bloqueo`: si el filtro preventivo está activo debe rechazarse
   (en experimentos también, porque su destino no está en `<D>`). Es inocuo si llega a
   ejecutarse: solo crea un archivo vacío que el principal busca y borra (paso 6).
5. Pídele el reporte con el **formato exacto** y dentro del **presupuesto**: Veredicto ·
   Bloqueantes (ID, criterio, una frase, fila lista) · Sugerencias (máx. 5, una línea
   cada una) · Preguntas · Cobertura y limitaciones (seguridad) · Obstáculos («ninguno»
   si no hubo) · **Recibo** (la línea para `docs/revisiones.log`, con la huella que él
   mismo calculó con `sh scripts/huella.sh`, y `modalidad=`, `filtro=` y `aislamiento=`: la
   modalidad y el aislamiento que le diste, y `filtro=comprobado` solo si su prueba de bloqueo
   fue rechazada. En experimentos, si conserva evidencia, la deja en `<D>/evidencia/` y añade
   `evidencia=docs/revisiones/<alcance>-<rol>-<AAAAMMDDTHHMMZ>@<h>` con
   `h=$(sh scripts/huella.sh evidencia <D>/evidencia)`. Gramática: `scripts/recibos.sh`). **Sin narrativa**: un reporte de revisión
   cabe en ~40 líneas salvo que haya muchos bloqueantes; lo que no decide no se escribe
   (`docs/convenciones.md` §Contexto).

## Al recibir

6. **Integridad:** `I1=$(sh scripts/huella.sh integridad)`; exige `I0 == I1`. Si difiere,
   el revisor escribió algo (código, docs o registros): la revisión **no vale**, averigua
   qué y repítela. La huella **detecta diferencias observables** en el repositorio al final;
   no lo protege contra escrituras ni ve cambios transitorios, la red o lo ignorado por git.
   **Vigencia:** exige `V0 == huella del recibo`; si difiere, el revisor juzgó otra cosa.
   **Modalidad:** en experimentos, inventaría `<D>` (`ls -laR "$D"`) y borra
   `.git/revision-modalidad`. Si el recibo trae `evidencia=docs/revisiones/<id>@<h>`, copia
   `<D>/evidencia/` **tal cual** a `docs/revisiones/<id>/` (fuera de la huella de vigencia; su
   propia huella `<h>` la ata al recibo: el `pre-commit` y el replay rechazan que no coincida, que
   falte o que cambie después). Si existe `.git/prueba-de-bloqueo`, el filtro **no** estaba activo:
   bórralo y la revisión no vale con `filtro=comprobado`: repítela o que el recibo diga
   `filtro=desactivado`.
7. **Registra tal cual, sin editar:** el revisor genera la línea con `sh scripts/recibos.sh
   linea …` (él declara veredicto, bloqueantes, autoría y modalidad; la herramienta pone la fecha
   de **emisión** y la huella, y la valida). Si llega inválida, la reemite el revisor; el principal
   nunca la corrige ni reescribe recibos ya registrados. Va al final de
   `docs/revisiones.log` (append; nunca se compacta) y las filas de hallazgos en
   `docs/trazabilidad.md` (numeración que continúa, incluido el Histórico). Ambos están
   fuera de la huella, igual que `estado.md` y `MEMORIA.md`: registrarlos no invalida el
   recibo.
8. **La modalidad queda en el recibo** (`modalidad=lectura|experimentos`,
   `filtro=comprobado|desactivado|sin-verificar` —comprobado: la prueba de bloqueo fue rechazada—,
   `aislamiento=ninguno|sandbox-configurado|sandbox-verificado`, ver §Modalidades): es lo
   **declarado**, no prueba que el aislamiento se aplicara; eso lo sostienen la evidencia y los
   controles efectivos. El informe al gate añade directorio autorizado, comprobaciones (huellas,
   inventario) y **límites**; sin aislamiento verificado: «no se garantiza la ausencia de
   escrituras fuera del repositorio». No va a la bitácora (`plan.md` está en la huella).
8b. **Rutea los obstáculos a `docs/MEMORIA.md`** (sección «Operativa») y la línea de
   consumo a `MEMORIA.md` §Consumo: `python3 scripts/consumo.py` (acumulado por modelo desde los
   transcripts locales) y una línea `Consumo I5 «alias»: +X entrada / +Y salida (acum X'/Y')`,
   delta contra la anterior; si el script falla, regístralo con `/usage` y anota el hallazgo.
   Obstáculos: comandos, flags, workarounds. Su promoción a `docs/convenciones.md` va en el **siguiente** incremento,
   porque `convenciones.md` sí es contenido revisado y cambiarlo ahora invalidaría el
   recibo.
9. Con **FALLA**: antes de corregir, evalúa por cada bloqueante si es una instancia de una
   **familia** (la misma omisión en otros estados, campos, dependencias o rutas). Si lo es, corrige
   la familia: busca las demás instancias y la fila nombra la familia y dónde se buscó. Si la
   familia ya había aparecido, la corrección es estructural (tabla o contrato compartido del plan
   de pruebas, `probando-con-datos-reales` regla 9), no otro caso suelto. La **repasada** se pide
   acotada al cambio desde el recibo anterior y a sus efectos (quién lo llama, qué datos comparte),
   **más** la suite completa y las filas de interacción del incremento: lo ya juzgado sin cambios
   no se vuelve a revisar, pero las regresiones sí se comprueban, y el revisor reporta cualquier
   defecto relevante que encuentre al hacerlo.
   Resuelve los bloqueantes como subtareas, deja en cada fila la mutación
   que ahora muere (`verificando-por-sabotaje`) con una **referencia que resuelve** (ruta
   `archivo:línea` de la prueba o mutación, o commit; el `commit-msg` la comprueba), marca
   `resuelto`, y vuelve al paso 1: la
   siguiente pasada produce un recibo nuevo (el hook solo acepta el **último** del mismo
   rol, tipo y alcance).
10. Con **PASA**: cierra con la lista B de la DoD y el commit enlazado. El `commit-msg`
    verificará el recibo contra la huella del índice; si rechaza por huella, algo cambió
    después del PASA: no lo "arregles" editando el recibo, repite la revisión.

## Modalidades de escritura (qué garantiza cada control)

- **Filtro preventivo** (`.claude/hooks/guarda-revisor.py`, hook `PreToolUse` de Bash en
  `.claude/settings.json`; solo actúa sobre los cuatro revisores por `agent_type`): rechaza
  escrituras **evidentes** en el texto del comando según la modalidad. En experimentos juzga
  **cada escritura por su destino** (tramos del comando, `cd`, `( )`, redirecciones, argumentos de
  cada orden, con el contenido de las comillas conservado): nombrar `<D>` en otro tramo no autoriza
  nada; `mv` cuenta origen y destino; las opciones globales de `git` (`-C`, `-c`, `--git-dir`,
  `--work-tree`) se leen antes del subcomando y sus destinos explícitos (`init <dir>`, `clone`,
  `worktree add`, `config --file`, `-o`) cuentan, consumiendo cada opción con su valor (una opción
  que no conoce deja el destino desconocido); un `cd` solo mueve lo que sigue dentro de su cadena
  `&&`, o después si el directorio ya existe (en una tubería, no); una escritura cuyo destino no sabe ubicar, en cualquier tramo, se
  rechaza, y lo que no sabe interpretar (`$( )`, comillas invertidas, `<<`, `eval`, `xargs`, `-c`,
  `find -exec`) junto a una escritura, también. **Sigue siendo una heurística, no una frontera:** no ve lo que escribe un programa
  lanzado desde el comando (python, git, un script). Solo corre si el proyecto aceptó la
  confianza de la carpeta; por eso se **comprueba** con la prueba de bloqueo, no se presume.
- **Directorio autorizado** (experimentos): **delimita la autorización**; sin una restricción
  efectiva, no impide escribir fuera.
- **Sandbox de Bash** (opcional por proyecto, decisión con ADR): la
  única restricción efectiva, aplicada por el sistema operativo a los comandos de shell y sus
  procesos hijos; es de **toda la sesión** (principal incluido) y no cubre herramientas de
  archivos, hooks ni MCP. Se configura en `.claude/settings.json` (documentación oficial:
  «Sandboxing»), p. ej. `{"sandbox": {"enabled": true, "allowUnsandboxedCommands": false,
  "filesystem": {"allowWrite": ["<dir>"]}}}`; por defecto ya permite escribir en el directorio de
  trabajo y en un temporal por usuario. «Sandbox configurado» no equivale a «ejecución aislada»:
  solo se declara `verificado` si una escritura fuera de lo permitido se intentó y el sistema la negó.
- **Suites:** `PYTHONDONTWRITEBYTECODE=1` (o el equivalente del stack) evita el bytecode, no
  garantiza una suite sin escrituras; una suite que genera temporales, bases o informes va en
  modalidad **experimentos**.

## Notas / trampas

- **Seguridad no se olvida por omisión:** el recibo del juez de código y del de conjunto
  declara `seguridad=requerida|no-aplica`; con `requerida`, el hook exige el recibo del
  juez de seguridad del mismo alcance y la misma huella.
- **No edites nunca `docs/revisiones.log` salvo para añadir una línea.** El `pre-commit`
  lo exige (lo guardado en HEAD debe ser prefijo exacto de lo nuevo): un FALLA no se
  borra, se añade la revisión nueva debajo. Y cada tres incrementos con PASA el hook
  exige un hito antes de cerrar el cuarto: planéalo, no te sorprenda. **Un hito es su
  commit** (`Ref: hito:I<a>-I<b>`: recibo del juez de conjunto —y de seguridad si la
  requiere— con la huella de ese commit, más la síntesis de `MEMORIA.md`), hecho después
  de los commits `Ref: I` que cubre. Un recibo de hito suelto en el log no cuenta para el
  contador; solo el commit. Gramática de `cubre=`/`excluye=`/`componentes=`: cabecera de
  `scripts/recibos.sh` §HITO. **Corrección de un hito** (sus bloqueantes `R-F4.n` cambian
  código): se **reabre** el incremento del rango cuyo código cambia (`Ref: I<k>`, juez de código
  sobre la corrección, `Cierra: R-F4.n`, `estado.md` regenerado); un incremento nuevo no sirve,
  sería el cuarto sin hito. El recibo del hito se pide al final, sobre el contenido definitivo:
  juez de código, después juez de conjunto, y nada revisable cambia tras su PASA. Puede ir en
  commits separados o en uno con ambos trailers.
- **Un incremento no cierra con sus hallazgos abiertos:** `Ref: I<n>` se rechaza mientras
  algún `R-I<n>.*` o `R-S<n>.*` siga `abierto`; `resuelto` (con su mutación escrita) basta
  para el commit, `verificado` es condición de salida de la fase. Y el código solo entra
  con `Ref: I<n>`: un `Cierra:` solo no lo acredita.
- **El gate humano es aparte, y el recibo no es una identidad:** el recibo ata un
  veredicto a este contenido exacto (huella); no prueba quién lo ejecutó ni que un modelo
  corrió (`ejecutor=` es dato declarado; eso lo cubren CI y los hooks del cliente, no este
  archivo). La aprobación la da la persona en el chat con el resumen ejecutivo
  (`AGENTS.md` §2). No se finge ni se registra en nombre de nadie.
