# Sources and credits

HolyBeans has its own interface, data model and explanatory text. These sources
inform its calculations and integrations; their names do not imply endorsement.

## Coffee and water

- [Coffee Ad Astra: Water for Coffee Extraction](https://coffeeadastra.com/2018/12/16/water-for-coffee-extraction/)
- [Barista Hustle: DIY Water Recipes Redux](https://www.baristahustle.com/diy-water-recipes-redux/)
- [Espresso Aficionados: Water](https://espressoaf.com/guides/water.html)
- [Lotus Water instructions](https://lotuscoffeeproducts.com/pages/product-instructions)
- [GWO brewing](https://gwo.coffee/pages/brewing)
- [SCA sample preparation, SCA-102-2024](https://sca.coffee/s/AW_SCA-102_Sample-Preparation_281024_Secured.pdf)
- [Barista Hustle cupping protocol](https://www.baristahustle.com/wp-content/uploads/2024/01/Barista-Hustle-Cupping-Protocols-10_01_2024.pdf)
- [World Coffee Research sensory lexicon](https://worldcoffeeresearch.org/resources/sensory-lexicon)
- [Research on espresso brewing ratios and sensory properties](https://doi.org/10.1111/1750-3841.16531)

Cupping tools are for personal notes; they are not a certification or an official
professional scoring system. Water presets retain their source links in the app.

## Devices and resources

- [NiimBlueLib](https://github.com/MultiMote/niimbluelib): community Niimbot protocol;
  [MIT notice](../assets/licenses/niimbluelib.txt).
- [Marklife L11 wire protocol](https://thermal-label.github.io/marklife/protocol/l11):
  independent P12/P15 encoders.
- [Fichero 5836 wire reference](https://github.com/0xMH/fichero-printer/blob/main/docs/PROTOCOL.md):
  independent AiYin D11s encoder and acknowledgement/error handling.
- Typonos PM240: independent TSPL encoder derived from the Labelnize 4.10.0
  device profile and command path, then physically tested in Printer Lab.
  No Labelnize binaries or proprietary source code are included.
- [Meticulous integration](https://github.com/cjborchert/ha-meticulous) and
  [cards](https://github.com/cjborchert/ha-meticulous-cards):
  [MIT notices](../assets/licenses/meticulous-piston.txt).
- Acaia implementation attribution: [aioacaia MIT notice](../assets/licenses/aioacaia.txt).
- [Gaggimate](https://github.com/jniebuhr/gaggimate): documented history format and read-only endpoints.
- IBM Plex: [font license](../assets/fonts/OFL.txt).
- Noto Emoji: [font license](../assets/licenses/noto-emoji.txt).
- Café catalogue source: [Coffee & Translation map](https://coffeeandtranslation.com/pages/mapa-cafe-especialidad).
  Municipality enrichment uses [geoBoundaries](https://www.geoboundaries.org/)
  and [Portugal DGT CAOP](https://www.dgterritorio.gov.pt/atividades/cartografia/cartografia-tematica/caop).

The offline café catalogue contains venue names, categories and coordinates
from the public map retrieved on 23 October 2026; it contains no reviews,
descriptions or photographs. Source URLs and municipality metadata are retained
in the JSON and the source is credited in the app. Spanish municipality enrichment
uses geoBoundaries gbOpen ESP ADM3 (IGN/Open Data ESRI, CC BY 4.0); Portuguese
municipality enrichment uses DGT CAOP2025 with source attribution. No boundary
geometries are bundled. The application's code license does not relicense
third-party source material.

[BeanConqueror](https://github.com/graphefruit/Beanconqueror) and
[BeanStats](https://beanstats.com/) inspired workflow ideas. BeanConqueror import
is implemented as a separate compatibility feature.
