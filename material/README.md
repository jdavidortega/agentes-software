# Material de contexto — entrada de ingesta

> Carpeta de **entrada** para lo que se **lee**: antecedentes, motivación, specs,
> notas, decisiones, código de referencia, capturas. Puede haber **varios
> archivos**. No necesitas ordenarlos ni clasificarlos: el agente los lee, los
> clasifica y los rutea a los archivos oficiales de la metodología.
>
> **Frontera con `analisis/`:** aquí va lo que se *lee*; los **artefactos
> analíticos** (notebooks, scripts, datos de entrada/salida) van a `analisis/`.

> **Obligatorio para arrancar.** Esta carpeta debe tener **≥1 archivo real** (además
> de este `README.md`) antes de construir el encuadre: el encuadre se **deriva** del
> material, no de lo que la persona alcance a teclear en frío. Si no tienes
> documentos, escribe un brief breve y déjalo aquí. Sin material, el agente se
> detiene (precondición de `docs/arranque.md`).

## Para la persona

- Suelta aquí cualquier archivo de contexto, sin estructura previa.
- Cuando quieras que se procese, díselo al agente (o él te pregunta en el Paso 1
  del arranque, al inventariar las entradas).
- Tú apruebas el ruteo antes de que se escriba nada (gate). El original **no se
  borra**: se queda aquí para trazabilidad.

## Para el agente (reglas de ingesta)

1. Lee **todo** lo que haya en esta carpeta (salvo este `README.md`).
2. Clasifica cada archivo y **propón** a dónde va, con su razón. **Siembra los
   documentos vivos desde el principio**: si el material ya trae contenido para
   ellos, no los dejes vacíos para "después".
   - **antecedentes y motivación** → `docs/contexto.md`.
   - **stack, tecnologías y arquitectura** que defina → §"Stack y arquitectura" de
     `docs/contexto.md` (la decisión); su detalle operativo va a `convenciones.md`.
   - **convenciones operativas** (estilo, patrones, comandos de build/test/run,
     entorno) → `docs/convenciones.md`, **verificando comandos y versiones contra la
     doc oficial vigente** antes de fijarlos.
   - **datos o decisiones** que implique → `docs/decisiones.md` (ADR-lite).
   - material que se conserva como **referencia** tal cual → se queda aquí; solo
     se anota en el manifiesto y, si aplica, se enlaza desde `docs/contexto.md`.
3. **Gate humano:** no escribas en los archivos oficiales sin aprobación explícita.
4. Si el material **contradice** algo ya escrito (un criterio, una decisión), no lo
   archives en silencio: señala qué queda inconsistente y resuélvelo con la persona.
5. **Nunca borres ni muevas** el archivo fuente. Se conserva siempre aquí; solo se
   elimina si la persona lo pide explícitamente.
6. Tras rutear, **añade una fila al manifiesto** de abajo.

## Manifiesto de ingesta

> Lo llena el agente. Una fila por archivo procesado. Es el acuse de recibo: evita
> reprocesar y deja rastro de a dónde fue cada cosa.

| Archivo | Fecha ingesta | Ruteado a | Nota |
|---------|---------------|-----------|------|
| _(ejemplo)_ `analisis.pdf` | AAAA-MM-DD | `docs/contexto.md` §Contexto | antecedentes |
