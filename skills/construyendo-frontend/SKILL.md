---
name: construyendo-frontend
description: "Prácticas mínimas exigibles para cualquier interfaz web: validación de campos en cliente Y servidor, feedback de formularios, estados visibles de error/carga/vacío, responsive verificado con evidencia (capturas en 2–3 anchos), nada de listas ni textos quemados, accesibilidad mínima y contrato con el back respetado al byte. Úsala en el diseño (Fase 2) de un proyecto con interfaz web, en cada incremento de la Fase 3 que toque el front, y como parte de la rúbrica del juez en esos incrementos. Un proyecto sin interfaz nunca la carga."
---
# Skill: Construyendo frontend

> Prácticas mínimas para cualquier interfaz web del proyecto. Se activa cuando el
> proyecto tiene front (o un incremento lo toca); un proyecto sin interfaz nunca
> carga esta skill. El juez la usa como parte de su rúbrica en los incrementos de
> front.

## Cuándo usarla

- En el diseño (Fase 2) de un proyecto con interfaz web: sus reglas condicionan el
  plan (validación doble, estados, evidencia responsive).
- En cada incremento de la Fase 3 que toque el front.
- En la revisión del juez sobre esos incrementos (exigir la evidencia).

## Reglas

1. **Validación de campos en cliente Y servidor.** La del cliente es UX (feedback
   inmediato); la del servidor es la **real** (seguridad e integridad). Nunca solo
   una: un formulario que solo valida en el cliente está sin validar.
2. **Todo formulario da feedback al enviar:** éxito visible, error visible con mensaje
   útil (qué falló y qué hacer), y estado de envío (botón deshabilitado/spinner) para
   evitar dobles envíos.
3. **Estados visibles de error, carga y vacío** en toda vista que consuma datos: nada
   de pantallas en blanco ni fallos silenciosos. Un error de API se muestra con
   mensaje accionable, no se traga.
4. **Responsive verificado, con evidencia.** Cada incremento de front se verifica
   contra 2–3 anchos reales (p. ej. ~375 px móvil, ~768 px tablet, ≥1280 px
   escritorio). La evidencia (capturas) es parte de la verificación con datos reales
   de la DoD; el juez puede exigirla.
5. **Nada de listas ni valores quemados en el front.** Las decisiones semánticas
   (alcance, catálogos, clasificaciones) van al servicio/árbitro correspondiente; y
   toda vía que evite al árbitro necesita su **propio** filtro (lección: saltarlo
   produjo respuestas fuera de alcance).
6. **Textos de cara al usuario externalizados** (no quemados en el código) y en el
   idioma del producto — ya es regla de `docs/convenciones.md`; aquí se verifica.
7. **Accesibilidad mínima:** todo input con su `label`, contraste legible, navegable
   por teclado, imágenes significativas con `alt`.
8. **El contrato con el back se respeta al byte.** El front consume el modelo de
   datos de salida definido en `docs/plan.md` (contrato); si el front necesita otra
   forma, eso es un cambio de contrato → ADR, no un apaño en el cliente.

## Pasos (por incremento de front)

1. Revisa qué reglas de arriba toca el incremento y diséñalo con ellas puestas.
2. Implementa validación doble (cliente + servidor) para todo campo nuevo.
3. Verifica los tres estados (error/carga/vacío) provocándolos de verdad
   (desconecta el back, envía datos inválidos, consulta sin resultados).
4. Toma las capturas responsive en los 2–3 anchos y déjalas como evidencia de la
   verificación del incremento.
5. Pasa la revisión del juez con la evidencia disponible.

## Notas / trampas

- "Se ve bien en mi pantalla" no es verificación: es un solo ancho.
- Validar solo en el cliente **parece** suficiente hasta que alguien llama a la API
  directo.
- Un `catch` que solo hace `console.error` es un fallo silencioso para el usuario
  (regla de manejo de errores del juez, aplicada al front).
- No inventes design system ni librería de componentes sin aprobación (`AGENTS.md`
  §3): es una dependencia nueva como cualquier otra.
