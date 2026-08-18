# Modelo · Serverless

- Límites del proveedor documentados en el runbook (timeout, memoria, tamaño de
  paquete, concurrencia) y verificados contra la doc oficial vigente.
- Variables y secretos por el mecanismo del proveedor, nunca dentro del paquete.
- Probar el **empaquetado real** (el artefacto que se sube) antes de publicar, no
  solo el código en local.
