# Skill: Revisión crítica (agente juez)

> Rol de **juez/revisor independiente**. Verifica de forma crítica cada incremento
> antes del commit y del gate humano. **No construye ni edita el código: reporta.**
> Idealmente se ejecuta como agente con **contexto propio** (un subagente en Claude
> Code; una pasada de revisión aparte en otra herramienta), para no heredar las
> racionalizaciones de quien escribió el código —ahí está su valor.

## Cuándo usarla

- Al cerrar **cada incremento** de la Fase 3, **antes del commit** y antes del gate
  humano.
- (Opcional) una pasada más a fondo en la Fase 4 (Validación).

## Quién la dispara y su memoria

- La **dispara el agente principal** (orquestador): al llegar al cierre del
  incremento, invoca al juez (un **subagente** con contexto propio) y le pasa qué
  revisar, apuntándolo a los archivos y al diff. El skill es la rúbrica; el subagente
  es quien la ejecuta; el principal es quien lo lanza.
- Cada revisión arranca con **contexto fresco** (a propósito: así el juez no se ancla
  ni arrastra aprobaciones previas). **No** se "resume" el subagente.
- La continuidad entre fases **no viene de la memoria, viene de los archivos.** El
  juez reconstruye el historial leyendo `docs/trazabilidad.md` (hallazgos previos y su
  estado) y `docs/decisiones.md`, y **verifica que los hallazgos `abierto` previos
  estén `resuelto`** antes de dar PASA.

## Insumos (el contexto en que se apoya)

- Archivos del proyecto: `docs/contexto.md` (problema + set de oro + criterios `C#`),
  `docs/plan.md` (diseño/arquitectura), `docs/trazabilidad.md` (hallazgos previos y
  estado), `docs/decisiones.md`, `docs/convenciones.md` y `docs/definicion-de-hecho.md`.
- **El diff del incremento** (lo que cambió) y sus pruebas.
- No hereda la memoria de trabajo del constructor: solo archivos + diff.

## Pasos

1. Lee los insumos. Si falta contexto o hay ambigüedad, **pregunta** (no asumas).
2. Evalúa por dimensiones, una a una (rúbrica abajo). Cada dimensión: **PASA/FALLA**
   si es binaria; **observación** si es de criterio.
3. Entrega el veredicto en este formato:
   - **Veredicto:** PASA / FALLA (FALLA si alguna dimensión binaria falla).
   - **Bloqueantes** (binarios): lista; asigna a cada uno un ID `R-I<incr>.<n>` y el
     criterio `C#` que protege; cada uno es una subtarea accionable.
   - **Sugerencias** (criterio, no bloquean): lista breve (aviso al gate, no se rastrean).
   - **Preguntas / dudas:** lo que no pudo verificar.
4. **Registra los bloqueantes en `docs/trazabilidad.md`** (ID, incremento, criterio,
   estado `abierto`) y deja una línea de cierre en la bitácora de `docs/plan.md`
   (revisión I#, veredicto, "ver trazabilidad"). Es la memoria entre fases.
5. El agente principal resuelve los bloqueantes como subtareas; al cerrarlos actualiza
   su estado a `resuelto (fecha + commit)` en `docs/trazabilidad.md` y enlaza el commit
   (`Cierra: R-I#.n`). El juez los marca `verificado` en la siguiente pasada. Solo con
   todo en PASA: commit final del incremento + gate humano.

## Rúbrica (dimensiones)

- **Definición de Hecho:** corre `docs/definicion-de-hecho.md` punto por punto (binario).
- **Consistencia de arquitectura:** el cambio respeta el enfoque/arquitectura de
  `plan.md`; no introduce dependencias ni abstracciones sin ADR.
- **Calidad y concisión:** legible, sin código muerto ni "por si acaso"; hace lo
  mínimo que resuelve el problema (anti-exceso).
- **Documentación:** interfaces públicas documentadas, completa pero concisa (ver DoD).
- **Pruebas:** cada funcionalidad (o apoyo a funcionalidad) tiene una prueba que la
  respalda; tests herméticos. No exige 100% mecánico: cobertura de **comportamiento**.
- **Funcionales:** cumple criterios de éxito y set de oro de `contexto.md`.
- **No funcionales:** solo los acordados en el encuadre (rendimiento, seguridad,
  observabilidad…); no inventes NFR que nadie pidió.

## Notas / trampas

- **No edita el código ni aprueba el commit.** Reporta; deciden el agente principal y
  la persona (evita el "juez y parte").
- **Binario donde se pueda;** lo subjetivo va como sugerencia o pregunta, nunca como
  FALLA silenciosa.
- **No infles:** una sugerencia que no sirve a un criterio acordado es gold-plating.
- Se afina con el tiempo: si una verificación se repite, súmala a la rúbrica.
