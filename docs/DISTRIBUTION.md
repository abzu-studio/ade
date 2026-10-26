# Distribución

Este proceso corresponde al proyecto Xcode en `macos/` (0.4.1). El Swift Package de `Sources/` (1.0.1) usa `scripts/package-macos-app.sh`, que genera un paquete con firma ad hoc; no produce una distribución notarizada. Ambos destinos mantienen formatos de datos distintos. No intercambies sus archivos de almacenamiento sin una migración explícita.

Versión 0.4.1, compilación 15. Identificador `com.ade.mac`. Destino mínimo: macOS 14.

Antes de distribuir un instalador comercial:

1. Ejecutar las pruebas del núcleo y de interfaz en una sesión gráfica habilitada.
2. Compilar Release para `arm64 x86_64` y comprobar la aplicación en ambas arquitecturas.
3. Verificar una instalación nueva sin datos de demostración y una actualización que conserve los datos existentes.
4. Firmar con Developer ID Application, manteniendo sandbox y hardened runtime.
5. Notarizar con Apple, adjuntar el ticket y verificar Gatekeeper en un Mac limpio.
6. Revisar licencias y derechos de los recursos gráficos.

## Vista previa pública sin notarización

```sh
python3 scripts/package-mac.py preview
```

Genera `dist/preview/Ade-0.4.1-15-unsigned.dmg`, marcado explícitamente como no notarizado. Solo incluye la aplicación, un enlace a Aplicaciones e instrucciones de instalación. El workflow `xcode-release.yml` compila desde el commit publicado, verifica el paquete y adjunta el DMG, código y checksums a una prerelease. No utiliza certificados ni datos de este Mac.

## Paquete local

```sh
python3 scripts/package-mac.py local
```

Genera `dist/local/Ade-0.4.1-15-local.dmg` y su SHA-256. El disco contiene Adê y un acceso a Aplicaciones. Usa firma ad hoc, no está notarizado y no debe publicarse como instalador comercial. No modifica la aplicación instalada ni su contenedor de datos.

El proceso comprueba ambas arquitecturas, la firma, hardened runtime, los permisos del sandbox, las licencias de fuentes y la ausencia de datos o acciones de demostración. Release no permite adjuntar un depurador ni concede acceso a la red.

## Distribución con Developer ID

Requiere una membresía activa de Apple Developer Program, un certificado **Developer ID Application** con su clave privada en el llavero y un perfil de autenticación de `notarytool` guardado en ese llavero. Configura las credenciales directamente con las herramientas de Apple; no las incluyas en Git ni en argumentos del script.

```sh
python3 scripts/package-mac.py distribute \
  --identity 'Developer ID Application: DISTRIBUTOR (TEAMID)' \
  --notary-profile 'ade-notary'
```

El script firma la aplicación, la envía a Apple y exige el resultado `Accepted`. Después adjunta y valida el ticket de la aplicación, crea el DMG, lo firma, lo notariza y adjunta su ticket. Solo tras superar esas comprobaciones y Gatekeeper coloca el instalador en `dist/release/`. No publica archivos en GitHub automáticamente.

Cada intento conserva sus registros en un directorio independiente bajo `build/`. Si Apple tarda más de 30 minutos, el comando se detiene; la solicitud puede seguir procesándose. Consulta su estado antes de volver a enviar. La parte de firma Developer ID y notarización requiere validación real con las credenciales del distribuidor.

Los certificados, credenciales, datos de usuario y productos de compilación quedan fuera del repositorio. Una compilación correcta no acredita compatibilidad en todas las máquinas ni ausencia absoluta de errores.

Referencia: [Notarizar software de macOS antes de distribuirlo](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution).
