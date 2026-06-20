# Skills

> Procedimientos reutilizables. Una skill es una lección que se repitió tanto
> que vale la pena documentarla como un "cómo hacer X" estable.

## De dónde salen

```
corrección puntual  →  docs/MEMORIA.md  →  (si se repite)  →  skill aquí
```

No diseñes skills por adelantado. Deja que emerjan del uso. Eso es coherente
con la guarda anti-sobredimensionamiento.

## Formato de una skill

Crea un archivo `skills/<nombre-corto>.md` con:

- **Cuándo usarla:** el disparador (qué situación la invoca).
- **Pasos:** el procedimiento, concreto.
- **Notas / trampas:** lo que aprendiste por las malas.

## Skills actuales
<!-- Lista de las skills de este proyecto. -->
- **`revision-funcional.md`** — revisor funcional: revisión independiente del encuadre
  y el plan al cerrar el arranque, contra su fuente (`material/`, `analisis/`); valida
  completitud y consistencia (reporta, no escribe).
- **`revision-critica.md`** — agente juez: revisión crítica independiente de cada
  incremento antes del commit (rúbrica de calidad; reporta, no edita).
