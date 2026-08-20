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

Una skill es **una carpeta**, no un archivo: `skills/<nombre-corto>/SKILL.md`. El
nombre de la carpeta es el identificador (minúsculas, números y guiones; ≤64
caracteres) y **debe coincidir con el campo `name`**.

`SKILL.md` abre con **frontmatter YAML** de dos campos obligatorios:

```yaml
---
name: nombre-corto            # igual al nombre de la carpeta
description: "Qué hace la skill y cuándo debe usarse."   # ≤1.024 caracteres
allowed-tools: Read, Grep, Glob, Bash, Edit              # opcional: acota herramientas
---
```

- **`description` es el campo que más pesa:** es lo único que el agente ve antes de
  decidir si abre la skill, así que responde **dos** preguntas —*qué hace* y *cuándo
  usarla*— y nombra los disparadores con las palabras que aparecerán en el pedido
  real. Una descripción vaga es una skill que nunca se activa.
- **`allowed-tools`** acota las herramientas mientras la skill está activa. Útil como
  guarda en roles de solo lectura o casi (las dos revisiones). No filtra por ruta: lo
  que no puede expresarse ahí sigue siendo prosa + rastro exigible (`AGENTS.md` §8).

Después del frontmatter, el cuerpo:

- **Cuándo usarla:** el disparador, con el detalle por fase que no cabe en la
  `description`.
- **Pasos:** el procedimiento, concreto.
- **Notas / trampas:** lo que aprendiste por las malas.

Si la skill necesita material de apoyo, la carpeta admite (**solo si hace falta**, la
guarda anti-sobredimensionamiento también aplica aquí):

```
skills/<nombre>/
├── SKILL.md          obligatorio
├── references/       documentación adicional que se abre solo cuando aplica
├── scripts/          código ejecutable de la skill
└── assets/           plantillas, imágenes u otros datos
```

`references/` gana su lugar cuando el cuerpo tiene **variantes excluyentes** y cargar
todas es gastar contexto: así está partida `desplegando-a-produccion` (una referencia
por modelo de despliegue, y la skill dice cuál abrir). Con secciones cortas que
siempre se leen juntas, un solo `SKILL.md` es lo correcto.

## Descubrimiento

Las skills viven aquí —fuente de verdad, agnóstica de herramienta, referenciada por
ruta desde `AGENTS.md`—. `.claude/skills/<nombre>` es un **symlink** a cada carpeta,
que es lo que hace que Claude Code las autodescubra y cargue solo su `description`
hasta que una dispara. Al crear una skill nueva, crea también su symlink:

```sh
ln -s ../../skills/<nombre> .claude/skills/<nombre>
```

`scripts/check_docs.sh` verifica lo mecanizable de todo esto (frontmatter presente,
`name` == carpeta, `description` no vacía y dentro del límite, symlink existente).

## Skills actuales
<!-- Lista de las skills de este proyecto, con su disparador en una línea. -->
- **`revision-funcional/`** — revisor funcional: revisión independiente del encuadre
  y el plan al cerrar el arranque, contra su fuente (`material/`, `analisis/`); valida
  completitud y consistencia (reporta, no escribe).
- **`revision-critica/`** — agente juez: revisión crítica independiente de cada
  incremento antes del commit (rúbrica de calidad; reporta, no edita).
- **`revision-seguridad/`** — juez de seguridad: auditoría independiente de lo
  explotable, con `references/` por dominio (frontend, backend/API, IaC-contenedores,
  IA/LLM). Se dispara cuando el incremento toca superficie de riesgo, y en Fase 4.
- **`escribiendo-readme/`** — README informativo con diagrama Mermaid gerencial y
  variantes por tipo de repo. Se dispara al crear/actualizar el README (DoD: mismo
  commit que cambia comportamiento; verificación al cierre de cada fase).
- **`construyendo-frontend/`** — validación cliente+servidor, estados de
  error/carga/vacío, responsive con evidencia, nada quemado. Se dispara cuando el
  proyecto tiene interfaz web.
- **`desplegando-a-produccion/`** — núcleo común (entorno de prueba, respaldos
  verificados, runbook, `--confirm-prod`, reversión) + `references/` por modelo de
  despliegue (contenedores / host / serverless). Se dispara con la rebanada de
  Operación/Despliegue.
- **`probando-con-datos-reales/`** — camino principal en la suite, tests que
  aportan, set de oro como regresión, mutation testing en Fase 4. Se dispara en el
  diseño de la estrategia de pruebas y en cada incremento.
- **`verificando-por-sabotaje/`** — demostrar que una garantía existe deshaciéndola a
  propósito en una copia y viendo la suite en rojo; incluye el arnés y el protocolo del
  aserto falsable. Se dispara al cerrar cada incremento (garantías nuevas), al pasar un
  hallazgo de `resuelto` a `verificado` (la mutación escrita en la fila) y antes de
  publicar cualquier aserto de verificación.
