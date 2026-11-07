# Ejemplo completo de un ciclo

Un proyecto pequeño —resumir por categoría un CSV de gastos— recorrido de punta a punta con los
controles reales del método: entrada y encuadre, plan y trazabilidad, tres incrementos con su recibo, un
hito, la validación y el cierre. Sirve para **ver** el procedimiento; las reglas están en sus fuentes
canónicas, que este ejemplo enlaza y no repite.

**Qué no es.** Los recibos de revisión son **sintéticos** (`ejecutor=ejemplo-sintetico`): los genera
`scripts/recibos.sh` con la huella real, así que su formato y su vigencia son los del método, pero ningún
revisor revisó nada. Un recibo válido no demuestra que una revisión ocurriera (`AGENTS.md` §9). Las
aprobaciones de la persona tampoco existen: cada gate queda señalado en `docs/estado.md` y en el
mensaje, «simulado». No demuestra el comportamiento de un agente.

Esta carpeta no viaja a los proyectos: `.gitattributes` la excluye de `git archive` (proyecto nuevo) y
no está en el conjunto de `scripts/adoptar.sh` (adopción).

## Cómo reproducirlo

Desde una copia limpia de la plantilla (sin cambios sin commitear), con los requisitos del
`README.md` §Cómo usarla; sin red, credenciales ni instalaciones:

```sh
sh ejemplo/generar.sh /ruta/a/una/carpeta-nueva
cd /ruta/a/una/carpeta-nueva
git log --stat --reverse          # la historia, un commit por paso
git show <commit>                 # qué cambió en cada paso
```

El script se niega si la carpeta ya existe. Instala la plantilla con la receta del README, recorre el
ciclo con los hooks activos (`.githooks/commit-msg` y `pre-commit` aceptan cada commit) y termina
reejecutando el contrato sobre toda la historia (`scripts/pruebas/validar_historial.sh`), el doctor
(`scripts/check_docs.sh`) y el parser de recibos. Las fechas de los recibos son las de la ejecución, así
que los hashes cambian de una generación a otra; la secuencia y los controles, no.

## Qué contiene cada paso

| Paso | Commit | Qué se escribe | Fuente canónica |
|---|---|---|---|
| Instalación y Bootstrap | (en el primer commit) | La plantilla del commit capturado una sola vez, hooks activos y la «Plantilla de origen» en `docs/convenciones.md` §Git | `README.md` §Cómo usarla; `docs/arranque.md` Paso 0 |
| Gate de completitud | `Ref: F1` | Las entradas en `contexto/` (`entrada/`) y `estado.md` en F1 | `docs/arranque.md` §Fase 1 a, «Gates intermedios del arranque» |
| Gate de ruteo | `Ref: F1` | La propuesta en `contexto/exploracion/ruteo.md`; nada en los documentos oficiales | `docs/arranque.md` §Fase 1 b |
| Encuadre | `Ref: F1` | `docs/encuadre.md` y ADR-001 (`pasos/f1/`), manifiesto de `contexto/README.md`, `AGENTS.md` §1 | `docs/arranque.md` §Fase 1 · Encuadre; contrato del set de oro en `docs/encuadre.md`; `docs/decisiones.md` «Aceptación» |
| Plan | `Ref: F2` + recibo del revisor funcional | `docs/plan.md`, `docs/trazabilidad.md`, `scripts/check.sh` y el README del producto (`pasos/f2/`) | `docs/arranque.md` §Fase 2; `docs/convenciones.md` §Comandos clave; `.claude/skills/escribiendo-readme/SKILL.md` |
| I1, I2, I3 | `Ref: I<n>` + recibo del juez de código | Código y pruebas (`pasos/i<n>/`); casilla `[x]` y bitácora antes del recibo; criterio `verificado` y `estado.md` después | `docs/definicion-de-hecho.md`; `.claude/skills/dirigiendo-revisiones/SKILL.md` |
| Hito I1–I3 | `Ref: hito:I1-I3` + recibo del juez de conjunto | Solo registros | `AGENTS.md` §2 (Fase 4, «también por hito»); gramática del recibo en `scripts/recibos.sh` |
| Validación | `Ref: F4` + recibo del juez de conjunto | Solo registros | `AGENTS.md` §2 (Fase 4); `docs/definicion-de-hecho.md` |
| Cierre | `Ref: F5` | `estado.md` en F5 y una lección en `docs/MEMORIA.md` | `AGENTS.md` §2 (Fase 5) |

`generar.sh` comenta cada paso; los textos que escribe están en `entrada/` y `pasos/`.

## Qué queda fuera, a propósito

- Revisiones reales, hallazgos, un FALLA y su repasada, sabotajes y mutation testing: los casos de
  rechazo y aceptación de cada control están en `scripts/pruebas/regresion.sh`.
- Seguridad, despliegue y reentrada: el producto no tiene superficie de riesgo ni destino remoto.
- La línea de consumo de `docs/MEMORIA.md` §Consumo: no hubo sesiones que medir.
