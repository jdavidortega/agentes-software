# Brief: resumen de gastos

Llevo mis gastos en un CSV (`fecha,categoria,importe`) y quiero, desde la terminal, ver cuánto gasté
por categoría y el total. Lo uso solo yo, en mi equipo; nada se publica ni se despliega.

- Una línea por categoría, `categoria: importe` con dos decimales, de mayor a menor importe; al final
  `Total: <importe>`.
- Si una fila tiene un importe que no es un número, quiero saber qué fila es y que no salga un resumen a
  medias.
- Si me equivoco de archivo, que lo diga.

Lo prefiero en Python, sin instalar nada.

Muestras: `gastos.csv` (un mes normal) y `gastos-invalido.csv` (una fila mal escrita).
