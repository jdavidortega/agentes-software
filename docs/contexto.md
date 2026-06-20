# Contexto y objetivos

> Fase 1 — Encuadre. Completa esto ANTES de diseñar nada. Es el primer gate.

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
describir el formato). Puede ir inline aquí, o como archivo referenciado (p. ej. en
analisis/ o material/) si el ejemplo es grande; en ese caso enlaza el archivo. Los
datos de salida que existan en analisis/ son candidatos directos a estos pares. -->
- Entrada: _…_ → Salida esperada: _…_

## Restricciones
<!-- Tiempo, stack, compatibilidad, recursos, dependencias forzadas. -->
-

## Stack y arquitectura
<!-- OBLIGATORIO en el encuadre. PRIMERO búscalo en material/ (es la definición de
requisitos): si está ahí, extráelo aquí. Si NO está, PREGÚNTALO con base en el
contexto (propón opciones razonables para este proyecto, con recomendación). NO asumas
un default (ni Python ni nada). Si hay más de una opción, debátela y regístrala como
ADR. Debe quedar resuelto ANTES del diseño (Paso 3) porque condiciona el plan. Verifica
versiones contra la doc oficial vigente. El detalle operativo (comandos) va a
docs/convenciones.md; aquí queda la decisión de encuadre. -->
- Lenguaje + versión: <!-- p. ej. Java 21 -->
- Framework + versión: <!-- p. ej. Spring Boot 3.5.14 -->
- Build / herramientas + versión: <!-- p. ej. Gradle 8.14.5 -->
- Estilo de arquitectura: <!-- p. ej. hexagonal, capas, microservicio… -->
- ¿Restricción dada o decisión abierta?: <!-- si abierta → ADR antes del Paso 3 -->

## Modelo de despliegue
<!-- PREGUNTA OBLIGATORIA del encuadre: ¿cómo se va a desplegar y empaquetar?
contenedor (Docker/compose), host directo, serverless… Condiciona rutas, paridad
dev/prod y el bucle de cambios, así que se decide ANTES del diseño. Los detalles
concretos van luego a docs/convenciones.md. -->
-

## Stakeholders / usuarios
<!-- ¿Para quién es esto? ¿Quién decide? -->
-
