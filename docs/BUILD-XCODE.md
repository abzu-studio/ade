# Compilar Adê 0.4.6 (20)

Requiere macOS 14+, Xcode 27.0 (27A266a), Apple Swift 6.4 (swiftlang-6.4.0.34.1) y Python 3. El proyecto Xcode está generado e incluido; XcodeGen solo es necesario si se modifica `macos/project.yml`.

Desde la raíz del archivo de código:

```sh
bash scripts/verify-toolchain.sh
./scripts/test-native.sh
python3 scripts/package-mac.py preview
```

El DMG universal queda en `dist/preview/`. Este modo usa firma ad hoc y no envía nada a Apple. Para Developer ID y notarización, consulta `docs/DISTRIBUTION.md`.

Para editar y ejecutar las pruebas de interfaz, abre `macos/Ade.xcodeproj`, elige el esquema Ade y ejecuta Product → Test. Los tests utilizan directorios y preferencias aislados. Las muestras de `DevelopmentFixtures.swift` y los accesos de prueba solo se compilan en Debug.

`docs/RULES-XCODE.md` describe las reglas y `docs/ARCHITECTURE-XCODE.md` sus responsabilidades. Esta edición no requiere Node, un servidor ni dependencias web.
