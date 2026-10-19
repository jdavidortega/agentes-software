# Modelo · Contenedores (Docker/compose)

- **Tres capas de config que no se mezclan:** host / rutas internas del contenedor /
  app. En `"A:B"`, A=host y B=contenedor; una constante interna del runtime **no se
  expone** en el archivo que el operador edita. Confundirlas costó horas en
  producción (índice vacío, 503).
- **Montaje fantasma:** con la sintaxis `-v`/`--volume` (y su equivalente corto en
  compose), si la fuente no existe en el host Docker la **crea como carpeta vacía** y la
  monta — síntoma engañoso (`disponible: true` con 500s). Con `--mount type=bind` (o
  `create_host_path: false` en compose) falla al arrancar, que es lo que se quiere.
  Prefiere `--mount`, monta archivos concretos y valida al arrancar que el insumo es
  **archivo legible**.
- **Regenera los derivados** (índices, cachés, volúmenes persistentes) tras corregir
  un insumo: no se actualizan solos.
- Runbook verificado con `docker inspect` contenedor por contenedor (montajes,
  puertos, redes) contra lo que el plan dice.
- **Reconstruir o traer, según el modelo:** si la imagen se **construye en el servidor**
  desde el código, `--build` al redesplegar (recrear el contenedor sin reconstruir la
  imagen es la causa clásica de "no veo el cambio"). Si la imagen se **promueve ya
  construida** (registro), no se reconstruye: `compose pull` de la versión aprobada,
  verificar su identidad (digest/etiqueta) y recrear (`up --no-build`).
- En servidor compartido con otros proyectos: puertos y volúmenes **aislados y
  documentados** en el runbook; verificar que no pisas nada ajeno antes de subir.
