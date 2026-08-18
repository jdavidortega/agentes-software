# Skill: Escribiendo el README

> Cómo se escribe un README **informativo**: uno que un lector externo al proyecto
> entiende sin abrir el código. Se usa cada vez que se crea o actualiza el
> `README.md` — y la DoD lo dispara sola: se actualiza **en el mismo commit** que
> cambia comportamiento, interfaz o comandos, y se verifica contra la realidad del
> código **al cierre de cada fase**, sin que la persona lo pida (`AGENTS.md` §2).

## Cuándo usarla

- Al crear el README del proyecto (primer incremento que produce algo ejecutable).
- En todo commit que cambie comportamiento, interfaz pública o comandos.
- Al cierre de cada fase (verificación automática: ¿el README describe lo que el
  sistema hace **hoy**?).

## Estructura mínima (todo README)

1. **Qué es y qué problema resuelve** — dos frases, para alguien que no es del
   equipo. Sin jerga interna del proyecto.
2. **Diagrama del flujo lógico (Mermaid), a nivel gerencial** — qué entra, qué hace
   el servicio, qué sale: componentes de alto nivel y su relación. **No** es un
   diagrama técnico (nada de clases ni tablas); si el detalle crece, va a
   `docs/plan.md`, no aquí.
3. **Cómo ejecutarlo** — local y producción, con los comandos reales (los mismos de
   `docs/convenciones.md` §Comandos clave; no los dupliques con variaciones: cópialos
   exactos o referencia).
4. **Entradas y salidas** — qué consume y qué produce, con **un ejemplo concreto**.
5. **Estructura del repo** — árbol corto comentado.

## Variantes por tipo de repo (añadir a la estructura mínima)

- **Solución completa / monorepo:** mapa de servicios y **cómo se comunican** (quién
  llama a quién, por qué canal), orden de arranque, y dónde vive cada **contrato**
  entre partes.
- **Back / API:** tabla resumida de endpoints (método, ruta, propósito en una frase)
  + enlace a la doc generada (OpenAPI/Swagger); autenticación; modelo de despliegue.
- **Base de datos / ETL:** fuentes → transformaciones → salidas; el **contrato que
  produce** (vistas, esquemas de `_id`, patrones de nombre de archivo) y **quién lo
  consume**; cómo re-ejecutar el pipeline y **en qué SO corre** (un pipeline que solo
  corre en el SO del desarrollador no es re-ejecutable en el servidor).
- **Front:** pantallas principales, contra qué back apunta (y cómo se configura),
  build y despliegue.

## Pasos

1. Identifica el tipo de repo y toma estructura mínima + su variante.
2. Escribe/actualiza **contra el código actual**, no de memoria: verifica cada
   comando ejecutándolo y cada afirmación contra lo que el sistema hace hoy.
3. Dibuja o actualiza el Mermaid gerencial (si el flujo no cambió, no lo toques).
4. Relee como lector externo: ¿podría ejecutarlo y entender qué hace sin abrir el
   código? Si no, falta algo; si sobra detalle técnico, muévelo a `docs/`.

## Notas / trampas

- **El README describe lo que el sistema hace HOY.** El error documentado: un giro de
  arquitectura (LLM-first) dejó un README diciendo "funciona 100% offline" durante
  semanas. Por eso la verificación es al cierre de cada fase y automática.
- **Consistencia interna:** si un título promete "config en dos capas", la lista tiene
  dos elementos, no tres. Esa incoherencia costó horas en producción.
- **No es el lugar de la verdad acordada:** objetivos, criterios y stack viven en
  `docs/contexto.md`; el README los resume y enlaza, no los duplica con otras palabras
  (dato en un solo lugar).
- Diferir el README "para después" está prohibido por la DoD: reapareció como
  bloqueante siete incrementos más tarde.
