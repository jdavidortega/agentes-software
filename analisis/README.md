# Análisis — artefactos analíticos

> Espacio para los **artefactos analíticos** del proyecto: notebooks, scripts de
> inspección, **datos de entrada** (opcionales) y **datos de salida/resultados**, sean
> de análisis previos o del muestreo que acompaña al diseño. Es lo que se *ejecuta o
> inspecciona*, no lo que se *lee* (eso va a `material/`). No es código de producción.

## Para qué sirve

- **Análisis previo como contexto:** si ya hay notebooks o resultados de trabajos
  anteriores, son contexto real del proyecto. Sus **hallazgos** alimentan
  `docs/contexto.md` §Contexto.
- **Datos de salida → set de oro:** los pares **datos de entrada → datos de salida**
  son candidatos directos al **set de oro** del encuadre (`docs/contexto.md`). Es
  probablemente su mayor valor para el arranque.
- **Muestreo de insumos reales (Paso 1 del arranque):** abrir 1–3 muestras reales de
  cada insumo y validar contra ellas los supuestos del spec (formato, nombres,
  numeración, casos límite, datos ya pre-extraídos). Las discrepancias se registran
  como decisión en `docs/decisiones.md`.

## Reglas

- **Opcional, pero su revisión es obligatoria.** La carpeta puede estar vacía; mirarla
  al arrancar no. Si tiene contenido, sus hallazgos se rutean (con gate); si está
  vacía, se registra explícitamente "no hay análisis previo".
- **Si tiene contenido, es parte del contexto real del proyecto:** consúltala al
  retomar el trabajo.
- Es exploratorio, no producción: no se importa desde el código de la app.
- Lo que se aprende se **promueve** a los archivos oficiales (contexto, decisiones);
  los notebooks y datos crudos **se quedan** aquí y se **enlazan** desde
  `docs/contexto.md`, no se copian.
