# Análisis exploratorio

> Espacio para el trabajo exploratorio que precede y acompaña al diseño: notebooks,
> scripts de inspección, muestreo de insumos reales. No es código de producción.

## Para qué sirve

- **Muestreo de insumos reales (Paso 2 del arranque):** abrir 1–3 muestras reales de
  cada insumo y validar contra ellas los supuestos del spec (formato, nombres,
  numeración, casos límite, datos ya pre-extraídos). Lo que se descubre aquí alimenta
  `docs/contexto.md` y se registra como decisión en `docs/decisiones.md`.
- **Validación inicial del problema:** entender los datos y el dominio antes de
  comprometerse a un diseño.

## Reglas

- **Si esta carpeta existe, su contenido es parte del contexto real del proyecto:**
  consúltala al retomar el trabajo. No es obligatoria — si el proyecto no tiene datos
  de muestra, simplemente no se usa.
- Es exploratorio, no producción: no se importa desde el código de la app.
- Lo que se aprende se **promueve** a los archivos oficiales (contexto, decisiones),
  no se queda solo aquí.
- Si un análisis se vuelve un insumo de contexto estable, considéralo parte del
  conocimiento real del problema y déjalo enlazado desde `docs/contexto.md`.
