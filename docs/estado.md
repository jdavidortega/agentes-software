# Estado del proyecto

> **Punto de reentrada.** Lo primero que el agente lee en cada sesión (junto con
> `convenciones.md`); los demás documentos se abren solo en la rebanada que la tarea
> toca. Se **REGENERA** (no se acumula) al cierre de cada incremento y de cada fase, **y
> en cada parada**: fin de sesión, gate pendiente de la persona, bloqueo. Lo que no
> está escrito aquí al parar se pierde; lección aprendida. Máximo una página. El detalle
> vive en los documentos por rebanada; la historia, en git; el porqué, en los ADR. Se
> siembra al cerrar la Fase 2 (`Ref: F2`). Al cierre del ciclo (F5) queda en **modo
> reentrada**: criterios `verificado`, nada "en curso", próximo paso = triage.
>
> **Al regenerar, cada afirmación se comprueba contra su fuente** —un PASA contra
> `docs/revisiones.log`, un gate aprobado contra la aprobación de la persona (un PASA no es
> un gate), un hallazgo contra `docs/trazabilidad.md`, un commit contra git—; nada se copia
> de la versión anterior sin comprobarlo. **Se retira** lo cerrado: gates, revisiones y pasos
> de fases o incrementos terminados (su historia está en git). **Se conserva** lo pendiente que
> sigue vigente aunque venga de una fase anterior, diciendo qué bloquea ahora. Lo que se
> cite como historia lleva `(histórico, <fecha UTC>)` y nunca va en «Pendiente».

- **Fase actual:** F_ · incremento activo: I_ «alias»
- **Próximo paso:** _…_

## Pendiente

<!-- Lo que falta del incremento en curso, en frases completas (qué, no siglas), y lo
que se espera de la persona. Se reescribe en cada parada; vacío solo si no hay nada. Un
pendiente de una fase anterior que sigue vivo se queda, con lo que bloquea ahora. -->
- **Del incremento en curso:** —
- **Esperando de la persona:** — (gate / dato / decisión; qué y dónde)

## Criterios

| C# | Alias | Estado |
|----|-------|--------|
| C1 | «…» | pendiente / cubierto / verificado |

## Abierto ahora

<!-- Solo lo VIVO: hallazgos sin cerrar, ADRs en `propuesta`, supuestos con
validación diferida (esperando su primer insumo real). Lo cerrado no vive aquí. -->
- **Hallazgos abiertos:** —
- **ADRs en `propuesta`:** —
- **Supuestos con validación diferida:** —

## Referencias activas

<!-- Los 2–4 ADR/decisiones que condicionan el trabajo actual, por título. -->
- —
