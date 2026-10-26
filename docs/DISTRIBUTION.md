# Distribución

Versión 0.3.2, compilación 11. Identificador `com.ade.mac`. Destino mínimo: macOS 14.

Antes de distribuir un instalador comercial:

1. Ejecutar las pruebas del núcleo y de interfaz en una sesión gráfica habilitada.
2. Compilar Release para `arm64 x86_64` y comprobar la aplicación en ambas arquitecturas.
3. Verificar una instalación nueva sin datos de demostración y una actualización que conserve los datos existentes.
4. Firmar con Developer ID Application, manteniendo sandbox y hardened runtime.
5. Notarizar con Apple, adjuntar el ticket y verificar Gatekeeper en un Mac limpio.
6. Revisar licencias y derechos de los recursos gráficos.

Los scripts usan firma ad hoc para verificación local. No incluyen certificados, credenciales, datos de usuario ni instaladores. Una compilación correcta no acredita notarización, compatibilidad en todas las máquinas ni ausencia absoluta de errores.
