# Modelo · Contenedores (Docker/compose)

- **Tres capas de config que no se mezclan:** host / rutas internas del contenedor /
  app. En `"A:B"`, A=host y B=contenedor; una constante interna del runtime **no se
  expone** en el archivo que el operador edita. Confundirlas costó horas en
  producción (índice vacío, 503).
- **Montaje fantasma:** si el archivo fuente no existe en el host, el bind-mount crea
  una **carpeta vacía** y la monta — síntoma engañoso (`disponible: true` con 500s).
  Monta archivos concretos y valida al arrancar que el insumo es **archivo legible**.
- **Regenera los derivados** (índices, cachés, volúmenes persistentes) tras corregir
  un insumo: no se actualizan solos.
- Runbook verificado con `docker inspect` contenedor por contenedor (montajes,
  puertos, redes) contra lo que el plan dice.
- **`--build` obligatorio al redesplegar:** recrear el contenedor sin reconstruir la
  imagen es la causa clásica de "no veo el cambio".
- En servidor compartido con otros proyectos: puertos y volúmenes **aislados y
  documentados** en el runbook; verificar que no pisas nada ajeno antes de subir.
