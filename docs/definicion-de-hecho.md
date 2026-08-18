# Definición de Hecho (Definition of Done)

> La compuerta de calidad. Adáptala a tu proyecto. Se usa en **dos momentos**:
> **(1) por incremento** (Fase 3): cada pieza la cumple al construirla, antes del
> commit; **(2) sobre el conjunto** (Fase 4): el sistema ensamblado la cumple a la
> vez, integrado y sobre datos reales (end-to-end), sin regresiones, con **pasada del
> juez sobre el conjunto** (`skills/revision-critica/SKILL.md`) y **mutation testing
> informativo** (los mutantes sobrevivientes del camino crítico se tratan como
> hallazgos del juez; ver `skills/probando-con-datos-reales/SKILL.md`).
>
> **Si el conjunto NO cumple (Fase 4):** vuelve atrás según la causa. Defecto o
> cobertura faltante (requisitos correctos) → Fase 3, incremento de corrección.
> Encuadre erróneo o requisito nuevo (cambian criterios o set de oro) → Fase 1,
> ajustar `docs/contexto.md` + ADR + re-revisión funcional. Una mejora más allá de lo
> acordado no es falla: va al backlog de `docs/plan.md`.

Antes de marcar como terminado:

- [ ] Cumple los criterios de éxito **y el set de oro** de `docs/contexto.md` (no
  solo "funciona": la salida tiene la calidad esperada).
- [ ] Las pruebas pasan (y hay pruebas para lo nuevo). Los pares del **set de oro**
  que el incremento cubra y sean automatizables están como **tests de regresión**
  (según lo decidido en el diseño).
- [ ] **Tests herméticos:** ninguna prueba depende de config de entorno (`.env`) ni
  llama a servicios externos; lo externo se inyecta o se mockea.
- [ ] **El camino principal está en la suite:** si el camino real depende de un
  servicio externo (LLM, API), se cubre con fixtures/grabación; el camino degradado
  también se prueba, pero **nunca en sustitución** del principal (ver
  `skills/probando-con-datos-reales/SKILL.md`).
- [ ] **Sin secretos ni config quemada.** *Si el proyecto maneja secretos o config de
  entorno*, van a `.env` (no versionado) + `.env.example`; **si no los maneja, no se crea
  `.env` por defecto**. Nunca credenciales/rutas quemadas en el código.
- [ ] **Verificación con datos reales:** si el incremento toca datos o salida, se
  verificó de forma exploratoria sobre insumos reales representativos, no solo
  fixtures sintéticos. Si toca el despliegue, además una prueba **end-to-end en las
  condiciones reales del modelo elegido** (empaquetado y datos de producción), no
  solo en local (ver `skills/desplegando-a-produccion/SKILL.md`).
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
  no narrar el qué línea a línea), sin duplicación ni código muerto; **lint y formatter pasan**
  (`scripts/check.sh`). El código es legible y sigue `docs/convenciones.md`.
- [ ] No se agregaron dependencias ni abstracciones nuevas sin aprobación.
- [ ] **El lenguaje/stack usado es el de `docs/contexto.md`** (no se coló otro por inercia).
- [ ] No quedó código muerto, TODOs sin registrar, ni "por si acaso".
- [ ] Las decisiones relevantes están en `docs/decisiones.md`.
- [ ] `README.md` actualizado **en el mismo commit** que cambia comportamiento,
  interfaz o comandos (formato: `skills/escribiendo-readme/SKILL.md`). Al **cierre de cada
  fase** el agente lo verifica además contra la realidad del código **sin que se lo
  pidan** (condición (c) del cierre, `AGENTS.md` §2). El juez lo revisa como dimensión.
- [ ] **Compactación del cierre:** `docs/estado.md` regenerado (fase, `C#` con alias y
  estado, hallazgos abiertos, próximo paso); bitácora de incrementos cerrados
  colapsada a una línea; hallazgos `verificado` archivados en el Histórico de
  `docs/trazabilidad.md`.
- [ ] **Commit de la fase/incremento** hecho, con mensaje concreto y suficiente.
- [ ] Hay revisión humana del cambio.
- [ ] Las lecciones, si las hubo, están en `docs/MEMORIA.md`.
