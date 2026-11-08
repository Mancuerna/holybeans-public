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
directamente. El proyecto iOS está incluido, pero su publicación y funcionamiento
en dispositivos aún no están validados.

La compatibilidad Bluetooth y de impresoras depende del modelo y firmware;
algunas integraciones son experimentales. Consulta [dispositivos](docs/DEVICES.md).

## Privacidad y copias

El diario funciona sin conexión. Puedes exportarlo con sus fotos y guardar copias
opcionales en tu Google Drive. **Las copias de Drive son independientes: no fusionan
ni sincronizan automáticamente los diarios de varios dispositivos.**

Las migraciones conservan los diarios existentes y se mantiene la lectura de
copias desde la versión 19. Consulta la [política de privacidad](https://holybeans.jacortes.me/es/).

## Compilar y colaborar

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

Para generar una APK de desarrollo: `flutter build apk --debug`. Una firma local
no permite sustituir una instalación de Play con una firma distinta.

```sh
flutter analyze --no-pub
flutter test --no-pub
python3 -m unittest discover -s tool/tests
```

Consulta [CONTRIBUTING.md](CONTRIBUTING.md) para arquitectura y pruebas. Los casos
que requieren una copia real externa se omiten explícitamente si no está disponible.
No adjuntes diarios personales, credenciales ni fotos privadas en incidencias.

Release Please acumula cambios en una PR. Al integrarla se prepara la release;
**el envío a Play se ejecuta manualmente** sobre el AAB ya validado.
[Funcionamiento y configuración](docs/RELEASING.md).

## Licencia y créditos

[GPL-3.0-only](LICENSE), con los avisos de fuentes y recursos conservados en
[assets/licenses](assets/licenses/) y [assets/fonts/OFL.txt](assets/fonts/OFL.txt).
[BeanConqueror](https://github.com/graphefruit/Beanconqueror) y
[BeanStats](https://beanstats.com/) inspiraron parte de los flujos. HolyBeans es
un proyecto independiente, con interfaz y textos propios.
[Fuentes y créditos](docs/SOURCES.md).
