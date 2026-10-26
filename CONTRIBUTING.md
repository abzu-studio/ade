# Contribuir

Hay dos destinos nativos: Swift Package (`Sources/Ade`, `Sources/AdeCore`, `Tests/AdeCoreTests`) y Xcode 0.3.2 (`macos/`, `native-tests/`). Para el primero, ejecuta `swift test` y conserva sus reglas en `Sources/AdeCore`; las instrucciones siguientes corresponden al segundo. Documenta cambios en el contrato del destino afectado y no mezcles sus formatos de persistencia.

Abre `macos/Ade.xcodeproj` o usa `scripts/build-mac.sh`. Mantén las reglas en `Rules.swift`, las operaciones de archivo en `LocalStore` y las vistas libres de cálculos de dominio. No añadas WebKit ni un runtime JavaScript.

Antes de entregar: ejecuta `scripts/test-native.sh`, compila y ejecuta `scripts/test-ui.sh` para cambios en flujos. Añade pruebas de invariantes o errores reales; conserva importaciones JSON v1. Los cambios de esquema requieren migración explícita y respaldo.

Conserva las licencias de los recursos de terceros. No incluyas datos de usuarios, exportaciones, capturas, credenciales, certificados, logs ni productos de compilación. Las pruebas deben usar datos sintéticos y directorios temporales. Ejecuta `python3 scripts/audit-source.py` después de preparar los archivos con Git.
