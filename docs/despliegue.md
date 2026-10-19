# Despliegue y operación (runbook vivo)

> El **cómo se corre, se despliega, se verifica y se revierte** este sistema, escrito para
> alguien que no estuvo en el proyecto. Nace en el **Encuadre** (cuando se decide el modelo
> de despliegue: destino y empaquetado) con lo local, y se completa en la **rebanada de
> Operación/Despliegue** (`AGENTS.md` §2; procedimiento en
> `.claude/skills/desplegando-a-produccion/SKILL.md`). Es **lectura obligatoria** antes de
> cualquier trabajo que toque producción y en toda reentrada que lo haga. Las pruebas que
> el agente hace en local **no sustituyen** lo que aquí dice sobre producción.
>
> **Nunca contiene valores de secretos**: dice **dónde viven** (gestor, variable, cuenta)
> y quién tiene acceso. Un valor real aquí es un incidente (rótalo).
> Lección de origen: al desplegar no se recordaba cómo probar, dónde estaba el código, qué
> base de datos ni dónde estaban las credenciales. Este archivo existe para eso.

## Modelo de despliegue (decidido en el encuadre)

- **Destino:** _solo local | local + remoto (dónde: servidor / nube / on-prem)_
- **Empaquetado:** _contenedor (Docker/compose) | host directo | serverless_
- **ADR que lo decidió:** _título_

## Dónde está cada cosa

| Pieza | Dónde | Acceso / responsable |
|-------|-------|----------------------|
| Código (repo, rama de producción) | _URL del remoto, rama_ | _…_ |
| Entorno de prueba | _host / proyecto / URL_ | _…_ |
| Producción | _host / proyecto / URL_ | _…_ |
| Base de datos / almacenamiento | _motor, instancia, nombre; esquema en …_ | _…_ |
| Servicios externos (APIs, colas) | _cuáles, entorno de prueba vs producción_ | _…_ |
| Credenciales y secretos (**solo dónde viven**) | _gestor / `.env` del host / variables del proveedor_ | _quién puede leerlos_ |
| Logs y métricas | _dónde se consultan, retención_ | _…_ |
| Respaldos | _qué, dónde, con qué frecuencia, cómo se restaura_ | _…_ |

## Cómo se ejecuta en local

<!-- Los comandos exactos de docs/convenciones.md §Comandos clave (no los dupliques con
variantes: cópialos o referencia). Incluye cómo cargar datos de prueba y cómo saber que
está arriba (chequeo de salud: que el recurso SIRVE, no solo que existe). -->
- Levantar: _…_
- Datos de prueba: _…_
- Verificar que está arriba: _…_

## Cómo se despliega (runbook, verificado contra el entorno real)

<!-- Un paso por línea, ejecutable tal cual, con el resumen de impacto que el script
muestra antes de actuar (--confirm-prod). Cada paso cotejado en el entorno de destino,
no de memoria. Antes de tocar producción: pruebas en local, luego en el entorno de
prueba con OK de la persona, luego respaldo verificado. -->
1. _Precondiciones (remoto al día, suite verde, respaldo verificado del …)_
2. _…_
3. _Verificación post-despliegue: qué se comprueba y cómo (comando / URL / consulta)_

## Cómo se verifica en producción

<!-- Pruebas adicionales a las de local: el camino principal end-to-end con datos reales,
el chequeo de salud, qué mirar en los logs los primeros minutos. -->
- _…_

## Cómo se revierte

<!-- Plan de reversión escrito ANTES de desplegar: qué se despliega de vuelta, cómo se
restaura el respaldo, cuánto tarda, quién decide. -->
- _…_

## Operación diaria y detalles que se olvidan

<!-- Tareas periódicas, rotación de logs/secretos, límites del proveedor, cosas que
costaron horas la última vez (montajes, --build, rutas del host vs del contenedor…). -->
- _…_

## Historial de despliegues

| Fecha (UTC) | Qué se desplegó (commit/incremento) | Entorno | Resultado | Reversión necesaria |
|-------------|-------------------------------------|---------|-----------|---------------------|
| _…_ | _…_ | _…_ | _…_ | _…_ |
