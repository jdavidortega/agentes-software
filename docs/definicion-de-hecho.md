# Definición de Hecho (Definition of Done)

> La compuerta de calidad. Adáptala a tu proyecto. Se usa en **dos momentos**:
> **(1) por incremento** (Fase 3): cada pieza la cumple al construirla; **(2) sobre el
> conjunto** (Fase 4 y cada hito): el sistema ensamblado la cumple a la vez, integrado y
> sobre datos reales (end-to-end), sin regresiones —en un **hito**, sobre el **alcance del
> hito** (lo construido hasta ahí y sus interacciones; los criterios de incrementos futuros
> se excluyen por nombre), en la Fase 4 sobre todo—, con **pasada del juez de conjunto**
> y **mutation testing informativo** (los mutantes sobrevivientes del camino crítico se
> tratan como hallazgos del juez; ver `.claude/skills/probando-con-datos-reales/SKILL.md`).
>
> Tiene **dos listas en orden**, para que nadie tenga que aprobar antes de tener evidencia
> ni commitear antes de la revisión: **A** es lo que el juez verifica **antes del commit**;
> **B** es lo que el principal hace **después del PASA** para cerrar el incremento. Regla
> del orden: **todo lo revisable queda escrito antes de pedir el PASA** (código, docs,
> bitácora del incremento ya colapsada a una línea, README); después del PASA solo se
> tocan los **registros** fuera de la huella (`revisiones.log`, `trazabilidad.md`,
> `estado.md`, `MEMORIA.md`). Si algo revisable cambia después, el recibo caduca y la
> revisión se repite; eso no es un defecto del control, es su razón de ser.
>
> **Si el conjunto NO cumple (Fase 4):** vuelve atrás según la causa. Defecto o
> cobertura faltante (requisitos correctos) → Fase 3, incremento de corrección.
> Encuadre erróneo o requisito nuevo (cambian criterios o set de oro) → Fase 1,
> ajustar `docs/encuadre.md` + ADR + re-revisión funcional. Una mejora más allá de lo
> acordado no es falla: va al backlog de `docs/plan.md`.

## A. Listo para commit (lo verifica el juez; todo binario)

- [ ] Cumple los criterios de éxito **y el set de oro** de `docs/encuadre.md` (no
  solo "funciona": la salida tiene la calidad esperada).
- [ ] **Las pruebas son las del plan de pruebas** del incremento (`docs/plan.md` §Plan de
  pruebas) y pasan: ≥1 flujo end-to-end por criterio que el incremento cubre, unitarios
  solo donde el flujo no llega, los pares del set de oro automatizables como regresión,
  y **ninguna que no pueda fallar ni que duplique otra** (el exceso de pruebas es
  hallazgo, no mérito; ver `.claude/skills/probando-con-datos-reales/SKILL.md`).
- [ ] **Cada garantía nueva fue saboteada en una copia** y la suite se puso en rojo
  (`.claude/skills/verificando-por-sabotaje/SKILL.md`, exit 0): una garantía que ninguna
  prueba puede romper es un comentario.
- [ ] **Tests herméticos:** ninguna prueba depende de config de entorno (`.env`) ni
  llama a servicios externos; lo externo se inyecta o se mockea.
- [ ] **El camino principal está en la suite:** si el camino real depende de un
  servicio externo (LLM, API), se cubre con fixtures/grabación; el camino degradado
  también se prueba, pero **nunca en sustitución** del principal.
- [ ] **Sin secretos ni config quemada.** *Si el proyecto maneja secretos o config de
  entorno*, van a `.env` (no versionado) + `.env.example`; **si no los maneja, no se crea
  `.env` por defecto**. Nunca credenciales/rutas quemadas en el código.
- [ ] **Pasada de seguridad, si el incremento toca superficie de riesgo** (entrada no
  confiable, authn/authz, secretos, persistencia, IaC/despliegue, IA/LLM): hecha, con
  sus hallazgos `R-S#.n` cerrados y su recibo en `docs/revisiones.log`
  (`.claude/skills/revision-seguridad/SKILL.md`). Si no la toca, el juez lo hace constar
  con `seguridad=no-aplica` en su recibo.
- [ ] **Verificación con datos reales y sobre lo generado:** si el incremento toca
  datos o salida, se verificó de forma exploratoria sobre insumos reales
  representativos, no solo fixtures sintéticos; y **lo generado se abre y examina**
  (datos y funcionalidad nueva) contra su criterio y su par del set de oro — tests
  verdes no sustituyen mirar lo producido. Si toca el despliegue, además una prueba
  **end-to-end en las condiciones reales del modelo elegido** (empaquetado y datos de
  producción), siguiendo `docs/despliegue.md` y
  `.claude/skills/desplegando-a-produccion/SKILL.md`.
- [ ] **Sin rutas al `cwd`:** todo recurso (datos, `.env`, índices/bases) se ancla a
  la raíz del proyecto o a una ruta de entorno explícita; ninguna ruta depende del
  directorio desde el que se ejecuta.
- [ ] **Recursos usables, no solo presentes:** los chequeos de salud validan que el
  recurso sirve (legible, esquema correcto), no solo que existe.
- [ ] **Interfaces públicas documentadas** (endpoints, funciones exportadas, CLI),
  completa pero concisa: propósito en una frase, entradas/salidas y su forma,
  errores/casos especiales, y un ejemplo. APIs: `summary` + `description` + `tags` +
  ejemplos en el esquema. Funciones: docstring con el contrato. Prueba: si hay que
  leer la implementación para invocarla, está incompleta; si repite el código línea
  a línea, está inflada.
- [ ] **Estilo y clean — base, no negociable:** nombres **idiomáticos y consistentes** del
  lenguaje, **código en inglés ASCII** (identificadores y comentarios, sin acentos),
  funciones cohesionadas, comentarios solo donde aportan (el porqué o una restricción,
  no narrar el qué línea a línea), sin duplicación ni código muerto; **lint y formatter
  pasan** (`scripts/check.sh`). El código es legible y sigue `docs/convenciones.md`.
- [ ] No se agregaron dependencias ni abstracciones nuevas sin aprobación.
- [ ] **El lenguaje/stack usado es el de `docs/encuadre.md`** (no se coló otro por inercia).
- [ ] No quedó código muerto, TODOs sin registrar, ni "por si acaso".
- [ ] Las decisiones relevantes están en `docs/decisiones.md`.
- [ ] `README.md` actualizado si el incremento cambia comportamiento, interfaz o
  comandos (formato: `.claude/skills/escribiendo-readme/SKILL.md`); el juez lo revisa
  como dimensión.

## B. Cierre del incremento (lo hace el principal tras el PASA del juez)

- [ ] **Rastro de la revisión registrado** tal cual lo trajo el juez: recibo al final de
  `docs/revisiones.log` (append-only, también con PASA limpio) y filas en
  `docs/trazabilidad.md`; los
  bloqueantes resueltos están en `resuelto` con su mutación escrita (pasan a `verificado`
  por un revisor independiente antes de la salida de la Fase 3; `AGENTS.md` §2).
- [ ] **Registros del cierre** (todos fuera de la huella): `docs/estado.md` regenerado
  (fase, `C#` con alias y estado, hallazgos abiertos, **pendiente** y próximo paso);
  hallazgos `verificado` archivados en el Histórico de `docs/trazabilidad.md`; **línea de
  consumo** en `docs/MEMORIA.md` §Consumo (`scripts/consumo.py`; ver
  `docs/convenciones.md` §Contexto); lecciones y obstáculos en `docs/MEMORIA.md`. La
  bitácora de `docs/plan.md` **no se toca aquí**: su línea del incremento se escribió y
  colapsó antes de pedir el PASA.
- [ ] **Commit enlazado** con `Ref: I#` **siempre** (es lo que exige el recibo del juez
  sobre el código; `Cierra: R-…` se añade cuando además cierra hallazgos, nunca lo sustituye),
  con mensaje concreto y suficiente;
  el `README.md` que cambió va en ese mismo commit.
- [ ] **Gate humano:** la persona recibe el resumen ejecutivo del incremento (`AGENTS.md`
  §2) y revisa el cambio; no se abre el siguiente incremento sin su OK.
- [ ] Al **cierre de cada fase**, además, el `README.md` se verifica contra la realidad del
  código **sin que se lo pidan** (condición (c) del cierre, `AGENTS.md` §2).
