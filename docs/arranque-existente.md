# Arranque sobre un proyecto existente (guion del agente)

> **Para el agente.** Este guion reemplaza a `docs/arranque.md` cuando el repositorio **ya
> tiene código que funciona** —reciente, heredado o hecho con agentes—. El objetivo no es
> reconstruirlo ni «normalizarlo», sino llevarlo al mismo punto al que llega un proyecto
> nuevo al aprobar su plan: **entendido, protegido por pruebas relevantes y listo para
> evolucionar**, sin alterar lo que ya hace. Las fases, los roles, los hooks y la
> reentrada son los de siempre; aquí solo está **lo que difiere**. Lo compartido se cita
> de `docs/arranque.md` y no se repite.

**Cuándo aplica.** La persona lo pide («arranca sobre proyecto existente»): eso confirma el
modo, no se vuelve a preguntar. Si nadie lo pidió pero hay código del producto fuera del
rastro y `docs/estado.md` no declara fase, **propón** este modo antes de actuar.

**Rige igual que en el arranque normal:** la REGLA DURA (validador en PASA **y** OK
explícito por actividad), la sección Transversal (hallazgo ≠ decisión, ADR con hora UTC,
etiquetas `REGISTRADO` / `PROPUESTO` / `PENDIENTE`, alias al crear) y el formato del gate
como resumen ejecutivo (`AGENTS.md` §2).

## Contrato de adopción

Ocho cláusulas que no se negocian en cada proyecto; si una no puede cumplirse, se dice y
se decide con la persona antes de seguir.

1. **Fuente.** El repositorio es la entrada. `contexto/` lleva el brief de adopción y el
   manifiesto de instalación; el código y los datos **se referencian donde están**, no se copian.
2. **Nada del producto cambia en el arranque.** Solo entran archivos del método,
   `scripts/check.sh`, entradas de `.gitignore` y —con aprobación explícita— la retirada de
   secretos versionados. Todo lo demás espera a un incremento con juez (Fase 3).
3. **Colisiones.** Se listan antes de copiar y **nunca se sobreescriben**. El README, la
   documentación y las instrucciones de agente que el proyecto ya tiene se conservan; su
   integración es explícita, por archivo y aprobada.
4. **Línea base.** Lo que el código ya hace distinto de la Definición de Hecho (estilo,
   idioma, rutas, configuración, documentación de interfaces) se registra en
   `docs/encuadre.md` §Línea base y **no se le exige al incremento que no lo toca**; las
   garantías sobre el cambio actual, sí (cláusula al inicio de `docs/definicion-de-hecho.md` §A).
5. **Base del método.** `docs/convenciones.md` declara el último commit previo a la adopción
   (`- **Base del método:** <sha>`). El replay del historial excluye lo anterior y valida
   el commit de instalación y todo lo posterior.
6. **Qué se protege.** Los criterios `C#` describen comportamiento observable que **ya
   existe y debe conservarse** (de 3 a 8). Cada uno tiene una prueba que demuestra la
   garantía o una brecha nombrada. Una prueba cuenta por lo que ejecuta, no por su nombre.
7. **Qué basta para cerrar el ciclo de adopción.** Cada `C#` verificado, los límites
   conocidos escritos como no-objetivos y las mejoras en el backlog ordenadas por impacto.
   No se corrige nada en este ciclo salvo que rompa un `C#` vigente o impida ejecutar o
   verificar con seguridad, y lo decide la persona.
8. **Entorno que funciona.** Se registra antes de tocar nada: si después algo falla, se
   sabe contra qué comparar.

## Paso 0 · Adopción (instalar el método sin tocar el producto)

Pasos A–C los corre la persona (o el agente a su pedido) **desde la plantilla**; D–H, el
agente **dentro del proyecto**. Ninguno modifica la lógica del producto.

**A. Inspección previa** (solo lectura).
`sh scripts/adoptar.sh inspeccionar <ruta-del-proyecto>` registra commit actual, cambios
pendientes, `core.hooksPath`, hooks propios y qué existe ya (README, CLAUDE.md, AGENTS.md,
`.claude/`, `scripts/`, `docs/`, `.github/`). Detecta dos **bloqueos**: un enlace
simbólico en cualquier componente de una ruta destino y una ruta que el `.gitignore` del
proyecto ignora. Con bloqueos no se sigue: se resuelven con la persona. Con cambios
pendientes en el proyecto, se pide commitearlos o apartarlos antes: la instalación tiene
que poder distinguirse de ellos.

**B. Vista previa** (no escribe).
`sh scripts/adoptar.sh vista-previa <ruta>` lista archivo por archivo: qué se copiaría,
qué **afecta el autodescubrimiento del agente** desde que se copia (`.claude/`,
`CLAUDE.md`, `AGENTS.md`), qué colisiona y se conserva, qué queda **excluido
deliberadamente** (README.md, .gitignore, mejoras/) y qué integraciones quedan a mano.
La persona revisa antes de copiar.

**C. Copia de lo ausente.**
`sh scripts/adoptar.sh copiar <ruta>` copia solo archivos que no existen y crea
`contexto/adopcion.md` (añadidos con su hash, colisiones, idénticos, excluidos,
pendientes). Repetirlo no escribe nada; el manifiesto **no se modifica** después: las
corridas siguientes clasifican contra él (sin cambios, modificado en el proyecto,
plantilla actualizada, idéntico sin registro, colisión) e informan.

**D. Integraciones acordadas** (cada una con OK explícito; ninguna toca lógica del producto).
- **`.gitignore`:** `sh scripts/adoptar.sh gitignore <ruta>` evalúa el efecto del bloque del
  método antes y después. Si ocultaría un archivo **versionado** (típico: un `.env`), no se
  aplica nada: primero se decide qué hacer con ese archivo (cláusula 2) y se repite con
  `--aplicar`. Lo que el proyecto ya ignoraba estando versionado es un **hallazgo**, no un bloqueo.
- **`CLAUDE.md` / `AGENTS.md` del proyecto:** no se renombran ni se diluyen. Si existe
  `CLAUDE.md`, se le añade la importación `@AGENTS.md`. Si existe `AGENTS.md` propio, sus
  instrucciones operativas se conservan con su alcance y prioridad (p. ej. como
  `docs/instrucciones-del-proyecto.md`, referenciado desde §1 del `AGENTS.md` del método
  como **lectura obligatoria**); la forma concreta se acuerda con la persona.
- **Colisiones en `docs/`** (p. ej. un runbook en `docs/despliegue.md`): se conserva el del
  proyecto. Su integración con la estructura del método se hace en la Fase 1, **siempre que
  el doctor lo acepte ya** (paso G); si no, se integra aquí lo mínimo para que lo acepte.
- **Hooks y CI existentes:** si `core.hooksPath` apunta a otra carpeta o hay hooks propios
  en `.git/hooks`, se acuerda cómo conviven **antes** de activar los del método (p. ej.
  llamarlos desde `.githooks/`). `.github/workflows/metodo.yml` solo aplica a GitHub
  Actions; en otro CI se copian sus comandos (`docs/convenciones.md` §Git).

**E. Brief de adopción.** Un archivo corto en `contexto/` (p. ej. `contexto/brief-adopcion.md`)
con lo que el repositorio no dice: por qué se adopta el método, qué requerimientos o
mejoras se esperan después, quién opera el sistema y qué está prohibido tocar. Si la
persona lo dice en el chat, se captura ahí. Fila en el manifiesto de `contexto/README.md`.

**F. Línea base del entorno** (`contexto/exploracion/entorno-base.md`).
Versión del lenguaje, dependencias **instaladas** (no solo declaradas), comando de pruebas
existente y su resultado. **Antes de correr la suite**, lee qué hace: si escribe archivos,
llama servicios o lee un `.env` real, ejecútala aislada (copia temporal, variables
neutras, sin red). El resultado es uno de: `pasa (N pruebas)`, `falla (cuáles)`, `sin
pruebas`, `dependencias incompletas` o `requiere acceso externo`, y se registra tal cual.
**No se corrige nada.** Un `.env` versionado es un hallazgo con propuesta aparte.

**G. Controles.**
- `scripts/check.sh` nace aquí (no en F2: el stack ya existe) con el comando de pruebas
  que ya funciona. Imprime **cuántas pruebas ejecutó** y un aviso visible si fueron cero;
  un cero silencioso está prohibido. El **linter no se activa todavía**: su alcance sobre
  código preexistente se decide en la Fase 2 con la línea base.
  `check.sh` corre con el intérprete y las dependencias **del proyecto** (su entorno
  virtual, por ejemplo); con otro intérprete falla en rojo, y es lo correcto: el pre-commit lo
  ejecuta en cada commit.
- `git config core.hooksPath .githooks` (tras resolver la convivencia del paso D),
  `git add -A` y `sh scripts/check_docs.sh` hasta PASA. El doctor lee el índice: antes de
  añadir los archivos los reporta como hooks sin bit ejecutable.

**H. Commit de instalación.**
- Añade a `docs/convenciones.md` §Git la línea `- **Base del método:** <sha>` con el
  commit actual del proyecto (**previo** a la instalación): `git rev-parse HEAD` antes de commitear.
- `docs/estado.md`: `Fase actual: F1 · en curso: reconocimiento del sistema existente`, con
  lo pendiente en frases completas. El commit **no afirma** que haya encuadre ni protección.
- Commit con `Ref: F1`, sin tocar código del producto (el hook lo rechazaría). Comprueba
  `sh scripts/pruebas/validar_historial.sh HEAD`: debe validar solo el commit de instalación.
- Si el remoto es compartido, trabaja en una rama y acuerda con la persona cuándo se integra.

**Validador del Paso 0 (PASA/FALLA):**
- [ ] La inspección no tiene bloqueos y la persona revisó la vista previa.
- [ ] `git diff --stat <base>..HEAD` solo muestra archivos del método, `contexto/`,
  `docs/`, `scripts/check.sh`, `.gitignore` y, si se aprobó, la retirada de secretos. El
  README y los archivos en colisión están **idénticos** a la base.
- [ ] Cada colisión e integración pendiente del manifiesto tiene resolución aprobada o
  está explícitamente diferida a la Fase 1.
- [ ] `contexto/exploracion/entorno-base.md` registra entorno y resultado de la suite.
- [ ] `scripts/check.sh` existe, corre lo que ya había y reporta el número de pruebas.
- [ ] Hooks activos y ejecutables; `sh scripts/check_docs.sh` en PASA.
- [ ] Commit de instalación con `Ref: F1`, base declarada y `validar_historial.sh HEAD` en verde.

**Gate del Paso 0:** resumen ejecutivo: qué se instaló, qué se conservó, qué quedó
pendiente de integrar, cómo está la suite, y que lo siguiente es **entender el sistema**.

---

## Lo que sigue (borrador; se valida y se precisa en el piloto)

> Este bloque fija la dirección acordada; sus validadores binarios se escriben tras el
> primer piloto. Mientras tanto se aplica con criterio y se anota en `docs/MEMORIA.md` lo
> que no funcione.

**Fase 1 · Reconocimiento** (lectura y ejecución; nada del producto cambia). Produce en
`docs/encuadre.md`, corto y referenciando lo que ya está escrito:
1. **Qué hace:** contexto en cinco líneas; §Entradas y salidas con muestra real referenciada;
   una ejecución local registrada.
2. **Arquitectura tal como está:** el sistema, sus dependencias externas y las
   responsabilidades principales; se amplía solo donde ayude a entender o modificar. El
   diagrama del README se **verifica** (o se crea si no hay).
3. **Cómo funciona:** flujo en pasos, parámetros, estados, errores y dependencias, en una
   página. El README se verifica contra el código y cada desfase es un hallazgo.
4. **Criterios vigentes y mapa de protección:** `C#` por comportamiento observable, set de
   oro con pares reales cuya procedencia (versión, datos, parámetros) se conoce, y cada
   prueba existente mapeada a lo que **realmente ejecuta**. La brecha queda nombrada.
5. **Convenciones observadas** y **§Línea base** (cláusula 4).
6. **Decisiones visibles:** ADR retrospectivos que separan **evidencia** (lo que el código
   muestra), **explicación confirmada** por la persona e **hipótesis**; fecha de
   documentación en UTC, nunca una fecha original inventada (si git la da, se cita el commit).

**Fase 2 · Diagnóstico y plan.** Pasada de línea base del juez de conjunto (y del de
seguridad si hay superficie de riesgo): sus hallazgos no bloquean commits, alimentan el
diagnóstico. El diagnóstico va en dos pistas —**método** (pruebas, convenciones, rastro,
runbook) y **solución** (arquitectura, componentes, dependencias, operación)—, cada ítem con
evidencia, impacto, esfuerzo y riesgo de regresión, y se clasifica con una pregunta: ¿rompe
un `C#` vigente, o impide ejecutar o verificar con seguridad? Si sí, incremento propuesto;
si no, backlog. El plan separa **protección** (lo mínimo para decir «protegido»; puede no
haber nada si la protección ya basta) de **mejora** (opcional). Revisor funcional y gate F2
como siempre. En el gate la persona elige: **mejorar ahora**, o **proteger, cerrar el ciclo
y seguir con funcionalidad nueva** por reentrada (recomendado: cerrar deja una línea base
verificada antes de cambiar nada).
