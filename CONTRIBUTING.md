# Contribuir a Hera

¡Gracias por tu interés en contribuir a Hera! Este documento proporciona información sobre cómo contribuir al proyecto.

## Estructura del Proyecto

El proyecto está organizado de la siguiente manera:

```
App/                          # Directorio principal de la aplicación
├── Hera.xcodeproj/           # Archivo de proyecto Xcode
├── Hera/                     # Código principal de la app
│   ├── Sources/
│   │   ├── App/              # Punto de entrada de la aplicación
│   │   ├── Models/           # Modelos de datos
│   │   ├── Views/            # Vistas de SwiftUI
│   │   ├── Services/         # Servicios (OpenAI, Audio, etc.)
│   │   ├── Utils/            # Utilidades comunes
│   │   └── Extensions/       # Extensiones de Swift/UIKit
│   ├── Assets.xcassets/      # Recursos gráficos de la aplicación
│   ├── Info.plist            # Configuración de la aplicación
│   └── Hera.entitlements     # Entitlements de la aplicación
├── HeraTests/                # Tests unitarios
├── HeraUITests/              # Tests de UI
└── Resources/                # Recursos de la aplicación
    ├── Banner/               # Imágenes de banner para el README
    └── Icon/                 # Iconos de la aplicación
```

## Directrices de Código

- Usa SwiftUI para las interfaces de usuario cuando sea posible
- Sigue la arquitectura MVVM (Model-View-ViewModel)
- Usa servicios para operaciones complejas o de red
- Comenta tu código adecuadamente
- Escribe nombres descriptivos para variables y funciones

## Proceso de Pull Request

1. Crea un fork del repositorio
2. Crea una rama con un nombre descriptivo
3. Realiza tus cambios
4. Asegúrate de que los tests pasan
5. Envía un Pull Request con una descripción clara de los cambios

## Convenciones de Commit

Por favor, sigue estas convenciones para los mensajes de commit:

- `feat`: Nueva característica
- `fix`: Corrección de un bug
- `docs`: Cambios en la documentación
- `style`: Formateo, punto y coma faltantes, etc.
- `refactor`: Refactorización del código
- `test`: Añadir o refactorizar tests
- `chore`: Cambios en el proceso de build, herramientas, etc.

Ejemplo: `feat: añadir detección de calendario en transcripciones`

## Licencia

Al contribuir a este proyecto, aceptas que tus contribuciones serán licenciadas bajo la misma licencia MIT que cubre el proyecto. 