# Definición de Hecho (Definition of Done)

> La compuerta de calidad. Adáptala a tu proyecto. Se usa en **dos momentos**:
> **(1) por incremento** (Fase 3): cada pieza la cumple al construirla, antes del
> commit; **(2) sobre el conjunto** (Fase 4): el sistema ensamblado la cumple a la
> vez, integrado y sobre datos reales (end-to-end), sin regresiones.
>
> **Si el conjunto NO cumple (Fase 4):** vuelve atrás según la causa. Defecto o
> cobertura faltante (requisitos correctos) → Fase 3, incremento de corrección.
> Encuadre erróneo o requisito nuevo (cambian criterios o set de oro) → Fase 1,
> ajustar `docs/contexto.md` + ADR + re-revisión funcional. Una mejora más allá de lo
> acordado no es falla: va al backlog de `docs/plan.md`.

Antes de marcar como terminado:

- [ ] Cumple los criterios de éxito **y el set de oro** de `docs/contexto.md` (no
  solo "funciona": la salida tiene la calidad esperada).
- [ ] Las pruebas pasan (y hay pruebas para lo nuevo).
- [ ] **Tests herméticos:** ninguna prueba depende de config de entorno (`.env`) ni
  llama a servicios externos; lo externo se inyecta o se mockea.
- [ ] **Sin secretos ni config quemada:** las variables, rutas y credenciales van a
  `.env` (no versionado); `.env.example` documenta cuáles, sin valores reales.
- [ ] **Verificación con datos reales:** si el incremento toca datos o salida, se
  verificó de forma exploratoria sobre insumos reales representativos, no solo
  fixtures sintéticos. Si toca el despliegue, además una prueba **end-to-end en las
  condiciones reales del modelo elegido** (empaquetado y datos de producción), no
  solo en local.
- [ ] **Sin rutas al `cwd`:** todo recurso (datos, `.env`, índices/bases) se ancla a
  la raíz del proyecto o a una ruta de entorno explícita; ninguna ruta depende del
  directorio desde el que se ejecuta.
- [ ] **Recursos usables, no solo presentes:** los chequeos de salud validan que el
  recurso sirve (legible, esquema correcto), no solo que existe.
- [ ] **Interfaces públicas documentadas** (endpoints, funciones exportadas, CLI),
  completa pero concisa: propósito en una frase, entradas/salidas y su forma,
  errores/casos especiales, y un ejemplo. APIs: `summary` + `description` + `tags` +
  ejemplos en el esquema. Funciones: docstring con el contrato. Prueba: si hay que
  leer la implementación para invocarla, está incompleta; si repite el código línea
  a línea, está inflada.
- [ ] El código es legible y sigue `docs/convenciones.md`.
- [ ] No se agregaron dependencias ni abstracciones nuevas sin aprobación.
- [ ] No quedó código muerto, TODOs sin registrar, ni "por si acaso".
- [ ] Las decisiones relevantes están en `docs/decisiones.md`.
- [ ] `README.md` actualizado (estructura, entradas/salidas, cómo ejecutar local y
  producción) si el cambio lo afecta.
- [ ] **Commit de la fase/incremento** hecho, con mensaje concreto y suficiente.
- [ ] Hay revisión humana del cambio.
- [ ] Las lecciones, si las hubo, están en `docs/MEMORIA.md`.
