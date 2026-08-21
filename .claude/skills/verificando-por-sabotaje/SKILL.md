---
name: verificando-por-sabotaje
description: "Cómo demostrar que una garantía o un aserto de verificación existen de verdad: deshacer la garantía a propósito en una copia del árbol y comprobar que la suite se pone en rojo, o forzar el escenario de fallo del aserto antes de publicarlo. Úsala al cerrar cada incremento (toda garantía nueva se sabotea antes del commit), al pasar un hallazgo de `resuelto` a `verificado` (la regla escalonada de AGENTS.md §2 exige la mutación que lo mata, escrita en su fila), al escribir o modificar cualquier comprobación que respalde un criterio, y cuando un juez o una revisión afirma que algo está protegido. Incluye el arnés reutilizable y las trampas conocidas (mutar siempre en una copia, mediciones no deterministas, guardas con falso negativo)."
allowed-tools: Read, Grep, Glob, Bash
---
# Skill: Verificando por sabotaje

> Una garantía que ninguna prueba puede romper es un comentario. La forma de saber cuál de
> las dos cosas es: **romperla a propósito y ver si la suite se entera.** El procedimiento
> es de minutos y es la diferencia entre creer y saber. Nació de dos proyectos reales que
> pagaron caro no tenerlo: garantías que ningún test rompía (cinco veces en uno), asertos
> que no podían fallar (tres veces en el otro, dos *después* de escrita la lección —saber
> la regla no la ejecuta; hace falta el paso mecánico—).

## Cuándo usarla

- **Al cerrar cada incremento**, antes del commit: cada garantía nueva se sabotea. No es
  opcional (`docs/convenciones.md` §Pruebas).
- **Al pasar un hallazgo de `resuelto` a `verificado`**: es la vía normal para
  remediaciones mecanizables (`AGENTS.md` §2). Quien resuelve **escribe en la fila la
  mutación que ahora muere**; quien verifica la re-ejecuta **y añade una que el autor no
  nombró**.
- **Al escribir o modificar cualquier comprobación que respalde un criterio** (asertos de
  un script de verificación, checks de la DoD, tests de propiedad): protocolo del aserto
  falsable, abajo.
- **Cuando alguien afirma que algo está protegido** —un juez, una nota de trazabilidad, un
  comentario en el código—. Esa afirmación es una hipótesis hasta que una mutación la mata.

## Pasos (sabotear una garantía)

1. **Escribe la mutación como texto**, no como intención: qué archivo, qué cadena exacta
   antes y qué cadena después. Si no puedes escribirla, no tienes una garantía: tienes una
   idea.
2. **Ponla en un spec JSON** y córrelo con el arnés (usa la suite del stack vía
   `scripts/check.sh`, o pásale otra con `--suite`):

   ```sh
   python .claude/skills/verificando-por-sabotaje/scripts/sabotear.py mutaciones.json
   ```

   ```json
   [{"label": "el filtro de frescura sobre la ventana",
     "file": "src/consolidar.py",
     "before": "if item.seen_at >= window_start:",
     "after":  "if True:"}]
   ```
3. **Lee el veredicto.** `DIES` es lo que buscas. `SURVIVES` es un hallazgo: la garantía no
   existe y hay que escribir la prueba que falta. `ANCHOR LOST` es un spec rancio —el
   código se movió—, que es otro problema y no un permiso para dar la garantía por buena.
4. **Copia la mutación a la fila del hallazgo** en `docs/trazabilidad.md`, en la celda de
   resolución. Cuesta una línea y convierte tu convicción privada en un artefacto que otro
   re-ejecuta en segundos, sin conocer tu sesión.

## Protocolo del aserto falsable (antes de publicar una comprobación)

1. **Escribe primero el escenario de fallo** que la comprobación debe distinguir: "si X se
   rompe, este valor cambia así". Si no puedes nombrarlo, la comprobación no verifica
   nada — no la publiques.
2. **Pregunta si el aserto es cierto por construcción.** Recorre quién produce el dato:
   ¿existe alguna rama del código capaz de generar el valor que lo haría fallar? Si
   ninguna sentencia puede producirlo, es tautológico.
3. **Hazlo fallar una vez antes de publicarlo.** Fuerza el caso (reduce la ventana, quita
   el filtro, inyecta la fila mala, rompe el módulo a propósito — en una copia) y confirma
   el rojo. Registra cómo lo forzaste: esa corrida es el artefacto de que la verificación
   verifica.
4. **Lee el mensaje de fallo en voz alta**, y escríbelo para los dos desenlaces: un
   mensaje de fallo que describe el éxito manda a buscar donde no está. Síntoma típico de
   aserto vacío: **la cifra interesante se imprime y el aserto comprueba otra.**

## Notas / trampas

- **Siempre en una copia, nunca en el árbol de trabajo.** Con varias revisiones en vuelo,
  una mutación sin commitear pone la suite en rojo para todos. El arnés copia solo; si
  escribes el tuyo, verifica el `cwd` antes de mutar. Y una instrucción de sabotaje sin
  decir **dónde** es una instrucción incompleta.
- **Una herramienta de medición se valida corriéndola dos veces y comparando:** si no da
  lo mismo, lo que mide no existe. Trampa conocida en Python: CPython valida el `.pyc`
  contra el mtime del fuente truncado a segundos, así que un bucle de mutación reutiliza
  bytecode viejo sin `PYTHONDONTWRITEBYTECODE=1` (el arnés ya lo pone). Otros stacks
  tienen sus cachés equivalentes: compruébalo.
- **Verificar contra un commit exige que lo verificado esté en el commit.** Pedir
  "verifícalo contra `git archive HEAD`" con la remediación sin commitear produce falsos
  negativos con aspecto de rigor. El arnés usa el árbol de trabajo por defecto;
  `--commit` cuando de verdad quieres el commit.
- **Un guarda con falso negativo es peor que uno ausente**, porque da permiso. Cuando un
  chequeo afirma algo sobre texto ("no hay `DELETE`"), sabotéalo con la forma que el
  lenguaje admite y tu regex no: palabra al final de la cláusula, otra indentación,
  mayúsculas. Y acota las aserciones sobre texto por la **estructura** (líneas, comas de
  nivel de tope), nunca por un número de caracteres.
- **Añade una mutación que el autor no nombró.** Es la cláusula que hace funcionar la
  regla escalonada: re-ejecutar solo lo que la fila dice es marcarse la tarea con el
  examen que uno eligió.
- **Trampa nueva → al reporte.** Si el sabotaje revela un obstáculo operativo nuevo (un
  caché que miente, un flag necesario, un entorno que se comporta distinto), repórtalo
  en la sección **Obstáculos** de tu veredicto: el principal lo suma a estas Notas o a
  `docs/convenciones.md`. La skill se afina con el uso; un obstáculo no reportado se
  redescubre a precio completo.
- **Lo que no es mecanizable no se sabotea, se declara.** Ninguna mutación mata "elegimos
  A sobre B". Ahí aplica la otra vía de `AGENTS.md` §2 (identidad o gate humano). Lo que
  **sí** puedes sabotear de un ADR son sus **opciones descartadas**: si implementar la
  opción rechazada deja la suite en verde, el ADR está sin proteger.
