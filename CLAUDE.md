# CLAUDE.md

> Las instrucciones canónicas viven en AGENTS.md. Este archivo solo las importa
> para que Claude Code las lea, más cualquier nota específica de Claude.

@AGENTS.md

## Notas específicas de Claude Code

<!--
Aquí, y SOLO aquí, va lo que es propio de Claude Code (no portable):
- Comandos slash personalizados
- Hooks (PreToolUse, etc.) para reglas que no pueden fallar
- Cualquier preferencia de Claude que no aplique a otras herramientas

Todo lo común al proyecto va en AGENTS.md, no aquí.
-->

- **Roles como agentes declarados:** revisor funcional, juez de código (incrementos),
  juez de conjunto (Fase 4) y juez de seguridad viven en `.claude/agents/` (contexto
  propio, herramientas acotadas con `tools`, rúbrica precargada con `skills` y **modelo
  por rol**: `sonnet` en las revisiones acotadas; `opus` fijado —no `inherit`— en
  conjunto y seguridad). Al invocar una revisión, usa esos agentes. El «Prompt de
  invocación» de cada SKILL.md queda como fallback portable para herramientas sin
  subagentes declarables (ver `.claude/skills/README.md` §Roles como agentes).
