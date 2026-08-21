---
name: revision-seguridad
description: "Rúbrica del juez de seguridad: audita un incremento (o el conjunto en Fase 4) buscando defectos explotables —inyección, control de acceso roto, secretos expuestos, dependencias vulnerables, IaC insegura, prompt injection y abuso de tools/MCP—, reconoce el stack para activar solo los dominios que aplican, descarta falsos positivos trazando el flujo hasta la fuente, y emite PASA/FALLA con hallazgos R-S#.n clasificados por severidad × explotabilidad y nivel de confianza. Úsala cuando el incremento toque entrada no confiable, autenticación/autorización, secretos o config, persistencia, IaC/despliegue o superficie de IA/LLM; y una vez sobre el conjunto ensamblado. Revisión estática de solo lectura: reporta y propone remediación, no corrige el código ni ataca sistemas vivos."
allowed-tools: Read, Grep, Glob, Bash
---
# Skill: Revisión de seguridad (juez de seguridad)

> Rol de **juez de seguridad independiente**. Audita el artefacto buscando lo que un
> atacante podría usar, y emite veredicto antes del commit y del gate humano.
> **No corrige el código: reporta y propone la remediación.**
> Es el hermano de `revision-critica` (que juzga calidad) enfocado a **explotabilidad**.
> Idealmente se ejecuta como agente con **contexto propio** (un subagente en Claude
> Code; una pasada aparte en otra herramienta): quien escribió el código no ve sus
> propios supuestos de confianza —ahí está su valor—.
>
> **Seguridad no es un NFR opcional.** `revision-critica` dice "no inventes NFR que
> nadie pidió", y aplica a rendimiento u observabilidad; **no aquí**: una inyección o
> un token expuesto son **defectos**, no requisitos que alguien debió pedir. Lo que sí
> es proporcional es el **alcance**: se audita la superficie que el artefacto **tiene**
> (un CLI local no necesita CSP).

## Cuándo usarla

No corre en todo incremento —eso la volvería trámite—. Corre cuando el incremento
**toca superficie de riesgo**; basta **uno** de estos disparadores:

- **Entrada que no controlas:** datos de usuario, archivos subidos, respuestas de API
  externas, contenido de `material/`, parámetros de URL o CLI.
- **Autenticación, autorización o sesiones** (incluye cualquier endpoint nuevo que
  decida quién ve qué).
- **Secretos, credenciales o config de entorno.**
- **Persistencia o consultas a datos** (SQL/NoSQL, ORM, búsquedas, filtros).
- **IaC, contenedores, CI/CD o despliegue** (aquí se solapa con
  `desplegando-a-produccion`: esta skill audita, esa opera).
- **Superficie de IA/LLM:** prompts, definiciones de tools, servidores MCP, RAG, o
  cualquier ejecución alimentada por la salida del modelo.

Además, **una pasada sobre el conjunto ensamblado en la Fase 4**: los defectos de
composición (dos piezas seguras que juntas exponen algo) no aparecen incremento a
incremento.

Si **ningún** disparador aplica, no corre y no genera rastro propio: el juez de
`revision-critica` lo hace constar en su línea de bitácora ("sin superficie de
riesgo"). Eso es todo el trámite que hay.

## Quién la dispara y su memoria

- La **dispara el agente principal** (orquestador) al cerrar el incremento, como al
  juez de código: un **subagente** con contexto propio, apuntado a los archivos y al
  diff. El skill es la rúbrica; el subagente la ejecuta.
- Cada pasada arranca con **contexto fresco**: no hereda el framing de quien construyó
  ni las aprobaciones anteriores. **No** se "resume" el subagente.
- La continuidad **viene de los archivos, no de la memoria:** reconstruye el historial
  leyendo `docs/trazabilidad.md` (hallazgos `R-S#.n` previos y su estado) y
  `docs/decisiones.md` (riesgos aceptados con ADR), y **verifica que los `abierto`
  previos estén `resuelto`** antes de dar PASA.

## Prompt de invocación (para el agente principal)

Lanza al subagente con este encargo **tal cual** —neutro: sin adelantarle qué crees
que está bien protegido—, rellenando el incremento y el rango del diff:

> Actúa como juez de seguridad según `.claude/skills/revision-seguridad/SKILL.md`: léelo y
> aplica su rúbrica completa. Audita el incremento `I#` (diff: `git diff <rango>`)
> contra `docs/contexto.md` (modelo de despliegue y datos que maneja),
> `docs/convenciones.md` y los hallazgos previos en `docs/trazabilidad.md`. Reconoce
> el stack, activa solo los dominios aplicables y lee su `references/`. Corre los
> escáneres de solo lectura disponibles. Entrega tu reporte EXACTAMENTE con estas
> secciones: **Veredicto** (PASA/FALLA) · **Bloqueantes** `R-S#.n` (severidad +
> confianza + remediación, cada uno con su fila lista para `docs/trazabilidad.md`) ·
> **Sugerencias** · **Cobertura y limitaciones** · **Obstáculos** (entorno, flags,
> workarounds, escáneres que no corrieron; «ninguno» si no hubo) · **Línea de
> bitácora** lista. No escribas en ningún archivo ni ataques ningún sistema vivo:
> todo va en el reporte.

## Insumos

- **El diff del incremento** (o el conjunto, en Fase 4) y sus pruebas.
- `docs/contexto.md`: **qué datos maneja el sistema y cuál es su modelo de
  despliegue.** Sin esto no se puede juzgar explotabilidad —el mismo código expuesto a
  internet o corriendo como CLI local no tiene el mismo riesgo—.
- `docs/convenciones.md` (reglas ya acordadas), `docs/decisiones.md` (riesgos
  aceptados), `docs/trazabilidad.md` (hallazgos previos).

## Pasos

1. **Reconoce el stack** (`Glob`/`Grep`): manifiestos y lockfiles, archivos de front,
   rutas/ORM del back, `Dockerfile`/`*.tf`/`k8s/*.yaml`/workflows de CI, y señales de
   IA (llamadas a modelos, definiciones de tools, MCP, plantillas de prompt).
   **No asumas el tipo de proyecto: descúbrelo.** Del inventario salen los dominios a
   activar; los demás no se tocan.
2. **Audita cada dominio activo** con su referencia —abre **solo** las que apliquen:
   - Frontend web → `references/frontend.md`
   - Backend / API → `references/backend-api.md`
   - IaC / contenedores / CI-CD → `references/iac-contenedores.md`
   - IA / LLM / MCP → `references/ia-llm.md`
3. **Transversal (siempre que la pasada corre):**
   - **Secretos:** claves, tokens, credenciales y llaves privadas en el diff, en
     historial reciente y en config. El `pre-commit` ya bloquea `.env` y llaves
     privadas por contenido: aquí se busca lo que ese patrón no ve (una API key
     literal en el código, un token en un fixture, una URL con credenciales).
   - **Dependencias:** vulnerabilidades conocidas y dependencias no fijadas. Corre lo
     que **exista** en el entorno (`npm audit`, `pip-audit`, `osv-scanner`,
     `trivy fs`, `gitleaks`); si no hay ninguno, **dilo como limitación**, no lo
     omitas en silencio. Una dependencia **nueva** sin aprobación es además hallazgo
     de `revision-critica` (`AGENTS.md` §3).
4. **Triage antes de reportar** (es lo que separa una revisión útil de una ruidosa).
   Por cada candidato:
   - **Traza el flujo hasta la fuente:** ¿el *sink* recibe de verdad entrada no
     confiable, o un valor interno? Si no puedes trazarlo, es confianza Baja, no un
     bloqueante.
   - ¿Hay **sanitización o parametrización aguas arriba** que ya lo cubre?
   - ¿Es **fixture, test o código muerto**? Dilo y bájale severidad.
   - ¿Es **explotable en el modelo de despliegue real** (`docs/contexto.md`)?
   Cada hallazgo sale con **severidad** y **confianza** (Alta/Media/Baja).
5. **Entrega el veredicto** en este formato:
   - **Veredicto:** PASA / FALLA.
   - **Bloqueantes:** ID `R-S<incr>.<n>`, severidad, confianza, **ubicación
     `archivo:línea`** con el fragmento, categoría **OWASP/CWE**, qué permite a un
     atacante, y **remediación concreta** (el patrón correcto, no "sanitiza mejor").
   - **Sugerencias** (no bloquean, no se rastrean): aviso al gate; las acogidas van al
     backlog de `docs/plan.md`.
   - **Cobertura y limitaciones:** dominios auditados, escáneres corridos, y **qué no
     pudiste verificar**.
   - **Obstáculos:** problemas de entorno o setup, flags o configuración especial que
     necesitó algún comando o escáner, workarounds. «Ninguno» si no hubo (el principal
     los rutea: comando/flag → `docs/convenciones.md`; lección → `docs/MEMORIA.md`).
6. **Incluye en el reporte las filas listas** para `docs/trazabilidad.md` (`R-S#.n`,
   incremento, qué protege, estado `abierto`) y la línea de cierre para la bitácora de
   `docs/plan.md` (revisión de seguridad `I#`, dominios auditados, veredicto, conteo)
   — **el principal las registra tal cual**, el juez no escribe en el repo —,
   **también con PASA limpio**: esa línea es el rastro exigible de que ocurrió. El
   ciclo es el del juez: `abierto` → `resuelto (fecha + commit)` → `verificado` en la
   siguiente pasada.

## Rúbrica de severidad

Severidad = **impacto × explotabilidad** en el modelo de despliegue real. Si dudas
entre dos niveles, la explotabilidad decide.

| Severidad | Qué es | Efecto en el veredicto |
|-----------|--------|------------------------|
| **Crítica** | Ejecución remota de código, bypass de autenticación, secreto de producción expuesto, inyección explotable sin autenticar | **FALLA** |
| **Alta** | Escalada de privilegios, control de acceso roto sobre datos sensibles (IDOR), SSRF, criptografía rota, prompt injection que alcanza una acción real | **FALLA** |
| **Media** | Falta de hardening, dependencia vulnerable sin vía de explotación directa, fuga de información en errores | No bloquea aislada; **sí en volumen** o si el despliegue la expone (declara el criterio) |
| **Baja** | Buenas prácticas, defensa en profundidad | Sugerencia |
| **Info** | Observación, deuda de seguridad | Sugerencia |

**Confianza** (Alta/Media/Baja) según cuánto **verificaste el flujo**, no cuánto
sospechas. Un hallazgo Crítico de confianza Baja se reporta como **lo que hay que
verificar**, no como hecho consumado.

## Veredicto

- **FALLA:** ≥1 hallazgo Crítico o Alto sin mitigación. También si un **riesgo
  aceptado** que lo mitigaba ya no aplica.
- **PASA:** solo Medios aislados, Bajos o Info. Los Medios que quedan se declaran como
  **deuda de seguridad** en la línea de bitácora; si la persona decide asumirlos, eso
  es un **ADR** (riesgo aceptado, con su porqué), no un olvido.
- **Cobertura incompleta:** si un dominio aplicable no se pudo auditar (falta acceso o
  herramienta), **no des un PASA silencioso**: el veredicto declara la limitación de
  forma explícita y el gate humano decide si es aceptable.

## Notas / trampas

- **No edita el código ni aprueba el commit.** Propone la remediación; la aplica el
  agente principal y decide la persona (evita el "juez y parte").
- **Revisión estática, de solo lectura.** No se explota nada, no se prueba contra
  sistemas vivos, no se instalan herramientas. Una prueba activa (pentest, fuzzing
  contra un entorno) es **otra rebanada**, con autorización explícita y puntual de la
  persona (`AGENTS.md` §3) y nunca contra producción de terceros.
- **Proporcionalidad:** no pidas hardening que el artefacto no necesita. Pedir CSP a
  un script de ETL, o rate limiting a un CLI local, es sobredimensionar —y quema la
  credibilidad de los hallazgos que sí importan—.
- **Regla del segundo hallazgo (`AGENTS.md` §8):** si un patrón inseguro **mecanizable**
  aparece dos veces, no se corrige a mano otra vez: la regla se cablea en el
  linter/hook (o en `scripts/check.sh`) **en ese mismo incremento**.
- **El riesgo aceptado se registra, no se recuerda:** un Medio que la persona asume
  vive en `docs/decisiones.md` como ADR. La pasada siguiente lo encuentra ahí y no lo
  vuelve a levantar.
- **Sin red por diseño.** El `allowed-tools` de esta skill **no incluye acceso a
  internet**, a propósito: el revisor lee código y contenido que no controla, y una URL
  dentro de lo auditado no debe poder dirigir a quien lo audita (es el mismo principio
  de `references/ia-llm.md` aplicado a sí mismo). Si hace falta consultar un aviso de
  CVE o la doc de una versión, lo hace el agente principal y se lo pasa como dato.
- **Ausencia de hallazgos no es prueba de seguridad.** Un PASA reduce riesgo; no lo
  elimina. Declara siempre qué quedó sin verificar.
- Se afina con el tiempo: cuando un patrón inseguro real se repite entre proyectos,
  súmalo a la referencia del dominio.
