# Dominio · Backend / API

> Se activa con servicio, API o cualquier código que reciba peticiones. Es el dominio
> donde viven los hallazgos que más pesan.

## Qué buscar

- **Inyección (CWE-89/78/943).** Consultas construidas por concatenación o
  interpolación de strings (SQL, NoSQL, LDAP), y comandos de sistema con entrada
  externa (`os.system`, `subprocess` con `shell=True`, `exec`, `child_process.exec`).
  Remediación: **consultas parametrizadas** y APIs sin shell (`subprocess.run([...])`);
  una lista de permitidos, nunca un filtro de caracteres prohibidos.
- **Control de acceso roto (A01, CWE-639) — el más frecuente y el más caro.**
  Por cada endpoint que recibe un identificador: ¿se verifica que **este** usuario
  puede tocar **ese** objeto (IDOR/BOLA), o se confía en el ID que llegó del cliente?
  ¿Y la autorización **de función** (un rol que no debería poder llamar la ruta)?
  Ojo con rutas nuevas que heredan por convención un middleware que no las cubre.
- **Autenticación y sesiones.** JWT: `alg: none`, algoritmo tomado del propio token,
  secreto débil o quemado, sin `exp`, firma no verificada. Contraseñas: `bcrypt`/
  `argon2`/`scrypt`, nunca MD5/SHA1/SHA256 pelado. Sesiones que no se invalidan al
  cerrar, tokens de recuperación predecibles.
- **SSRF (CWE-918):** el servidor pide una URL que el usuario controla. Remediación:
  lista de destinos permitidos, y bloquear rangos internos y metadatos de nube.
- **Exposición excesiva de datos:** el endpoint devuelve el objeto entero (hash de
  contraseña, campos internos, PII) y "el front ya no lo muestra". Se filtra en el
  servidor.
- **Mass assignment:** el cuerpo de la petición se asigna al modelo sin lista de campos
  permitidos (un `role: admin` colado).
- **Deserialización insegura** (`pickle`, `yaml.load` sin `SafeLoader`, `unserialize`)
  y **path traversal** (`../` en nombres de archivo, rutas construidas con entrada).
- **Criptografía:** algoritmos obsoletos, IV/nonce reutilizado, aleatoriedad no
  criptográfica (`random` en vez de `secrets`), verificación TLS desactivada
  (`verify=False`, `rejectUnauthorized: false`).
- **Rate limiting ausente** en login, recuperación de contraseña y endpoints costosos.
- **Fugas por logs y errores:** stack traces al cliente, credenciales/PII/tokens en
  logs (choca con la regla de manejo explícito de errores de `revision-critica`).
- **Subida de archivos:** tipo validado por extensión, sin límite de tamaño, guardado
  en ruta servida públicamente o ejecutable.
