# Adê 0.4.5 · macOS

Edición nativa SwiftUI/Xcode, compilación 19. Requiere macOS 14 o posterior; incluye Apple Silicon e Intel. Compilada con Xcode 27.0 (27A266a) y Apple Swift 6.4 (swiftlang-6.4.0.34.1), el mismo toolchain de la versión local verificada.

## Cambios desde 0.4.1

- Fondo con dither animado y reflejos continuos, adaptado a los cuatro temas y más visible en los temas claros.
- Elimina la franja inferior reservada y las bandas verticales que separaban el efecto del contenido.
- Barra lateral, cabeceras y paneles con translucidez y reflejos móviles.
- Dither animado dentro de botones principales, pestaña seleccionada e indicador de asistencia; las etiquetas permanecen nítidas.
- La animación respeta Reducir movimiento, Reducir transparencia, mayor contraste, el modo de bajo consumo y la opción de movimiento de Adê. Se pausa cuando la ventana está inactiva.

## Descargas

- `Ade-0.4.5-19-unsigned.dmg`: aplicación e instrucciones de instalación.
- `Ade-0.4.5-source.zip`: proyecto Xcode exacto usado para compilar, reglas, pruebas y licencias.
- `SHA256SUMS.txt`: hashes del DMG y del código.
- `BUILD.txt`: commit, ejecución de compilación y versiones de Xcode y Swift.

## Instalación y datos

Abre el DMG y arrastra Adê a Aplicaciones. La descarga no contiene registros personales, credenciales, espacios de demostración ni herramientas de prueba. Las instalaciones nuevas empiezan vacías. Conserva el identificador `com.ade.mac` y el formato de datos de las ediciones Xcode 0.4.x: reemplazar la aplicación conserva los espacios existentes. Puedes exportar una copia desde Datos antes de actualizar.

**Firma ad hoc, sin certificado Developer ID ni notarización de Apple.** macOS puede bloquear la primera apertura. Si confías en la descarga, consulta las [instrucciones de Apple para abrir una app bloqueada](https://support.apple.com/es-es/102445); no es necesario desactivar Gatekeeper.

El Swift Package 1.0.1 que también existe en este repositorio es otra edición, con distinto contenedor y formato. No migra automáticamente sus datos a este DMG.

## Verificación

Las pruebas de interfaz locales comprobaron los cuatro temas, movimiento real en el fondo, barra lateral y botones, controles inmóviles, disposición compacta y estabilidad al desactivar la animación. Se verificó la actualización local conservando el archivo de datos. GitHub Actions vuelve a ejecutar las pruebas del núcleo, persistencia y PDF, y verifica el paquete universal, permisos, firma y ausencia de archivos privados antes de publicar. La notarización y la validación física en un Mac Intel siguen pendientes.
