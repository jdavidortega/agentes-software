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
   **registros** fuera de la huella (recibo, filas, `estado.md`, consumo y lecciones en
   `MEMORIA.md`). El `commit-msg` rechaza `Ref: I<n>` sin la casilla en `[x]` o sin
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
   decláralo en el informe. El rechazo del canario muestra qué archivo se leyó.
   - **lectura** (por defecto): el revisor no escribe en ningún sitio. Borra
     `.git/revision-modalidad` o escribe en él `lectura`.
   - **experimentos** (reproducir, sabotear, correr algo que genera archivos):
     `D=$(mktemp -d)` y `printf 'experimentos %s\n' "$D" > .git/revision-modalidad`. Es el
     **único** lugar donde el revisor está autorizado a escribir.

## Invocación

4. Lanza el agente declarado (`.claude/agents/<rol>.md`) o, sin subagentes, el «Prompt
   de invocación» de su skill. Pásale **solo** qué revisar: rol, alcance, rango del diff
   (`git diff <base>..HEAD` o árbol de trabajo) y los archivos. **No** le resumas tu
   solución ni le adelantes conclusiones. Dile la **modalidad** con su regla literal: «no
   escribas en ningún sitio, tampoco en directorios temporales» o «escribe solo en `<D>`»; y
   pídele, como primer comando, el **canario** `touch .git/canario-revisor`: si el filtro
   preventivo está activo debe rechazarse (en experimentos también, porque no nombra `<D>`).
5. Pídele el reporte con el **formato exacto** y dentro del **presupuesto**: Veredicto ·
   Bloqueantes (ID, criterio, una frase, fila lista) · Sugerencias (máx. 5, una línea
   cada una) · Preguntas · Cobertura y limitaciones (seguridad) · Obstáculos («ninguno»
   si no hubo) · **Recibo** (la línea para `docs/revisiones.log`, con la huella que él
   mismo calculó con `sh scripts/huella.sh`). **Sin narrativa**: un reporte de revisión
   cabe en ~40 líneas salvo que haya muchos bloqueantes; lo que no decide no se escribe
   (`docs/convenciones.md` §Contexto).

## Al recibir

6. **Integridad:** `I1=$(sh scripts/huella.sh integridad)`; exige `I0 == I1`. Si difiere,
   el revisor escribió algo (código, docs o registros): la revisión **no vale**, averigua
   qué y repítela. La huella **detecta diferencias observables** en el repositorio al final;
   no lo protege contra escrituras ni ve cambios transitorios, la red o lo ignorado por git.
   **Vigencia:** exige `V0 == huella del recibo`; si difiere, el revisor juzgó otra cosa.
   **Modalidad:** en experimentos, inventaría `<D>` (`ls -laR "$D"`), copia a
   `contexto/exploracion/` solo lo que sea evidencia y borra `.git/revision-modalidad`. Si
   existe `.git/canario-revisor`, el filtro **no** estaba activo: bórralo y decláralo.
7. **Registra tal cual, sin editar:** la línea del recibo al final de
   `docs/revisiones.log` (append; nunca se compacta) y las filas de hallazgos en
   `docs/trazabilidad.md` (numeración que continúa, incluido el Histórico). Ambos están
   fuera de la huella, igual que `estado.md` y `MEMORIA.md`: registrarlos no invalida el
   recibo.
8. **Declara la modalidad** en el informe de la revisión (y en la bitácora), sin tocar la
   gramática del recibo: modalidad (`lectura` | `experimentos`), directorio autorizado,
   **filtro preventivo** (`comprobado`: el canario fue rechazado · `desactivado`: el canario
   se creó · `sin verificar`), **aislamiento** (`ninguno` · `sandbox configurado` · `sandbox
   verificado`, ver §Modalidades), comprobaciones hechas (huellas, inventario) y **límites**.
   Sin aislamiento verificado, el límite dice: «no se garantiza la ausencia de escrituras
   fuera del repositorio».
8b. **Rutea los obstáculos a `docs/MEMORIA.md`** (sección «Operativa») y la línea de
   consumo a `MEMORIA.md` §Consumo: comandos, flags, workarounds, tokens. Su promoción a `docs/convenciones.md` va en el **siguiente** incremento,
   porque `convenciones.md` sí es contenido revisado y cambiarlo ahora invalidaría el
   recibo.
9. Con **FALLA**: resuelve los bloqueantes como subtareas, deja en cada fila la mutación
   que ahora muere (`verificando-por-sabotaje`), marca `resuelto`, y vuelve al paso 1: la
   siguiente pasada produce un recibo nuevo (el hook solo acepta el **último** del mismo
   rol, tipo y alcance).
10. Con **PASA**: cierra con la lista B de la DoD y el commit enlazado. El `commit-msg`
    verificará el recibo contra la huella del índice; si rechaza por huella, algo cambió
    después del PASA: no lo "arregles" editando el recibo, repite la revisión.

## Modalidades de escritura (qué garantiza cada control)

- **Filtro preventivo** (`.claude/hooks/guarda-revisor.py`, hook `PreToolUse` de Bash en
  `.claude/settings.json`; solo actúa sobre los cuatro revisores por `agent_type`): rechaza
  escrituras **evidentes** en el texto del comando según la modalidad. **No es frontera:** no
  ve lo que escribe un programa lanzado desde el comando (python, git) y un comando que nombre
  `<D>` pasa aunque también escriba en otro sitio. Solo corre si el proyecto aceptó la
  confianza de la carpeta; por eso se **comprueba** con el canario, no se presume.
- **Directorio autorizado** (experimentos): **delimita la autorización**; sin una restricción
  efectiva, no impide escribir fuera.
- **Sandbox de Bash** (opcional por proyecto, `docs/convenciones.md` §Revisores y sandbox): la
  única restricción efectiva, aplicada por el sistema operativo a los comandos de shell y sus
  procesos hijos; es de **toda la sesión** (principal incluido) y no cubre herramientas de
  archivos, hooks ni MCP. «Sandbox configurado» no equivale a «ejecución aislada»: solo se
  declara `verificado` si una escritura fuera de lo permitido se intentó y el sistema la negó.
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
  contador; solo el commit.
- **Un incremento no cierra con sus hallazgos abiertos:** `Ref: I<n>` se rechaza mientras
  algún `R-I<n>.*` o `R-S<n>.*` siga `abierto`; `resuelto` (con su mutación escrita) basta
  para el commit, `verificado` es condición de salida de la fase. Y el código solo entra
  con `Ref: I<n>`: un `Cierra:` solo no lo acredita.
- **El gate humano es aparte, y el recibo no es una identidad:** el recibo ata un
  veredicto a este contenido exacto (huella); no prueba quién lo ejecutó ni que un modelo
  corrió (`ejecutor=` es dato declarado; eso lo cubren CI y los hooks del cliente, no este
  archivo). La aprobación la da la persona en el chat con el resumen ejecutivo
  (`AGENTS.md` §2). No se finge ni se registra en nombre de nadie.
