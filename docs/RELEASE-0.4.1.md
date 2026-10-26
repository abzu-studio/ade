# Adê 0.4.1 · macOS

Edición SwiftUI/Xcode, compilación 15. Requiere macOS 14 o posterior; incluye Apple Silicon e Intel.

## Descargas

- `Ade-0.4.1-15-unsigned.dmg`: aplicación y acceso a Aplicaciones.
- `Ade-0.4.1-source.zip`: código exacto del proyecto Xcode usado para compilar el DMG, reglas, pruebas y licencias.
- `SHA256SUMS.txt`: checksums de ambas descargas.
- `BUILD.txt`: commit y ejecución de GitHub Actions de procedencia.

## Instalación

Abre el DMG y arrastra Adê a Aplicaciones. La aplicación se entrega sin registros, datos personales, credenciales ni herramientas de prueba. Conserva el identificador `com.ade.mac` y el formato de almacenamiento de la edición Xcode 0.4.0; reemplazar su aplicación no borra los espacios existentes. Es recomendable exportar una copia desde Datos antes de actualizar.

**Esta edición usa firma ad hoc. No tiene certificado Developer ID ni notarización de Apple.** macOS puede bloquear su primera apertura. Si confías en esta descarga, consulta las [instrucciones de Apple para abrir una app bloqueada](https://support.apple.com/es-es/102445). No requiere desactivar Gatekeeper.

El Swift Package 1.0.1 de este repositorio es otra edición, con otro contenedor y formato; no migra automáticamente sus datos a este DMG.

## Cambios

- Corrige vistas que desaparecían al alternar Personas, Grupos y Períodos.
- Conserva deshacer y rehacer al reintentar una escritura fallida; limpia acciones obsoletas tras recuperar una copia.
- Los PDF individuales incluyen únicamente la persona seleccionada.
- Invalida vistas previas y resultados de participación cuando cambian sus filtros o revisiones.
- Añade apertura rápida y mueve cálculos y persistencia fuera del hilo principal.
- Excluye la demostración y los accesos de prueba de Release; el autor inicial es «Local».

Las pruebas automatizadas, la compilación universal y la inspección del paquete se ejecutan antes de publicar. La firma Developer ID, notarización y validación física en un Mac Intel siguen pendientes.
