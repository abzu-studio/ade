# Arquitectura 0.4.1

- `Domain.swift`: entidades y codificación JSON v1.
- `Rules.swift`: validación, operaciones de dominio, cálculos, sugerencias y revisiones.
- `AppModel.swift`: estado observable en MainActor, comandos, navegación e importación.
- `LocalStore.swift`: actor de almacenamiento, archivos atómicos, bloqueo y control de concurrencia por SHA-256.
- `NativePDF.swift`: documentos mediante las API nativas de macOS.
- Vistas SwiftUI: catálogos, asistencia, participación y documentos.
- `Theme.swift`, `PaperAtmosphere.swift` y `PaperMotion.swift`: apariencia y movimiento.
- `DevelopmentFixtures.swift`: datos sintéticos exclusivos de Debug.

No contiene WebKit, un servidor web ni un runtime JavaScript. MainActor coordina la interfaz; LocalStore prepara transacciones, cálculos y serialización fuera del hilo principal. El formato persistido permanece en versión 1.
