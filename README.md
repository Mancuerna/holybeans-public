<p align="center">
  <img src="android/app/src/main/res/drawable-nodpi/ic_launcher_art.png" width="112" alt="HolyBeans icon">
</p>
<h1 align="center">HolyBeans</h1>
<p align="center">Your coffee, from the first bean to the last sip.</p>
<p align="center">
  <a href="https://play.google.com/store/apps/details?id=com.caffeinateddev.holybeans">Get it on Google Play</a> ·
  <a href="https://holybeans.jacortes.me/docs/">User guide</a> ·
  <a href="https://holybeans.jacortes.me/home/">Website</a> ·
  <a href="README.es.md">Español</a>
</p>
<p align="center">
  <a href="https://github.com/Mancuerna/holybeans-public/actions/workflows/ci.yml"><img src="https://github.com/Mancuerna/holybeans-public/actions/workflows/ci.yml/badge.svg" alt="CI status"></a>
  <img src="https://img.shields.io/badge/platform-Android-3DDC84" alt="Platform: Android">
  <img src="https://img.shields.io/badge/built_with-Flutter-02569B" alt="Built with Flutter">
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-GPL--3.0--only-blue" alt="License: GPL-3.0-only"></a>
</p>

HolyBeans is a coffee journal for people who enjoy making, tasting and learning
about coffee. Keep your beans, recipes, equipment and tasting notes together,
then return to the cups you loved and make them again.

Your journal lives on your device. Everyday use needs no account. Google Drive
backups and device connections are optional.

## Make every cup your own

- **Know your beans.** Track roasters, origins, roast dates, remaining coffee,
  frozen portions and the coffees you have finished.
- **Find your recipe.** Record espresso and filter brews with dose, yield, grind,
  temperature, time, ratings and notes. Repeat a favourite or compare experiments.
  Save portafilter weights with their baskets and subtract the tare to fill your
  espresso dose, manually or from a connected scale.
- **Follow the brew.** Use timers, pour plans and optional connected scales or
  pressure measurements. Explore recorded curves and extraction measurements.
- **Taste and explore.** Keep personal cupping notes, record café visits and see
  how your habits change through statistics.
- **Keep your setup together.** Manage grinders, brewers, other tools and water
  recipes. Share coffee and brew cards, or print labels with supported printers.
- **Bring your journal along.** Import BeanConqueror exports and export or restore
  HolyBeans backups with photos.

English and Spanish are included, with light and dark themes. See the
[user guide](https://holybeans.jacortes.me/docs/) for walkthroughs and limitations.

## Get HolyBeans

Install the Android app from [Google Play](https://play.google.com/store/apps/details?id=com.caffeinateddev.holybeans).
The store handles app signing and updates. Release bundles (`.aab`) are publishing
artifacts, not files you can install directly on a phone.

Android 7.0 (API 24) and later are supported. The ongoing brew notification
requires Android 8.0 (API 26) or later. iOS is not supported, and this
repository does not include an iOS project.
Bluetooth and printer support varies by model and firmware; some integrations
are experimental. See [device support](docs/DEVICES.md) before choosing hardware.

Android allows HTTP connections for Meticulous and Gaggimate machines on the
local network. Optional Loffee Labs coffee search uses HTTPS and your API key;
see [integration data and credentials](docs/DEVICES.md#loffee-labs-coffee-catalog).

## Your data

The local journal works offline. You can export a backup including photos, and
optionally store independent backups in your own Google Drive. Drive backups
are **not automatic merging or live synchronization between devices**.

Migrations from schema 19 preserve existing journals, and backups from version 5
remain supported. See [data and compatibility](docs/DATA.md) and the
[privacy policy](https://holybeans.jacortes.me/).

## Build from source

Use Flutter **3.47.5** (Dart **3.13.4**), JDK **21**, and an Android SDK configured
for Flutter. After cloning this repository:

```sh
git clone https://github.com/Mancuerna/holybeans-public.git
cd holybeans-public
flutter doctor
flutter pub get
python3 -m tool.generate_release_notes
flutter gen-l10n
flutter run
```

For a locally installable development APK:

```sh
flutter build apk --debug
```

Release builds require all four environment variables: `HOLYBEANS_KEYSTORE`,
`HOLYBEANS_KEYSTORE_PASSWORD`, `HOLYBEANS_KEY_ALIAS`, and `HOLYBEANS_KEY_PASSWORD`.
Missing or blank values fail the build. For a local release-mode test with the
Android debug key, explicitly opt in:

```sh
ORG_GRADLE_PROJECT_allowDebugSigning=true flutter build apk --release
```

When invoking Gradle directly, use `-PallowDebugSigning=true` instead. This opt-in
is for local tests only; publishing requires the upload key. Complete signing
credentials take precedence over the opt-in.

A locally signed build cannot replace the Play installation unless its signing
identity matches. Keep a backup before changing how you install the app.

## Development

```sh
flutter analyze --no-pub
flutter test --no-pub test/schema_verifier_test.dart
# Full automated Flutter suite (benchmark is separate):
flutter test --no-pub
# Publishing and CI helper tests; no credentials or network required:
python3 -m unittest discover -s tool/tests
```

Generated database code is included. After changing Drift declarations, regenerate
it with `dart run build_runner build --delete-conflicting-outputs` and update the
migration tests. Localization sources are in `lib/l10n/`.

Read [CONTRIBUTING.md](CONTRIBUTING.md) for architecture, tests, Android integration
checks and device restrictions. Tests requiring an external real backup are
explicitly skipped when it is absent; CI never uploads personal journals.
See the [performance audit](docs/PERFORMANCE.md) for device measurements,
implemented optimizations and reproducible stress scenarios.

## Releases

Code changes run CI. Release Please collects changes in a release pull request.
Merging that PR creates a GitHub release; its bundle is built after validation.
**Publishing to Google Play is a separate manual action** using that same bundle.
See [release automation](docs/RELEASING.md) for setup and the exact checks.

## Contribute

Bug reports, translations and focused pull requests are welcome. Include steps
to reproduce a problem, the app version and the device model when relevant.
Please use fictional data in examples and remove personal details from logs.

## License and acknowledgements

HolyBeans is licensed under [GPL-3.0-only](LICENSE). Font and third-party notices
are included in [assets/licenses](assets/licenses/) and [assets/fonts/OFL.txt](assets/fonts/OFL.txt).

[BeanConqueror](https://github.com/graphefruit/Beanconqueror) and
[BeanStats](https://beanstats.com/) inspired parts of the workflow. HolyBeans is
an independent project with its own interface and text. See
[sources and credits](docs/SOURCES.md) for protocols, calculations and resources.
