# Skill: Desplegando a producción

> El **cómo** de la rebanada de Operación/Despliegue (`AGENTS.md` §2). Se activa con
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
   ejecutado o cotejado en el entorno de destino.
6. **`--confirm-prod`:** los scripts de despliegue exigen un flag explícito de
   confirmación y muestran un **resumen de lo que van a impactar** antes de actuar.
   Además, la autorización de la persona es **en ese momento**, no heredada
   (`AGENTS.md` §3).
7. **Plan de reversión escrito antes** de aplicar cualquier downgrade consciente — y
   la reversión futura queda **en el backlog** de `docs/plan.md`, no solo en las
   Consecuencias del ADR.
8. **Secretos solo por entorno**, nunca en bundles ni en el repo; uno expuesto se
   **rota**. Precondición de la rebanada: el repo tiene **remoto** (si venía de una
   PoC sin remoto, se crea aquí, antes que nada).

## Sección · Contenedores (Docker/compose)

- **Tres capas de config que no se mezclan:** host / rutas internas del contenedor /
  app. En `"A:B"`, A=host y B=contenedor; una constante interna del runtime **no se
  expone** en el archivo que el operador edita. Confundirlas costó horas en
  producción (índice vacío, 503).
- **Montaje fantasma:** si el archivo fuente no existe en el host, el bind-mount crea
  una **carpeta vacía** y la monta — síntoma engañoso (`disponible: true` con 500s).
  Monta archivos concretos y valida al arrancar que el insumo es **archivo legible**.
- **Regenera los derivados** (índices, cachés, volúmenes persistentes) tras corregir
  un insumo: no se actualizan solos.
- Runbook verificado con `docker inspect` contenedor por contenedor (montajes,
  puertos, redes) contra lo que el plan dice.
- **`--build` obligatorio al redesplegar:** recrear el contenedor sin reconstruir la
  imagen es la causa clásica de "no veo el cambio".
- En servidor compartido con otros proyectos: puertos y volúmenes **aislados y
  documentados** en el runbook; verificar que no pisas nada ajeno antes de subir.

## Sección · Host directo

- Proceso gestionado (systemd/supervisor), no un `nohup` suelto: arranque al boot,
  reinicio ante caída, logs con rotación.
- Usuario propio con permisos mínimos; nada corre como root sin razón documentada.
- Rutas ancladas (nunca al `cwd`) y dependencias del SO listadas en el runbook con
  versión.
- El comando de arranque de producción es el del stack (`docs/convenciones.md`), no
  una variante artesanal solo del servidor.

## Sección · Serverless

- Límites del proveedor documentados en el runbook (timeout, memoria, tamaño de
  paquete, concurrencia) y verificados contra la doc oficial vigente.
- Variables y secretos por el mecanismo del proveedor, nunca dentro del paquete.
- Probar el **empaquetado real** (el artefacto que se sube) antes de publicar, no
  solo el código en local.

> Las secciones de host y serverless nacen mínimas a propósito: crecen con las
> lecciones de proyectos reales, igual que la de contenedores creció con las suyas.

## Notas / trampas

- **El servidor no es la fuente de verdad de la integración:** el ensamblado se
  reconstruye desde los repos (con remoto), no desde un bundle generado en
  producción con secretos adentro.
- Chequeos de salud que validan **existencia** y no **usabilidad** mienten
  (`docs/convenciones.md` §Robustez operativa).
- Esta rebanada tiene juez y bitácora como cualquier otra: el trabajo de mayor
  riesgo es justo el que no puede quedar fuera del método (lección: los ADR de
  despliegue registrados sin bitácora, sin juez y sin criterio).
