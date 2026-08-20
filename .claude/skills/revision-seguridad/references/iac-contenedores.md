# Dominio · IaC / Contenedores / CI-CD

> Se activa con `Dockerfile`, compose, Terraform, manifiestos de K8s o workflows de CI.
> Audita lo declarado; **operar** el despliegue es `desplegando-a-produccion`.

## Qué buscar

- **Dockerfile:** imagen base sin fijar (`:latest` o sin digest), el proceso corre como
  `root` (falta `USER`), secretos en `ENV`/`ARG` o en capas intermedias (quedan en la
  imagen aunque una capa posterior los borre), paquetes de build innecesarios en la
  imagen final, `curl … | sh` sin verificación.
- **Compose / runtime:** puertos de servicios internos publicados al host sin
  necesidad, bind-mounts de rutas sensibles (`/var/run/docker.sock` es acceso root al
  anfitrión), `privileged: true`, capacidades añadidas sin justificación, variables con
  credenciales literales en el archivo versionado.
- **Kubernetes:** sin `securityContext` (`runAsNonRoot`, `readOnlyRootFilesystem`,
  `allowPrivilegeEscalation: false`), `hostPath`/`hostNetwork`, RBAC con `*` en
  verbos/recursos, secretos como variables planas, sin `NetworkPolicy` (todo pod habla
  con todo), sin límites de recursos.
- **Terraform / nube:** almacenamiento con acceso público, grupos de seguridad
  abiertos a `0.0.0.0/0` en puertos administrativos (22, 3389, bases de datos), IAM con
  `Action: "*"` o `Resource: "*"`, cifrado en reposo ausente, logging/auditoría
  desactivado, **estado de Terraform** con secretos versionado en el repo.
- **CI/CD (cadena de suministro):** secretos impresos o pasados por argumentos de línea
  de comandos (quedan en logs), acciones de terceros sin fijar a un SHA, disparadores
  peligrosos (`pull_request_target` con checkout del código del PR = ejecución de
  código ajeno con secretos del repo), permisos de token amplios cuando bastaría
  lectura, cachés compartidas entre ramas de confianza distinta.
- **Dependencias no fijadas** en la construcción (rangos abiertos, sin lockfile
  versionado): la construcción no es reproducible y es vía de *dependency confusion*.
