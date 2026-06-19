# agentes-software — Plantilla para desarrollar software con agentes de IA

Estructura base para trabajar con un agente de IA (Claude Code, Codex, Cursor…)
de forma **segura y estructurada** en proyectos de software. No es un proyecto en
sí: es una plantilla que copias a tu proyecto real. El agente la sigue paso a
paso, con una **compuerta humana entre cada fase**, antes de escribir la primera
línea de código.

## Cómo usarla

1. Copia el contenido de este repo a tu nuevo proyecto.
2. Verifica que **git esté configurado**. Se hace un commit por fase/incremento.
3. Pídele al agente que ejecute `docs/arranque.md`. Ese guion te conduce por el
   encuadre, la ingesta de material, el diseño y la validación —con un gate en
   cada paso— **antes de programar**. No saltes el encuadre.
4. Deja tus análisis, datos o documentos de referencia en `material/`. En el Paso
   2 del arranque el agente los lee, te propone a dónde va cada cosa (gate) y los
   rutea a los archivos oficiales (`docs/contexto.md`, `docs/decisiones.md`).

## Las 5 fases (con compuerta humana entre cada una)

1. **Encuadre** — contexto, objetivos, no-objetivos, criterios de éxito, set de
   oro, stack y arquitectura, modelo de despliegue (`docs/contexto.md`).
2. **Diseño / plan** — enfoque mínimo e incrementos (`docs/plan.md`).
3. **Ejecución iterativa** — incrementos pequeños, verificados sobre datos reales,
   con revisión crítica independiente antes de cada commit.
4. **Validación** — `docs/definicion-de-hecho.md`.
5. **Cierre y aprendizaje** — lecciones a `MEMORIA.md`.

## Los mecanismos que la sostienen

- **Compuertas (gates):** tú apruebas explícitamente entre fases. No se avanza sin
  tu OK.
- **Registro de decisiones:** toda decisión con más de una opción razonable queda
  en `docs/decisiones.md` (ADR-lite). Trazabilidad y aprendizaje.
- **Guardas anti-sobredimensionamiento:** complejidad solo cuando se necesita.
  Riesgo típico en software: abstracción prematura y dependencias especulativas.
- **Ciclo de aprendizaje:** `corrección → MEMORIA.md → (si se repite) → skill`.

## Portabilidad: AGENTS.md es el núcleo

`AGENTS.md` contiene todas las instrucciones del proyecto; es la **fuente de
verdad** y el estándar que leen las distintas herramientas. `CLAUDE.md` solo lo
importa (`@AGENTS.md`) más notas propias de Claude Code. Si cambias de
herramienta, te llevas `AGENTS.md` y funciona.

> Una regla en `AGENTS.md` moldea el comportamiento del agente pero no lo
> garantiza. Lo que no puede fallar (tests obligatorios, escaneos) va en
> CI / pre-commit / hooks.

## Estructura

```
.
├── AGENTS.md            instrucciones del proyecto (canónico)
├── CLAUDE.md            importa AGENTS.md + notas de Claude Code
├── README.md            este archivo
├── MEMORIA.md           lecciones del proyecto
├── docs/
│   ├── arranque.md          guion de arranque (primer punto de entrada)
│   ├── contexto.md          encuadre + set de oro + stack/arquitectura
│   ├── plan.md              plan vivo + bitácora + backlog
│   ├── trazabilidad.md      hilo criterios ↔ incrementos ↔ hallazgos
│   ├── decisiones.md        ADR-lite
│   ├── convenciones.md      cómo hacemos las cosas aquí
│   └── definicion-de-hecho.md
├── analisis/            notebooks y validación exploratoria
├── material/            entrada de ingesta de contexto
├── skills/              procedimientos reutilizables (incluye revisión crítica)
├── .env.example         variables de entorno documentadas (sin valores)
└── .gitignore
```

---

> **Al iniciar tu proyecto real**, reemplaza el contenido de arriba por el README
> de tu proyecto: descripción, estructura, entradas/salidas y cómo ejecutarlo. Lo
> sustantivo (objetivos, criterios, stack) vive en `docs/contexto.md`.
