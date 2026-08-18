# Skills

> Procedimientos reutilizables. Una skill es una lección que se repitió tanto
> que vale la pena documentarla como un "cómo hacer X" estable. **Solo se carga
> cuando aplica**: un proyecto sin front nunca paga el costo de la skill de front.

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
<!-- Lista de las skills de este proyecto, con su disparador en una línea. -->
- **`revision-funcional.md`** — revisor funcional: revisión independiente del encuadre
  y el plan al cerrar el arranque, contra su fuente (`material/`, `analisis/`); valida
  completitud y consistencia (reporta, no escribe).
- **`revision-critica.md`** — agente juez: revisión crítica independiente de cada
  incremento antes del commit (rúbrica de calidad; reporta, no edita).
- **`escribiendo-readme.md`** — README informativo con diagrama Mermaid gerencial y
  variantes por tipo de repo. Se dispara al crear/actualizar el README (DoD: mismo
  commit que cambia comportamiento; verificación al cierre de cada fase).
- **`construyendo-frontend.md`** — validación cliente+servidor, estados de
  error/carga/vacío, responsive con evidencia, nada quemado. Se dispara cuando el
  proyecto tiene interfaz web.
- **`desplegando-a-produccion.md`** — núcleo común (entorno de prueba, respaldos
  verificados, runbook, `--confirm-prod`, reversión) + secciones por modelo de
  despliegue (contenedores / host / serverless). Se dispara con la rebanada de
  Operación/Despliegue.
- **`probando-con-datos-reales.md`** — camino principal en la suite, tests que
  aportan, set de oro como regresión, mutation testing en Fase 4. Se dispara en el
  diseño de la estrategia de pruebas y en cada incremento.
