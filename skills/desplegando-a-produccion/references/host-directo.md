# Modelo · Host directo

- Proceso gestionado (systemd/supervisor), no un `nohup` suelto: arranque al boot,
  reinicio ante caída, logs con rotación.
- Usuario propio con permisos mínimos; nada corre como root sin razón documentada.
- Rutas ancladas (nunca al `cwd`) y dependencias del SO listadas en el runbook con
  versión.
- El comando de arranque de producción es el del stack (`docs/convenciones.md`), no
  una variante artesanal solo del servidor.
