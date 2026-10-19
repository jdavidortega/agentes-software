# Encuadre: contexto y objetivos

> Fase 1 — Encuadre. **No se llena desde cero:** se construye a partir de las entradas
> ingeridas de `contexto/` (ver `docs/arranque.md`, Fase 1). El agente arma un borrador
> y aquí se **revisa y completa** con la persona, cerrando los huecos. Debe quedar
> listo ANTES de diseñar.
>
> **Marca el origen de cada dato:** `[de contexto/]` (extraído de una entrada: di
> cuál), `[inferido]` (deducido por el agente — hay que confirmarlo) o `[FALTA]` (hueco
> pendiente). No se avanza con `[FALTA]` ni `[inferido]` sin confirmar.

## Contexto
<!-- ¿Por qué existe este proyecto? ¿Qué problema o necesidad lo origina? -->


## Objetivos
<!-- Qué debe lograr. Concreto y verificable. -->
-

## No-objetivos (explícito)
<!-- Qué queda FUERA de alcance a propósito. Tu primer freno al sobredimensionamiento. -->
-

## Criterios de éxito
<!-- ¿Cómo sabremos que está terminado y bien hecho? Medibles si es posible.
Da a cada criterio un ID (C1, C2…) para enlazarlo en docs/trazabilidad.md. -->
- C1:

## Set de oro (ejemplos de salida esperada)
<!-- 5–10 pares `entrada → salida esperada` que definan la CALIDAD aceptable, no
solo la funcionalidad. Funcionar ≠ salir bien (p. ej. "responde citando la fuente"
Y "respuesta concisa y enfocada"). Ancla la UX desde el inicio y es el set contra
el que se valida. Usa muestras reales cuando existan.
OBLIGATORIO: incluye al menos un EJEMPLO CONCRETO de entrada y de salida (no basta
describir el formato). Puede ir inline aquí, o como archivo referenciado en contexto/ si el ejemplo es
grande; en ese caso enlaza el archivo. Las muestras de salida inventariadas en
§Entradas y salidas son candidatas directas a estos pares. -->
- Entrada: _…_ → Salida esperada: _…_

## Entradas y salidas
<!-- OBLIGATORIO en el encuadre. Todo proceso de software tiene entradas y salidas (una
o varias): archivos, tablas, respuestas de API, eventos, pantallas, artefactos
generados. Una fila por cada una. Para un sistema con varias piezas (back, base de
datos, front) inventaría las de cada frontera que el sistema expone o consume, no las
internas. Cada fila cita su MUESTRA REAL en contexto/ (o el acceso con el que se
obtuvo) y si se validó contra ella; si aún no existe insumo real, aplica la regla de
tres casos de docs/arranque.md: bosquejo del modelo de datos validado con la persona y
supuesto con validación diferida al primer insumo real. El revisor funcional contrasta
esta tabla contra contexto/: una entrada sin muestra ni bosquejo es un vacío R-E.n. -->

| E/S | Nombre | Origen / consumidor | Formato | Muestra en `contexto/` o acceso | Validada |
|-----|--------|---------------------|---------|----------------------------------|----------|
| Entrada | _…_ | _quién la produce_ | _…_ | _`contexto/…`_ | sí / no / `[supuesto]` diferido |
| Salida | _…_ | _quién la consume_ | _…_ | _`contexto/…` o ejemplo en el set de oro_ | sí / no / `[supuesto]` diferido |

<!-- Las discrepancias entre la muestra y lo que decía el spec son HALLAZGOS (regístralos
en §Contexto); solo si fuerzan una elección, ADR. Las salidas inventariadas aquí deben
aparecer en el set de oro con al menos un ejemplo concreto. -->

## Restricciones
<!-- Tiempo, stack, compatibilidad, recursos, dependencias forzadas. -->
-

## Stack y arquitectura
<!-- OBLIGATORIO en el encuadre. PRIMERO búscalo en contexto/ (ahí está la definición de
requisitos): si está ahí, extráelo aquí. Si NO está, PREGÚNTALO con base en el
contexto (propón opciones razonables para este proyecto, con recomendación). NO asumas
un default (ni Python ni nada). Si hay más de una opción, debátela y regístrala como
ADR. Debe quedar resuelto ANTES del diseño (Fase 2) porque condiciona el plan. Verifica
versiones contra la doc oficial vigente. El detalle operativo (comandos) va a
docs/convenciones.md; aquí queda la decisión de encuadre. -->
- Lenguaje + versión: <!-- p. ej. Java 21 -->
- Framework + versión: <!-- p. ej. Spring Boot 3.5.14 -->
- Build / herramientas + versión: <!-- p. ej. Gradle 8.14.5 -->
- Estilo de arquitectura: <!-- p. ej. hexagonal, capas, microservicio… -->
- ¿Restricción dada o decisión abierta?: <!-- si abierta → ADR antes del diseño (Fase 2) -->

## Modelo de despliegue
<!-- DOS PREGUNTAS OBLIGATORIAS del encuadre (no las asumas):
1. DESTINO: ¿la solución requiere despliegue remoto (servidor/nube/on-prem que otros
   usan) o solo corre local? El despliegue LOCAL siempre existe: ahí se desarrolla y
   se valida todo. Si hay remoto, se trata como producción: todo cambio se prueba en
   local ANTES, y llegar al remoto pasa por la rebanada de Operación/Despliegue con
   plan que protege lo desplegado (.claude/skills/desplegando-a-produccion/SKILL.md).
2. EMPAQUETADO: ¿contenedor (Docker/compose), host directo o serverless? Contenedor
   es el default recomendado (aislamiento y paridad dev/prod); desviarse lleva razón
   registrada (ADR si hubo opciones).
Condiciona rutas, paridad dev/prod y el bucle de cambios: se decide ANTES del diseño.
Los detalles concretos van luego a docs/convenciones.md. -->
- Destino: <!-- solo local | local + remoto (¿dónde?) -->
- Empaquetado: <!-- contenedor (recomendado) | host directo | serverless -->

## Stakeholders / usuarios
<!-- ¿Para quién es esto? ¿Quién decide? -->
-
