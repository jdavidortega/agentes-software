---
name: desplegando-a-produccion
description: "Procedimiento de la rebanada de Operación/Despliegue: réplica local del entorno, pruebas exhaustivas en local antes de tocar producción, entorno de prueba con OK de la persona, respaldo verificado antes de cualquier operación destructiva, runbook, --confirm-prod y plan de reversión escrito; más la sección del modelo elegido en references/ (contenedores, host directo, serverless). Úsala en cualquier trabajo que impacte producción —primer despliegue, cambios sobre un sistema vivo, migración, config o secretos— y al diseñar el plan de despliegue. Exige autorización explícita y puntual de la persona."
---
# Skill: Desplegando a producción

> El **cómo** de la rebanada de Operación/Despliegue (`AGENTS.md` §2). El despliegue
> **local** siempre existe (ahí se desarrolla y valida); esta rebanada gobierna el
> **remoto**, que se trata como producción desde el primer día. Se activa con
> cualquier trabajo que impacte producción —deploy, migración, config, secretos—,
> **sea cual sea el modelo de despliegue** que el encuadre decidió. Lee el **núcleo
> común** + **solo la sección de tu modelo** (contenedores / host directo /
> serverless); no cargues las otras.

## Cuándo usarla

- Al abrir la rebanada de Operación/Despliegue (primer despliegue, o cambios sobre
  un sistema ya en producción).
- Antes de cualquier migración o cambio de datos en un entorno real.
- Al diseñar el plan de despliegue (que es parte de esta rebanada, con juez y gate).

## Núcleo común (todo modelo)

1. **Réplica local del entorno primero.** Mismo SO base que producción (un pipeline
   que solo corre en el SO del desarrollador no es re-ejecutable en el servidor),
   misma configuración, datos representativos **sanitizados**.
2. **Pruebas exhaustivas en local, siempre antes** de tocar producción.
3. **Con servicios o bases de datos reales: entorno de prueba obligatorio.** Todo se
   prueba primero ahí y **la persona valida los resultados en ese entorno**; nunca se
   prueba contra producción. Solo con ese OK se diseña el plan de despliegue.
4. **El plan de despliegue protege los datos de producción:** respaldo **verificado**
   (restaurable de verdad, no solo existente) antes de cualquier operación
   destructiva (DELETE/DROP/migraciones); las migraciones se ensayan sobre una copia
   de datos reales en el entorno de prueba; ninguna operación que borre datos corre
   sin plan de reversión probado.
5. **Runbook verificado contra el entorno real**, no contra la memoria: cada paso
   ejecutado o cotejado en el entorno de destino. **Vive en `docs/despliegue.md`** (dónde
   está cada cosa, cómo se despliega, cómo se verifica en producción, cómo se revierte,
   historial): lo que no está escrito ahí se olvida para el siguiente despliegue.
6. **`--confirm-prod`:** los scripts de despliegue exigen un flag explícito de
   confirmación y muestran un **resumen de lo que van a impactar** antes de actuar.
   Además, la autorización de la persona es **en ese momento**, no heredada
   (`AGENTS.md` §3).
7. **Plan de reversión escrito antes** de aplicar cualquier downgrade consciente — y
   la reversión futura queda **en el backlog** de `docs/plan.md`, no solo en las
   Consecuencias del ADR.
8. **Secretos solo por entorno**, nunca en bundles ni en el repo; uno expuesto se
   **rota**. El repo tiene **remoto** desde el Bootstrap: el ensamblado se reconstruye
   desde él, nunca desde un bundle generado en producción.

## Sección del modelo de despliegue (lee solo la tuya)

El modelo lo decidió el encuadre (`docs/encuadre.md`). Abre **una** de estas y no las
otras: cargar las tres es gastar contexto en lo que no aplica.

- Contenedores (Docker/compose) → `references/contenedores.md`
- Host directo (systemd/supervisor) → `references/host-directo.md`
- Serverless (funciones gestionadas) → `references/serverless.md`

> Host y serverless nacen mínimas a propósito: crecen con las lecciones de proyectos
> reales, igual que la de contenedores creció con las suyas.

## Notas / trampas

- **El servidor no es la fuente de verdad de la integración:** el ensamblado se
  reconstruye desde los repos (con remoto), no desde un bundle generado en
  producción con secretos adentro.
- Chequeos de salud que validan **existencia** y no **usabilidad** mienten
  (`docs/convenciones.md` §Robustez operativa).
- Esta rebanada tiene juez y bitácora como cualquier otra: el trabajo de mayor
  riesgo es justo el que no puede quedar fuera del método (lección: los ADR de
  despliegue registrados sin bitácora, sin juez y sin criterio).
