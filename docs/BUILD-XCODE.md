# Compilar Adê 0.4.1 (15)

Requiere macOS 14+, Xcode 16.4 o posterior y Python 3. El proyecto Xcode está generado e incluido; XcodeGen solo es necesario si se modifica `macos/project.yml`.

Desde la raíz del archivo de código:

```sh
./scripts/test-native.sh
python3 scripts/package-mac.py preview
```

El DMG universal queda en `dist/preview/`. Este modo usa firma ad hoc y no envía nada a Apple. Para Developer ID y notarización, consulta `docs/DISTRIBUTION.md`.

Para editar y ejecutar las pruebas de interfaz, abre `macos/Ade.xcodeproj`, elige el esquema Ade y ejecuta Product → Test. Los tests utilizan directorios y preferencias aislados. Las muestras de `DevelopmentFixtures.swift` y los accesos de prueba solo se compilan en Debug.

`docs/RULES-XCODE.md` describe las reglas y `docs/ARCHITECTURE-XCODE.md` sus responsabilidades. Esta edición no requiere Node, un servidor ni dependencias web.
