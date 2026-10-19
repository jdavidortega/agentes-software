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
   **ya colapsada a su línea** (qué cambió y por qué), el `README.md` al día si cambió
   comportamiento, ADRs si hubo decisión. `plan.md` y `convenciones.md` cuentan en la
   huella: después del PASA no se tocan. Lo que sí se escribe después son los
   **registros** fuera de la huella (recibo, filas, `estado.md`, consumo y lecciones en
   `MEMORIA.md`).
2. **Stagea todo** (`git add -A`) y toma las dos huellas: `V0=$(sh scripts/huella.sh)`
   (vigencia: lo revisable) e `I0=$(sh scripts/huella.sh integridad)` (integridad: todo,
   registros incluidos).
3. Decide **qué rol** toca y su **alcance** (`AGENTS.md` §9): encuadre `F2` → revisor
   funcional; incremento `I<n>` → juez de código (+ seguridad si toca superficie de
   riesgo); hito `hito:I<a>-I<b>` → juez de conjunto (+ seguridad); Fase 4 `F4` → juez de
   conjunto (+ seguridad). **Uno a la vez**; nunca con una suite o un sabotaje corriendo.

## Invocación

4. Lanza el agente declarado (`.claude/agents/<rol>.md`) o, sin subagentes, el «Prompt
   de invocación» de su skill. Pásale **solo** qué revisar: rol, alcance, rango del diff
   (`git diff <base>..HEAD` o árbol de trabajo) y los archivos. **No** le resumas tu
   solución ni le adelantes conclusiones.
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
   qué y repítela. **Vigencia:** exige `V0 == huella del recibo`; si difiere, el revisor
   juzgó otra cosa. Ninguna de las dos ve la red ni los archivos ignorados por git.
7. **Registra tal cual, sin editar:** la línea del recibo al final de
   `docs/revisiones.log` (append; nunca se compacta) y las filas de hallazgos en
   `docs/trazabilidad.md` (numeración que continúa, incluido el Histórico). Ambos están
   fuera de la huella, igual que `estado.md` y `MEMORIA.md`: registrarlos no invalida el
   recibo.
8. **Rutea los obstáculos a `docs/MEMORIA.md`** (sección «Operativa») y la línea de
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

## Notas / trampas

- **Seguridad no se olvida por omisión:** el recibo del juez de código y del de conjunto
  declara `seguridad=requerida|no-aplica`; con `requerida`, el hook exige el recibo del
  juez de seguridad del mismo alcance y la misma huella.
- **No edites nunca `docs/revisiones.log` salvo para añadir una línea.** Un recibo
  retocado es la forma más barata de perder el rastro; el hook lo lee, no la persona.
- **El gate humano es aparte:** el recibo prueba que la revisión ocurrió sobre este
  contenido; la aprobación la da la persona en el chat con el resumen ejecutivo
  (`AGENTS.md` §2). No se finge ni se registra en nombre de nadie.
