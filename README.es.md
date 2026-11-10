<p align="center">
  <img src="android/app/src/main/res/drawable-nodpi/ic_launcher_art.png" width="112" alt="Icono de HolyBeans">
</p>
<h1 align="center">HolyBeans</h1>
<p align="center">Tu café, desde el primer grano hasta el último sorbo.</p>
<p align="center">
  <a href="https://play.google.com/store/apps/details?id=com.caffeinateddev.holybeans">Disponible en Google Play</a> ·
  <a href="https://holybeans.jacortes.me/es/docs/">Guía de uso</a> ·
  <a href="https://holybeans.jacortes.me/es/home/">Web</a> ·
  <a href="README.md">English</a>
</p>
<p align="center">
  <a href="https://github.com/Mancuerna/holybeans-public/actions/workflows/ci.yml"><img src="https://github.com/Mancuerna/holybeans-public/actions/workflows/ci.yml/badge.svg" alt="Estado de CI"></a>
  <img src="https://img.shields.io/badge/platform-Android-3DDC84" alt="Plataforma: Android">
  <img src="https://img.shields.io/badge/built_with-Flutter-02569B" alt="Desarrollado con Flutter">
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-GPL--3.0--only-blue" alt="Licencia: GPL-3.0-only"></a>
</p>

HolyBeans es un diario para quienes disfrutan preparando, probando y aprendiendo
sobre café. Reúne tus granos, recetas, equipo y notas de cata para volver a esas
tazas que te gustaron y prepararlas de nuevo.

El diario vive en tu dispositivo. No necesitas una cuenta para usarlo. Las copias
en Google Drive y las conexiones con dispositivos son opcionales.

## De los granos a la taza

- **Tus cafés:** tostadores, orígenes, fechas de tueste, existencias y porciones congeladas.
- **Tus recetas:** espresso y filtro con dosis, bebida, molienda, temperatura, tiempo,
  valoraciones y notas. Repite una preparación o compara tus experimentos.
  Guarda el peso del portafiltro con su cesta y resta la tara para rellenar la
  dosis de espresso, a mano o desde una báscula conectada.
- **Durante la preparación:** temporizadores, planes de vertido, curvas y conexión
  opcional con básculas y sensores de presión.
- **Cata y cafeterías:** notas personales, visitas a cafeterías y estadísticas de tus hábitos.
- **Tu equipo:** molinos, cafeteras, herramientas y recetas de agua. Comparte fichas
  de cafés y preparaciones o imprime etiquetas con impresoras compatibles.
- **Tus datos contigo:** importación de BeanConqueror y copias de HolyBeans con fotos.

Incluye español e inglés y temas claro y oscuro. La
[guía](https://holybeans.jacortes.me/es/docs/) explica los recorridos y sus límites.

## Instalación

Descarga la app Android desde [Google Play](https://play.google.com/store/apps/details?id=com.caffeinateddev.holybeans).
Los archivos `.aab` de las releases sirven para publicar, no para instalarlos
directamente. Android es la plataforma compatible. iOS no tiene soporte y el
repositorio no incluye un proyecto para esa plataforma.

La compatibilidad Bluetooth y de impresoras depende del modelo y firmware;
algunas integraciones son experimentales. Consulta [dispositivos](docs/DEVICES.md).

Android permite conexiones HTTP con máquinas Meticulous y Gaggimate en la red
local. La búsqueda opcional de cafés en Loffee Labs usa HTTPS y tu clave de API;
consulta los [datos y credenciales de la integración](docs/DEVICES.md#loffee-labs-coffee-catalog).

## Privacidad y copias

El diario funciona sin conexión. Puedes exportarlo con sus fotos y guardar copias
opcionales en tu Google Drive. **Las copias de Drive son independientes: no fusionan
ni sincronizan automáticamente los diarios de varios dispositivos.**

Las migraciones desde el esquema 19 conservan los diarios existentes y se mantiene
la lectura de copias desde la versión 5. Consulta la
[política de privacidad](https://holybeans.jacortes.me/es/).

## Compilar desde el código fuente

Necesitas Flutter **3.47.5**, Dart **3.13.4**, JDK **21** y el SDK de Android.
Después de clonar el repositorio:

```sh
git clone https://github.com/Mancuerna/holybeans-public.git
cd holybeans-public
flutter doctor
flutter pub get
python3 -m tool.generate_release_notes
flutter gen-l10n
flutter run
```

Para generar una APK de desarrollo:

```sh
flutter build apk --debug
```

Una firma local no permite sustituir una instalación de Play con una firma distinta.
Guarda una copia del diario antes de cambiar la forma de instalar la app.

## Desarrollo

```sh
flutter analyze --no-pub
flutter test --no-pub test/schema_verifier_test.dart
# Suite completa de Flutter (el benchmark se ejecuta por separado):
flutter test --no-pub
# Tests de publicación y CI; no necesitan credenciales ni red:
python3 -m unittest discover -s tool/tests
```

El código generado de la base de datos está incluido. Tras cambiar declaraciones
Drift, regénéralo con `dart run build_runner build --delete-conflicting-outputs`
y actualiza las pruebas de migración. Las traducciones están en `lib/l10n/`.

Consulta [CONTRIBUTING.md](CONTRIBUTING.md) para arquitectura, pruebas de integración
Android y límites de uso del hardware. Los casos
que requieren una copia real externa se omiten explícitamente si no está disponible.
CI no sube diarios personales. La [auditoría de rendimiento](docs/PERFORMANCE.md)
recoge mediciones en dispositivo, optimizaciones y escenarios de estrés reproducibles.

## Releases

Release Please acumula cambios en una PR. Al integrarla se prepara la release;
**el envío a Play se ejecuta manualmente** sobre el AAB ya validado.
[Funcionamiento y configuración](docs/RELEASING.md).

## Colaborar

Puedes contribuir con informes de errores, traducciones y PR con cambios concretos.
Incluye los pasos para reproducir el problema, la versión de la app y el modelo de
dispositivo cuando sea relevante. Usa datos ficticios en los ejemplos y elimina
los datos personales de los logs. No adjuntes diarios personales, credenciales ni
fotos privadas en incidencias.

## Licencia y créditos

[GPL-3.0-only](LICENSE), con los avisos de fuentes y recursos conservados en
[assets/licenses](assets/licenses/) y [assets/fonts/OFL.txt](assets/fonts/OFL.txt).
[BeanConqueror](https://github.com/graphefruit/Beanconqueror) y
[BeanStats](https://beanstats.com/) inspiraron parte de los flujos. HolyBeans es
un proyecto independiente, con interfaz y textos propios.
[Fuentes y créditos](docs/SOURCES.md).
