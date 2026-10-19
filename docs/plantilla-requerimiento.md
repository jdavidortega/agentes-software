# Plantilla de requerimiento (brief de `contexto/`)

> Formato para escribir un requerimiento como documento de `contexto/`. **No sustituye
> a `docs/encuadre.md`** —la verdad acordada vive allá—: es un insumo de la ingesta; el
> agente lo rutea con las reglas de siempre (`contexto/README.md`). Copia la plantilla
> que toque a `contexto/brief-<tema>.md`:
>
> - **A — inicial:** primer ciclo, aún no hay encuadre.
> - **B — reentrada:** el proyecto ya cerró (Fase 5) y llega trabajo nuevo. En
>   reentrada se ingiere **solo este insumo** (rebanada), no se re-corre la Fase 1.
>   Lo pedido con el plan aún vivo no es reentrada (va al bucle de la Fase 3), pero
>   reportarlo con «Qué pasa hoy / Qué debería pasar» de la B sirve igual.
>
> No es obligatoria: `contexto/` acepta cualquier documento. Úsala cuando no tengas
> specs previas, o como lista de control de qué contiene un requerimiento bien escrito.

## Reglas de escritura

1. **Problema y resultado, no solución.** Cómo implementarlo se decide en el diseño.
   Una tecnología de verdad impuesta (política de la organización, sistema existente)
   es una **restricción**; una preferencia de diseño no es un requerimiento.
2. **Lo que no te conste, márcalo `[supuesto]`**: se confirma en el encuadre, no se
   hereda como verdad.
3. **Verificable o no es criterio.** «Rápido», «robusto», «amigable» no se pueden
   verificar; un umbral, un ejemplo o una condición observable sí (ver abajo).
4. **Corto.** Si una sección no aplica, escribe `no aplica` y sigue; no la infles.

---

## A · Requerimiento inicial

```markdown
# Brief: _[tema]_ — AAAA-MM-DD

## Problema y resultado esperado
<!-- Qué duele hoy, a quién, y qué existe cuando esto esté terminado (observable). -->
…

## Usuarios y quién decide
<!-- Quién lo usa; quién aprueba los gates y resuelve dudas de negocio. -->
…

## Criterios de éxito (candidatos a C#)
<!-- Verificables; uno por comportamiento. Serán los C1, C2… de encuadre.md. -->
- …

## Ejemplos entrada → salida (candidatos al set de oro)
<!-- ≥1 con datos CONCRETOS (no solo el formato). Archivos grandes → contexto/, enlazados. -->
- Entrada: _…_ → Salida esperada: _…_

## No-objetivos conocidos
<!-- Qué queda fuera a propósito. -->
- …

## Restricciones
<!-- Solo las reales: stack (¿impuesto o abierto? si abierto, se decide en el encuadre
con ADR), plazo, datos/privacidad, integraciones, despliegue si ya está decidido. -->
- …

## Insumos reales disponibles y referencias
<!-- Entradas y salidas del sistema (una o varias) y dónde están sus muestras: archivos
que dejas en contexto/, o accesos/API/BD para obtenerlas; si aún no hay, dilo. -->
- …

## Supuestos y riesgos
- [supuesto] …
```

**Listo para la ingesta cuando:**

- [ ] El problema explica el **por qué**, no solo el qué.
- [ ] Hay ≥1 criterio verificable (con condición observable, no adornos).
- [ ] Hay ≥1 ejemplo `entrada → salida` con datos concretos (o su archivo en `contexto/`).
- [ ] El stack dice si es **impuesto o abierto**; los supuestos van marcados `[supuesto]`.
- [ ] Quedó en `contexto/brief-<tema>.md`.

El encuadre pedirá más (set de oro ≥5 pares, stack resuelto, despliegue…): no lo
resuelvas todo aquí; el arranque completa los huecos contigo.

---

## B · Requerimiento nuevo o cambio (reentrada)

```markdown
# Brief de reentrada: _[tema]_ — AAAA-MM-DD

## Qué pasa hoy
<!-- Comportamiento observado, con evidencia real: entrada usada, salida obtenida, en
qué entorno (los archivos de evidencia → contexto/). Si no es falla sino algo nuevo:
"hoy el sistema no hace X". -->
…

## Qué debería pasar
<!-- Concreto y verificable. Si cambia o nace un criterio, escríbelo como criterio;
si cambia el set de oro, da el par nuevo o editado. -->
…

## Clasificación que propongo
<!-- Tu hipótesis; el agente hace el triage y lo confirmas en el gate. Pivote:
¿cambia la verdad acordada (un C# o el set de oro de encuadre.md)? -->
- [ ] Defecto / regresión / cobertura faltante / ajuste interno que el criterio ya
      permitía → Fase 3 (no cambia la verdad)
- [ ] Ajuste — **edita** un `C#` o un par del set de oro → Encuadre (rebanada)
- [ ] Requisito nuevo — **añade** un `C#`/capacidad → Encuadre (rebanada)
- [ ] Mejora opcional / pregunta → backlog / respuesta (no abre ciclo)

## C# o pares del set de oro afectados (si los conoces)
…

## Urgencia
<!-- ¿Bloquea la operación o puede esperar? -->
…
```

**Listo para el triage cuando:**

- [ ] «Qué pasa hoy» trae **evidencia real** (entrada + salida observada), no una impresión.
- [ ] «Qué debería pasar» es verificable (criterio o par del set de oro).
- [ ] Si el pedido mezcla aspectos (una parte falla, otra cambia un criterio), van
      **separados**: el triage clasifica **por aspecto, no por ticket**.
- [ ] Quedó en `contexto/` (aunque haya nacido en el chat) y anotado en el manifiesto.

---

## Cómo se escribe un buen criterio

**[actor/sistema] + verbo observable + condición + umbral o ejemplo.**

| ✗ Así no | ✓ Así sí |
|----------|----------|
| «La búsqueda debe ser rápida» | «Una búsqueda sobre el corpus completo (~10k docs) responde en <2 s» |
| «Usar PostgreSQL con índice GIN» (solución camuflada) | «La búsqueda tolera 1 error tipográfico por palabra» (y si Postgres es política de la org → Restricciones) |
| «Valida los datos y notifica y guarda el historial» (3 en 1) | Tres criterios, uno por comportamiento: se verifican y rastrean por separado |

Regla práctica: si el juez no podría dar **PASA/FALLA** leyendo el criterio y mirando
la salida, todavía no es un criterio; es una intención.
