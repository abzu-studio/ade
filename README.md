# Adê para Mac

Aplicación nativa en SwiftUI para organizar espacios, personas, eventos, voluntariado, asistencia y documentos. Requiere macOS 14 o posterior. Los datos se guardan localmente, sin servicios de red.

Versión **0.3.2 (11)**.

## Funciones

- Personas activas e inactivas; grupos con fechas de pertenencia.
- Períodos, componentes y categorías.
- Eventos con participantes, capacidad, duplicación y cancelación.
- Asistencia con notas, historial y resultados individuales generales, por componente y por categoría.
- Sugerencias de voluntariado con puntuación visible y selección manual.
- Plantillas PDF con texto, imágenes, columnas y fondos PDF.
- Importación y exportación JSON, revisiones recuperables y versiones en conflicto.
- Español e inglés; temas Índigo y Grafito de día y de noche; movimiento adaptado a accesibilidad.

## Compilar y verificar

Abre `macos/Ade.xcodeproj` en Xcode con un SDK de macOS 14 o posterior. El proyecto está incluido; XcodeGen solo es necesario para regenerarlo desde `macos/project.yml`.

```sh
xcodebuild -project macos/Ade.xcodeproj -scheme Ade \
  -configuration Release -derivedDataPath build/ReleaseDerived \
  CODE_SIGN_IDENTITY=- build
./scripts/test-native.sh
./scripts/test-ui.sh
python3 scripts/audit-source.py
```

La firma ad hoc permite verificación local; no produce una distribución notarizada. Las pruebas de interfaz requieren una sesión gráfica de macOS habilitada para Xcode y usan datos temporales aislados. Los ejemplos se compilan únicamente en Debug.

## Documentación

[Reglas](docs/RULES.md) · [Arquitectura](docs/ARCHITECTURE.md) · [Distribución](docs/DISTRIBUTION.md) · [Privacidad](PRIVACY.md) · [Contribuir](CONTRIBUTING.md).

Código bajo [licencia MIT](LICENSE). Las fuentes conservan sus [licencias OFL](THIRD_PARTY_NOTICES.md).
