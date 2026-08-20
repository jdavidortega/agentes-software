# Dominio · Frontend web

> Se activa con interfaz web. Complementa `construyendo-frontend`: esa exige validación
> doble y estados; aquí se audita lo explotable.

## Qué buscar

- **XSS (CWE-79).** *Sinks* sin escapar: `innerHTML`, `outerHTML`,
  `dangerouslySetInnerHTML`, `v-html`, `document.write`, `insertAdjacentHTML`,
  `$.html()`, `eval`, `new Function`, `setTimeout` con string. Por cada uno, **traza el
  valor hasta su origen**: si viene de la URL, del usuario, de la BD o de una API, es
  hallazgo; si es una constante del código, no. Remediación: renderizado por texto
  (`textContent`, interpolación del framework) o sanitizador mantenido, nunca un regex
  propio.
- **Secretos en el cliente (CWE-798).** Toda clave que llega al bundle es pública:
  busca `apiKey`, `secret`, `token`, `password`, `Bearer `, cadenas de conexión, y
  variables de build expuestas (`VITE_*`, `NEXT_PUBLIC_*`, `REACT_APP_*`) con valores
  sensibles. Remediación: la llamada que necesita la clave vive en el servidor.
- **Endpoints y datos internos filtrados:** URLs internas, IPs, nombres de host de
  infraestructura, comentarios con rutas de administración.
- **Almacenamiento de tokens.** JWT de sesión en `localStorage`/`sessionStorage` es
  legible por cualquier XSS. Preferido: cookie `HttpOnly` + `Secure` + `SameSite`.
- **Cabeceras de seguridad ausentes o permisivas** (A05): CSP con `unsafe-inline`/
  `unsafe-eval`/`*`, falta de `X-Content-Type-Options`, `Referrer-Policy`.
  Proporcionalidad: exígelas en una app servida a usuarios, no en un artefacto interno
  sin navegador.
- **CSRF (CWE-352)** en formularios que mutan estado con cookies de sesión, y
  **clickjacking** (`frame-ancestors`) en vistas sensibles.
- **Redirecciones abiertas** (`window.location = <valor externo>`) y `target="_blank"`
  sin `rel="noopener"`.
- **Autorización decidida en el cliente.** Ocultar un botón no es autorizar: si la
  única barrera es la UI, el hallazgo es del back (control de acceso roto).
