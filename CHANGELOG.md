# Cambios del método

Lo que cambia para quien usa el método: procedimiento, instrumentación, compatibilidad, migraciones y
correcciones de seguridad. No es un sistema de versiones ni una fila por commit: **una entrega es un
commit de la plantilla** y se identifica por su SHA; la fecha solo orienta.

- **Origen de tu proyecto:** adoptado, `contexto/adopcion.md` («Plantilla de origen»); nuevo,
  `docs/convenciones.md` §Git («Plantilla de origen»), si la instalación lo registró. Sin registro ni
  otra evidencia, el origen es **desconocido**: no se deduce del HEAD actual de la plantilla.
- **Estado actual, que no es el origen:** un proyecto adoptado registra cada actualización por archivo
  en `contexto/adopcion-actualizaciones.md`, y `scripts/adoptar.sh vista-previa` distingue lo
  modificado en el proyecto de lo que la plantilla cambió. Las adaptaciones locales y las
  actualizaciones parciales hacen que el estado actual no lo describa un único SHA.
- **Qué cambió desde tu origen:** las filas posteriores a ese commit, y
  `git -C <plantilla> log --oneline <sha>..HEAD` para el detalle.

**Efecto en un proyecto existente** (una fila puede tener varios):
- **Sin acción:** no cambia nada de lo que el proyecto usa.
- **Instrucciones o rúbricas:** cambia el procedimiento o lo que revisa un rol (documentos del método,
  `AGENTS.md`, skills, agentes). No migra datos, pero el trabajo se hace distinto desde ese commit.
- **Instrumentación:** cambian scripts, hooks o la CI del método.
- **Migración:** hay que adaptar datos o contratos del proyecto.

Para traer instrucciones o instrumentación: en un proyecto adoptado, `scripts/adoptar.sh actualizar`
(sustituye solo lo que el proyecto no tocó y lo registra); en uno nuevo, a mano, comparando con la
plantilla. Los documentos propios del proyecto (`docs/plan.md`, `docs/estado.md`, `docs/encuadre.md`…)
nunca se sustituyen.

## Marcadores de contrato

Una línea dentro de un archivo del método que fija qué regla valida un commit. Son independientes de la
entrega: un proyecto puede usar una entrega nueva y conservar commits validados con un contrato anterior.

| Marcador | Dónde | Desde | Qué fija |
|---|---|---|---|
| `# contrato-recibos: 2` | `docs/revisiones.log` y `scripts/recibos.sh` | `ddb6c99` (2026-10-26) | Los recibos posteriores declaran `modalidad=`, `filtro=` y `aislamiento=` |
| `# contrato-set-de-oro: 1` | `scripts/check_docs.sh` | `672801f` (2026-11-03) | El contrato revisado incluye los archivos que enlaza el set de oro |

## Cambios actuales

Su referencia es el commit que contiene esta sección.

| Cambio | Efecto | Qué hacer |
|---|---|---|
| Sección «Desarrollo de la plantilla» del README: cómo se verifica un cambio del método mismo. Solo para quien desarrolla la plantilla. | Sin acción | — |

## Cambios desde el 2026-11-01

Lo anterior está en la historia de git.

| Commit | Fecha | Cambio | Efecto | Qué hacer |
|---|---|---|---|---|
| `37a4c26` | 2026-11-05 | Identificación de la entrega: la receta del README captura el SHA una vez, extrae ese mismo commit y lo deja en `.git/plantilla-origen`; el Bootstrap lo declara en `docs/convenciones.md` §Git. La recuperación compara solo contra un origen registrado o demostrado. Este registro de cambios. | Instrucciones | Proyecto nuevo ya instalado: declarar la plantilla de origen solo si hay evidencia (p. ej. el SHA anotado al instalar); si no, `desconocida`. El doctor no lo exige: depende del procedimiento. |
| `4b4eb81` | 2026-11-05 | Ejemplo completo de un ciclo (`ejemplo/`), solo en la plantilla. | Sin acción | — |
| `33734d3` | 2026-11-05 | La casilla `[x]` del plan no es un PASA (plantilla de `docs/plan.md`); requisitos y entornos probados en el README. | Instrucciones | El significado de la casilla rige también en proyectos existentes; su `docs/plan.md` no se sustituye. |
| `a3c2aa0` | 2026-11-05 | Regla 10: qué invalida una evidencia, qué suite corresponde, la repasada usa `scripts/check.sh`, duraciones como mediciones. | Instrucciones | Actualizar las skills `probando-con-datos-reales`, `dirigiendo-revisiones` y `revision-critica`, y la DoD. Las cabeceras de las regresiones solo cambian comentarios. |
| `b13d784` | 2026-11-05 | Commits preparatorios `Ref: F1` en los gates de completitud y ruteo; ignorado provisional comprobado; secretos fuera del historial. | Instrucciones | Actualizar `docs/convenciones.md` y `docs/arranque.md`. Cambia cómo se hacen los gates intermedios del arranque. |
| `7c12b84` | 2026-11-05 | `AGENTS.md` §8 remite a la excepción de fallos previos. | Instrucciones | Actualizar `AGENTS.md`. |
| `6d334db` | 2026-11-05 | **Seguridad:** la receta antigua para deshacer una extracción podía borrar archivos previos. Instalación encadenada y recuperación sin borrado. | Sin acción en proyectos ya instalados | No usar la receta antigua de recuperación. |
| `3ac7475` | 2026-11-04 | `sabotear.py` con el comparador de fallos previos: solo cuenta como detección lo que el comparador declara fallo nuevo. | Instrumentación; Instrucciones | Actualizar la skill de sabotaje y su script. Un sabotaje que solo rompe la importación ya no cuenta. |
| `e44277c` | 2026-11-04 | El lector del plan ignora líneas de bitácora fechadas fuera de `## Incrementos`; el arranque pide completar `AGENTS.md` §1; `verificado` de criterio y de hallazgo separados. | Instrumentación; Instrucciones | Actualizar `scripts/check_docs.sh` y los documentos. El doctor ya exigía `AGENTS.md` §1 desde F2. |
| `18e8926` | 2026-11-04 | Un ADR retrospectivo no decide el tratamiento de una prueba. | Instrumentación; Instrucciones | Adopción con fallos previos: un destino que sea un ADR retrospectivo deja de valer; cambiarlo por un `I<n>` o un ADR no retrospectivo. |
| `cbb899a` | 2026-11-04 | Corrección: `check_docs` dejaba carpetas de la suite en el TMPDIR de quien lo llamaba. | Instrumentación; Instrucciones | Actualizar `scripts/check_docs.sh` y la tabla de chequeos de `dirigiendo-revisiones`. Las carpetas que ya se acumularon no se borran solas. |
| `ffcfcfd` | 2026-11-04 | La CI corre el preflight de capacidades y la regresión de la suite vigilada; mejoras de `suite.py`. | Instrumentación | Actualizar `metodo.yml`, `scripts/suite.py` y la regresión; requisitos del README §Cómo usarla. |
| `09f261d`, `e0645ec`, `2de80c1` | 2026-11-04 | Selección de pruebas por garantía (M12); fuente única de hechos pendientes y de aceptación de ADR (M11), con su campo «Aprobación». | Instrucciones | Actualizar skills y documentos. Los ADR nuevos citan su aprobación. |
| `c57fd65` | 2026-11-03 | Replay local en cada gate; remoto y CI solo si se comparte o se despliega; el Bootstrap ya no exige remoto. | Instrucciones | Desde el primer incremento, cada gate informa el replay. |
| `56dda73`, `551a7c5`, `979477a` | 2026-11-03 | Protocolo común de hechos pendientes (M07); fuentes efectivas del revisor y tabla de chequeos con sus efectos (M08). | Instrucciones | Actualizar los documentos y las skills de revisión: cambian cómo se difiere un dato y qué ejecuta un revisor. |
| `6f86973` | 2026-11-03 | Fallos previos declarados en una adopción (unittest): línea base, comparador, testigo y destinos. | Instrumentación; Instrucciones | Sin registro de fallos previos, nada cambia. |
| `672801f` | 2026-11-03 | Marcador `# contrato-set-de-oro: 1`. | Instrumentación; Instrucciones; Migración | Los commits anteriores conservan su regla. Si el último `Ref: F2` no vale como referencia, el trabajo dependiente exige un `Ref: F2` de alcance F2 completo. La regla del contrato en `docs/encuadre.md` rige aunque ese documento del proyecto no se sustituya. |
| `feeb428` | 2026-11-03 | `docs/estado.md` §Criterios coincide con la cobertura de `docs/trazabilidad.md`. | Instrumentación; Migración | Desde F2, añadir o corregir esa tabla en `docs/estado.md`. |
| `4ab0748` | 2026-11-02 | `scripts/check.sh` empieza por el bloque canónico de la suite vigilada desde que existe, en cualquier fase. | Instrumentación; Instrucciones; Migración | Anteponer a `scripts/check.sh` el bloque de `docs/convenciones.md` §Comandos clave, sin cambios; actualizar `docs/convenciones.md` y `docs/arranque-existente.md`. |
| `60808b6` | 2026-11-02 | Las exenciones del `commit-msg` van por archivo, no por carpeta. | Instrumentación; Instrucciones | Un archivo propio en `.github/`, `scripts/pruebas/` o `.githooks/` entra con `Ref: I<n>`; actualizar `docs/convenciones.md` y `docs/arranque-existente.md`. |
| `e0ec507`, `73dfc8a` | 2026-11-01 / 02 | Aclaraciones de los dos caminos, autorizaciones cruzadas en la adopción y filtro de los revisores. | Instrucciones; Instrumentación | Actualizar documentos, agentes y `.claude/hooks/guarda-revisor.py`. |
