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

**Pasada de coherencia (antes de cada gate de este guion).** El doctor y los hooks prueban
integridad estructural, no que lo escrito sea coherente. Antes de pedir un gate, el agente
responde por escrito, en el resumen del gate, cuatro preguntas:
1. ¿Queda algún **ejemplo de la plantilla** en lo que este paso tocó (`docs/estado.md`,
   tabla de criterios, manifiesto de `contexto/README.md`, `docs/decisiones.md`)?
2. ¿`docs/estado.md` distingue **lo terminado**, **lo pendiente de aprobación** y **lo que
   falta**, sin contradecirse con lo commiteado (p. ej. «instalación terminada; gate
   pendiente», «criterios aún no definidos»)?
3. ¿Cada entrada nueva de `contexto/` tiene su **fila en el manifiesto** de `contexto/README.md`?
4. ¿Cada evidencia citada se puede **repetir desde lo escrito** (comando, directorio, qué
   se neutralizó, resultado)?
5. ¿Queda algún ADR `propuesta` **asignado a este gate**? Un gate no se cruza con decisiones
   suyas abiertas: se deciden, o se reasignan **con razón** a una actividad posterior. Una
   elección pendiente es ADR; un **hecho desconocido** no (va a §Pendientes con impacto y quién).

El resultado queda también en `docs/estado.md`, en una línea con lo que quedó pendiente; la
evidencia se referencia, no se copia. Así el revisor puede comprobar que la pasada ocurrió.

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
   integración es explícita, por archivo y aprobada. **Excepción a `AGENTS.md` §2 (README
   corregido antes de cada gate):** en una adopción el README se **verifica** y cada desfase se
   registra como hallazgo; su corrección es una integración que la persona aprueba (en el gate o
   en el plan), no un requisito para pedir el gate.
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
pendientes). Repetirlo no escribe nada; el manifiesto **no se modifica nunca**, tampoco
antes del commit de instalación: las corridas siguientes clasifican contra él (sin cambios,
modificado en el proyecto, plantilla actualizada, idéntico sin registro, colisión) e informan.

**Si la plantilla cambia después de copiar** (antes o después del commit de instalación):
`sh scripts/adoptar.sh actualizar <ruta> "<motivo>"` sustituye **solo** los archivos
instalados que el proyecto no tocó y deja una línea por archivo en
`contexto/adopcion-actualizaciones.md` (append-only: hash anterior, hash nuevo, plantilla,
fecha, motivo). Lo que el proyecto ya modificó no se sustituye: es una integración manual
con la persona. No se borra ni se reinstala nada, porque pueden existir integraciones manuales.

**D. Integraciones acordadas** (cada una con OK explícito; ninguna toca lógica del producto).
- **`.gitignore`:** `sh scripts/adoptar.sh gitignore <ruta>` evalúa el efecto del bloque del
  método antes y después. Si ocultaría un archivo **versionado** (típico: un `.env`), no se
  aplica nada: primero se decide qué hacer con ese archivo (cláusula 2) y se repite con
  `--aplicar`. Lo que el proyecto ya ignoraba estando versionado es un **hallazgo**, no un bloqueo.
  Si el `.gitignore` del proyecto es un enlace simbólico, el modo lo rechaza: escribir en él
  modificaría un archivo fuera del repositorio.
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
pruebas`, `dependencias incompletas` o `requiere acceso externo`, y se registra tal cual,
**con el procedimiento exacto para repetirlo**: comando, directorio desde el que corre,
qué se copió y qué se neutralizó (archivos, variables, red) y la salida resumida. Un
inventario de paquetes describe el entorno observado; no prueba que pueda reconstruirse.
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
- `docs/estado.md`: `Fase actual: F1 · instalación terminada; gate del Paso 0 pendiente`;
  en la tabla de criterios, «criterios aún no definidos (Fase 1)» en lugar de la fila de
  ejemplo; lo pendiente en frases completas. El commit **no afirma** que haya encuadre ni protección.
- Fila del brief y del manifiesto de instalación en el manifiesto de `contexto/README.md`,
  sin las filas de ejemplo.
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
- [ ] Pasada de coherencia respondida (cinco preguntas) sin ningún «sí» pendiente en la 1 y la 5
  ni «no» en las 2–4.

**Gate del Paso 0:** resumen ejecutivo: qué se instaló, qué se conservó, qué quedó
pendiente de integrar, cómo está la suite, y que lo siguiente es **entender el sistema**.

---

## Fase 1 · Reconocimiento (nada del producto cambia)

Produce `docs/encuadre.md` con **el sistema tal como está**, corto y referenciando lo que ya
está escrito, más `docs/convenciones.md` y `docs/decisiones.md`. Se lee el código entero
que toca cada capacidad; lo que se afirma, se cita.

**Marcas de origen** (sustituyen a las del arranque normal): `[de código: archivo:línea]`,
`[de ejecución: script, fecha]`, `[de contexto/: archivo]`, `[inferido]` (por confirmar) y
`[pendiente: quién lo confirma]`. El encuadre declara una vez el **commit evaluado**; cada `C#`
y cada hallazgo citan `archivo:línea` de ese commit.

**Sustitutos (fakes y mocks).** Toda verificación hecha con un sustituto (Redis en memoria,
broker eager, cliente HTTP falso, reloj fijo) declara **qué sustituye y qué garantía queda sin
verificar** por eso (p. ej. «TTL y concurrencia de Redis no verificados»), en la fila de
§Entradas y salidas o en el mapa de protección que corresponda.

**Desconocidos: hecho pendiente ≠ elección.** Un dato que solo la persona u operación sabe
(parámetros desplegados, política de una capa externa, tiempos reales) es un **hecho
pendiente de confirmar**: se escribe con su impacto y quién lo confirma, sin ADR. Solo hay
ADR (`propuesta`) cuando hay una **elección** entre opciones. Un pendiente no bloquea la
Fase 1 si ninguna garantía que se declare verificada depende de él.

**Actividades:**
1. **Qué hace.** Contexto en cinco líneas. §Entradas y salidas: una fila por entrada y por
   salida, con su muestra y una columna **qué se verificó / qué falta** (p. ej. «CSV histórico
   inspeccionado; contrato HTTP no comprobado»), nunca un «sí» que exceda lo comprobado.
   **Ejecución local:** la transformación principal corre sobre entradas reales con lo
   externo sustituido **en la frontera** (la llamada HTTP, no la lógica), con un script
   reproducible en `contexto/exploracion/`. Si no hay entradas reales accesibles, se dice.
2. **Arquitectura tal como está.** El sistema, sus dependencias externas y las
   responsabilidades principales; diagrama del README **verificado** (o creado). Versiones:
   las que corrieron; sin acceso autorizado a producción se escribe «evaluado localmente;
   equivalencia con producción no comprobada».
3. **Cómo funciona.** Flujo en pasos, estados y errores, en una página. **Parámetros:** los que
   gobiernan un comportamiento crítico (umbrales, límites de tiempo, reintentos, ventanas,
   tamaños de muestra) se listan **aunque coincidan con su valor por defecto**, con el valor
   configurado cuando difiere; los demás se referencian (`settings`, `.env.example`), no se copian.
   **Contratos de salida por camino**, con «no aplica» justificado cuando corresponda:
   éxito · sin datos · error previsto · excepción no prevista · fallo **antes** del manejo de
   errores (arranque) · caída de **cada** dependencia · entrada con formato inesperado ·
   concurrencia y locks (con y sin estado previo) · límites de tiempo (suave y duro) ·
   interrupción y **reentrega** · cambio de fecha o zona horaria (claves diarias, ventanas).
   En cada camino: qué ve **cada consumidor** (p. ej. el estado de la cola frente al de negocio).
   El README se verifica contra el código y cada desfase es un hallazgo (cláusula 3).
4. **Criterios vigentes y mapa de protección.** Un `C#` por comportamiento observable que
   debe conservarse, y **todo estado terminal** que el sistema expone tiene un `C#` o queda
   declarado fuera. Set de oro con **referencia producida por la versión actual** (no por un
   análisis previo cuya procedencia no se conoce), con **los pares necesarios para representar
   salidas y caminos materialmente distintos** (cinco es una referencia, no una garantía de
   suficiencia). Toda **cifra** del set de oro se **deriva del artefacto persistido** con una
   definición de conteo declarada (p. ej. vértices únicos, sin el punto que cierra el anillo) y
   se verifica contra él. Por par, procedencia (script o prueba que
   lo produce), y persistidos en `contexto/exploracion/` la **salida pequeña**, los
   **parámetros**, la **versión del código** y el **hash de la entrada** con **dónde y cómo
   obtenerla**; si la entrada no es accesible de forma estable, la reproducción se declara
   **limitada**. Mapa: cada prueba existente con lo que **realmente ejecuta** (qué sustituye).
   La brecha queda nombrada.
5. **Convenciones observadas** en `docs/convenciones.md`, en una sección propia **al inicio**
   («Observado en este proyecto»): cómo se configura, se levanta, se prueba y se aplica un cambio
   (comandos verificados) y el estilo tal como es. Las reglas de la plantilla **se conservan**:
   rigen lo nuevo o modificado. Lo que difiere de ellas va a `docs/encuadre.md` §Línea base (cláusula 4).
6. **Decisiones visibles** en `docs/decisiones.md`: ADR retrospectivos de lo que condiciona un
   cambio (algoritmos, parámetros, persistencia, políticas de reintento, nombres de salida),
   cada uno con **evidencia** (archivo), **explicación confirmada** por la persona o
   **hipótesis**; fecha de documentación en UTC, nunca una fecha original inventada.

**Revisión:** el revisor funcional en **modo adopción, alcance Fase 1** (rúbrica:
`.claude/skills/revision-funcional/SKILL.md` §En una adopción), antes del gate.

**Validador de la Fase 1 (PASA/FALLA):**
- [ ] Las seis actividades tienen su salida en el archivo que les toca.
- [ ] Cada fila de §Entradas y salidas dice qué se verificó y qué falta.
- [ ] Hay un script de ejecución local en `contexto/exploracion/` que corre la transformación
  principal sobre entradas reales, o la imposibilidad está declarada.
- [ ] La lista de caminos de la actividad 3 está completa: cada camino con su contrato o con
  «no aplica» justificado.
- [ ] Cada estado terminal expuesto tiene `C#` o está declarado fuera; cada `C#` tiene una
  prueba que lo ejecuta de verdad o una brecha nombrada, y cita `archivo:línea`.
- [ ] Cada par del set de oro tiene procedencia y referencia persistida (o reproducción
  declarada limitada); sus cifras se derivan del artefacto persistido.
- [ ] Cada verificación con sustituto declara qué garantía queda sin verificar.
- [ ] §Cómo funciona lista los parámetros críticos (aunque coincidan con su valor por defecto).
- [ ] `docs/convenciones.md` abre con «Observado en este proyecto» (configurar, levantar,
  probar, aplicar un cambio; estilo) y conserva las reglas de la plantilla.
- [ ] Sin `[inferido]` sin confirmar; cada `[pendiente]` con impacto y quién lo confirma.
- [ ] Revisor funcional en PASA y pasada de coherencia respondida y anotada en `docs/estado.md`.

---

## Fase 2 · Diagnóstico y plan (nada del producto cambia)

**Objetivo:** un **diagnóstico priorizado** y un **plan mínimo defendible**. El plan no convierte
cada hallazgo en trabajo: selecciona lo necesario y explica por qué lo demás puede esperar.

**1. Evidencia de línea base.** El principal invoca, en serie, al **juez de conjunto** y, si hay
superficie de riesgo, al **juez de seguridad**, sobre el sistema existente y **acotados a lo que
la Fase 1 no resolvió** (composición entre componentes, seguridad); reutilizan la evidencia de la
Fase 1 y no repiten reproducciones salvo por una duda concreta. Sus informes quedan en
`contexto/exploracion/linea-base-*.md` con IDs propios (`LB-C.n`, `LB-S.n`). No bloquean commits:
son **evidencia, no una lista de tareas**. Se registra el consumo de cada etapa.

**2. Diagnóstico** (`docs/plan.md` §Diagnóstico). Una fila por hallazgo relevante: los `H#` del
encuadre y los `LB-*`, **consolidando duplicados** (una fila, varias fuentes). **Inventario:** cada
ID de origen tiene **destino explícito** —fila propia, consolidado en otra fila (cuál), descartado
(razón) o pendiente— en un cotejo que permita contar origen contra destino; ningún ID desaparece.
Por fila:
- **Clase** (antes de valorar): incumplimiento de un `C#` · brecha de evidencia (un `C#` sin
  prueba que lo demuestre) · riesgo (algo que puede fallar y hoy no está contratado) · mejora
  opcional.
- **Valoración cualitativa:** impacto, probabilidad, esfuerzo y riesgo de regresión (alto, medio
  o bajo), con la **incertidumbre** declarada cuando falten datos. No se inventan puntuaciones.
  La probabilidad se apoya en datos representativos: una observación aislada (p. ej. una sola
  duración medida) no estima la cola; sin datos, **desconocida**, y el riesgo queda **condicionado**.
- **Valoración del informe**, en su propia columna, cuando difiera de la propia, con la
  justificación y su fuente. Así toda discrepancia es visible y la lista es cerrada.
- **Decisión:** seleccionado (→ `I#`) · diferido (**por qué puede esperar**) · pendiente de
  confirmar (qué dato y quién) · descartado (razón).
El diagnóstico **puede discrepar** de los informes de los jueces, con justificación y fuente.
**Si un informe contradice el encuadre**, primero se comprueba contra el código cuál afirmación es
correcta. Una corrección **factual** del encuadre (una fila de contratos, un hallazgo) se hace con
nota en el diagnóstico; si cambia un `C#` o el set de oro, es **reentrada** (ADR, revisor, gate).

**3. Plan** (`docs/plan.md`), en dos bloques separados:
- **Protección (obligatoria y mínima):** lo necesario para que **cada `C#` vigente quede
  verificable**. Un `C#` cubierto por pruebas existentes va a un incremento de **verificación por
  sabotaje** (`.claude/skills/verificando-por-sabotaje/SKILL.md`): demuestra que la prueba protege
  la garantía, sin tocar el producto. Un `C#` con brecha va a un incremento que escribe la prueba
  que falta (y, si hace falta, una costura mínima, con juez). Una prueba que fija un
  comportamiento observado **con limitación conocida** (un hallazgo) se marca como
  **caracterización**, citando el hallazgo: protege lo que hay hoy sin convertir el defecto en
  obligación; cambiarlo después exige actualizar el contrato (`C#` o ADR) en ese mismo incremento.
- **Mejora (opcional):** cada incremento dice qué riesgo trata y **por qué ahora** y no después.
Cada `I#` lleva alias e indica el `C#` que protege o el hallazgo que trata. **Línea de corte:**
un párrafo que explica qué queda fuera y por qué puede esperar. Plan de pruebas por incremento
(solo lo que cierra brechas). Decisiones con opciones (alcance del linter sobre lo existente,
tolerancia del set de oro…) como ADR; los ADR `propuesta` de la Fase 1 se resuelven o se
reasignan a su actividad. `docs/trazabilidad.md`: una fila por `C#` con su incremento.
**Reglas compartidas que se comprueban aquí** (no se repiten): `AGENTS.md` §1 sin marcadores
(el doctor los rechaza desde F2); el plan respeta la regla de **hito** (`docs/convenciones.md`,
«Hito»: uno cada tres incrementos cerrados); el consumo de cada etapa se anota en
`docs/MEMORIA.md` §Consumo.

**4. Revisión:** revisor funcional en **modo adopción, alcance Fase 2**: el validador de abajo y
la **síntesis contra sus fuentes** (encuadre e informes de línea base).

**Validador de la Fase 2 (PASA/FALLA):**
- [ ] Informes de línea base en `contexto/exploracion/`, acotados a lo no resuelto por la Fase 1,
  con el consumo de cada etapa registrado.
- [ ] Cotejo de inventario: cada ID de origen (`H#`, `LB-*`) tiene destino explícito; ninguno
  desaparece.
- [ ] Cada fila de §Diagnóstico tiene clase, valoración (probabilidad desconocida si no hay datos
  representativos) y decisión; los diferidos dicen por qué pueden esperar y los descartados, por qué.
- [ ] Toda discrepancia con un informe consta en la columna de su valoración, con justificación y
  fuente; las contradicciones con el encuadre se resolvieron contra el código.
- [ ] Bloque de protección mínimo: cada `C#` con un incremento (verificación por sabotaje o
  prueba nueva) en `docs/trazabilidad.md`; ningún incremento de protección sin `C#`.
- [ ] Mejoras separadas, cada una con el riesgo que trata y por qué ahora; línea de corte escrita.
- [ ] Plan de pruebas por incremento; las caracterizaciones marcadas con su hallazgo.
- [ ] Reglas compartidas comprobadas: `AGENTS.md` §1 sin marcadores, hitos en el plan, consumo
  anotado.
- [ ] El plan se defiende en ≤ 10 líneas en el resumen del gate.
- [ ] Nada del producto cambió (`git diff <base>..HEAD` sobre el código).
- [ ] Revisor funcional en PASA y pasada de coherencia anotada en `docs/estado.md`.

**Gate de la Fase 2:** la persona elige la ruta: **mejorar ahora** (protección + mejoras
aprobadas) o **proteger, cerrar el ciclo y seguir con funcionalidad nueva** por reentrada
(recomendado: cerrar deja una línea base verificada antes de cambiar nada).
