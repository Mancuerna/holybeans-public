# Changelog

## [1.8.0](https://github.com/Mancuerna/holybeans-public/compare/v1.7.0...v1.8.0) (2026-11-11)


### Features

* **share:** add adjustable photo overlay background opacity ([#39](https://github.com/Mancuerna/holybeans-public/issues/39)) ([0f0c69e](https://github.com/Mancuerna/holybeans-public/commit/0f0c69e750163fb02eaf99902000c21c8eaae40f))
* **share:** overlay charts in separate photo panels ([#41](https://github.com/Mancuerna/holybeans-public/issues/41)) ([baa0428](https://github.com/Mancuerna/holybeans-public/commit/baa04284bd3042ae43f46ab8748db037b496bd92))


### Bug Fixes

* **android:** guard live updates below API 26 ([e0d9fa1](https://github.com/Mancuerna/holybeans-public/commit/e0d9fa16167a1bdb6976ee3d21f7a9460bf07446))
* **android:** validate incoming cards and read content off the UI thread ([4444981](https://github.com/Mancuerna/holybeans-public/commit/4444981e55023bafc671c17f60e47cfd94a02c46))
* **backup:** guard manual actions and show progress ([5e85a63](https://github.com/Mancuerna/holybeans-public/commit/5e85a635af6cfaf46208ae32d8667e13dd34da04))
* **backup:** retain recovery copies and clean temporary files ([2c7baf1](https://github.com/Mancuerna/holybeans-public/commit/2c7baf11a50cffb86f40eb90edf3f7ca4b9e7577))
* **backup:** validate before replacing the journal ([fd4a5db](https://github.com/Mancuerna/holybeans-public/commit/fd4a5dbe53175d969694bdb371115dc739da0b90))
* **ble:** abort pending connections before switching devices ([949adf8](https://github.com/Mancuerna/holybeans-public/commit/949adf824cb129d808d3af3a6ac6376441f6a161))
* **ble:** share scans and reset interrupted measurements ([defd1c4](https://github.com/Mancuerna/holybeans-public/commit/defd1c42c9ebedc745690c4676ea32c847cea6e7))
* **brews:** show failures when saving curve pours ([c451aa4](https://github.com/Mancuerna/holybeans-public/commit/c451aa4617de9dcf9c4281cb2f7c7bbabf8fbec5))
* **database:** make the roaster backfill schema-independent ([a76c482](https://github.com/Mancuerna/holybeans-public/commit/a76c4826546b7b899aba17591e60cfca9170e8ca))
* **export:** neutralise spreadsheet formulas in CSV ([de948e5](https://github.com/Mancuerna/holybeans-public/commit/de948e50cc65e820c6ef2cbb1f9ab25905a2ea66))
* guard damaged lists and report recovered errors ([19d4b00](https://github.com/Mancuerna/holybeans-public/commit/19d4b00ef1a003950143c32af9a45a5de41c11b1))
* **import:** bound QR expansion and parse cards off the UI isolate ([85998a7](https://github.com/Mancuerna/holybeans-public/commit/85998a75362a3d6f050156984bc78ba3b39f318f))
* **import:** keep the import page open until it finishes ([34887b6](https://github.com/Mancuerna/holybeans-public/commit/34887b6b3c3ab7e6facd112afafaa9009bf7a3c4))
* **import:** validate external data and calendar dates ([bea8a36](https://github.com/Mancuerna/holybeans-public/commit/bea8a361515ce69f8d964c3a51af9412bdbcd126))
* **labels:** release every printer on close ([063e208](https://github.com/Mancuerna/holybeans-public/commit/063e208ee4b0b0ee56e0ae516b6329e2daa0fcdf))
* **meticulous:** bound and isolate machine responses ([b1f098e](https://github.com/Mancuerna/holybeans-public/commit/b1f098e89f61333f9c55dca276e2b62e0f442c9c))
* **preferences:** tolerate damaged stored JSON ([6daacd4](https://github.com/Mancuerna/holybeans-public/commit/6daacd4ebe2e474d04314d585dac0cfc083534b3))
* **startup:** isolate optional service failures ([#49](https://github.com/Mancuerna/holybeans-public/issues/49)) ([b12418b](https://github.com/Mancuerna/holybeans-public/commit/b12418b62578ddac04c864e475c67eba1f4fca24))
* **startup:** report framework and asynchronous failures ([#48](https://github.com/Mancuerna/holybeans-public/issues/48)) ([bc4a7f6](https://github.com/Mancuerna/holybeans-public/commit/bc4a7f690a912bc7811fba0f76f54de0a41e1e1a))
* **startup:** show recovery when the journal cannot open ([#50](https://github.com/Mancuerna/holybeans-public/issues/50)) ([a349d86](https://github.com/Mancuerna/holybeans-public/commit/a349d86e47dd86eaf1372ec4ddbd60addbe1f3cd))
* **stock:** thaw portions emptied within tolerance ([f055e37](https://github.com/Mancuerna/holybeans-public/commit/f055e377c662f39b8456e034cef9ed00e969ecb0))
* **sync:** ignore stale Drive authorization results ([5f66d29](https://github.com/Mancuerna/holybeans-public/commit/5f66d2983c2551052969c7068e3605a6a87cbbb9))
* **ui:** handle failed asynchronous operations ([76d5a02](https://github.com/Mancuerna/holybeans-public/commit/76d5a02e7b6ca0cebd8e94b947ade7128be93780))


### Performance Improvements

* **assistant:** isolate flow guide updates ([561ff65](https://github.com/Mancuerna/holybeans-public/commit/561ff6564c263ad8e633f2757585fa2c71360368))
* **assistant:** isolate pressure guide updates ([4e995bb](https://github.com/Mancuerna/holybeans-public/commit/4e995bb61e8e7b9bae644aa92d2c75dba94cfc54))
* **assistant:** retain guide chart backgrounds ([9e31356](https://github.com/Mancuerna/holybeans-public/commit/9e31356543a39e6afe3ccc2af736753143103cce))
* **assistant:** reuse pressure guide chart points ([4fb832a](https://github.com/Mancuerna/holybeans-public/commit/4fb832aa47549e9f9d994b33f2826be1a9d180e8))
* **backup:** encode manual exports in workers ([dc4dffa](https://github.com/Mancuerna/holybeans-public/commit/dc4dffa1340da4cc4ef94e6ead8a3124817470cd))
* **backup:** prepare restores in workers ([8393681](https://github.com/Mancuerna/holybeans-public/commit/839368196e02e2e06935c2310405f028bd0aa876))
* **beans:** reuse stock and search aggregations ([34e93e9](https://github.com/Mancuerna/holybeans-public/commit/34e93e9622fbaa2a7c9ccaebdbc7e4b909beddef))
* **brews:** isolate comparison playback updates ([7993e70](https://github.com/Mancuerna/holybeans-public/commit/7993e7062a209f3ac38404c9245b6e7f9e2ee6bc))
* **brews:** isolate controls from scale readings ([87f2869](https://github.com/Mancuerna/holybeans-public/commit/87f28692ff38f4ea3a400448c1efb3dc4cc48b69))
* **brews:** isolate water plan controls from readings ([7ff2bef](https://github.com/Mancuerna/holybeans-public/commit/7ff2befff48e8a7fedd41e7aa7481934797e128b))
* **brews:** retain extraction plots with complete repaint checks ([c77e36b](https://github.com/Mancuerna/holybeans-public/commit/c77e36b58fe8dbba015c21737741f4e3a4ad5db3))
* **brews:** retain unchanged comparison chart paints ([282fd69](https://github.com/Mancuerna/holybeans-public/commit/282fd69edaa7d92bd2b1eda2c10f5cf2dc063355))
* **cafes:** cache catalog decoding off the UI isolate ([614b512](https://github.com/Mancuerna/holybeans-public/commit/614b512bd2882b6ea87613b6df51e0b0c7c07009))
* **cafes:** reuse picker search data and preserve load retries ([c6aeb6b](https://github.com/Mancuerna/holybeans-public/commit/c6aeb6ba288bae87c64b5961c630e2f8eeb28061))
* **cupping:** stop timer rebuilds while scoring ([a0a37f3](https://github.com/Mancuerna/holybeans-public/commit/a0a37f3b02683ce7299f36fb2169216f9b3b4f0e))
* **database:** add journal lookup indexes ([54b4b1f](https://github.com/Mancuerna/holybeans-public/commit/54b4b1fd6111c90c97dd2c9ef61f19b7d4bb14ed))
* **database:** narrow photo cleanup and archive queries ([a1f9458](https://github.com/Mancuerna/holybeans-public/commit/a1f9458e58aa738040cfaedc0692b588a0b4f60f))
* **database:** narrow tool lookup reads ([287d578](https://github.com/Mancuerna/holybeans-public/commit/287d5781d811cca215d4f6dce46e00c003bd02f1))
* **database:** project import metadata columns ([1242719](https://github.com/Mancuerna/holybeans-public/commit/12427191f559552bf0d6cbcef25e9cd3c7a34fb3))
* **database:** scope stock adjustment streams ([d85bd29](https://github.com/Mancuerna/holybeans-public/commit/d85bd29fe8bb57c60ab15c3d17bf7a333eafc32a))
* **drive:** verify unchanged photos by checksum ([e15f13c](https://github.com/Mancuerna/holybeans-public/commit/e15f13c62f66d2e1486f9824343e1d4c1e18b3af))
* **freshness:** reuse calculations for unchanged lots ([1ed5964](https://github.com/Mancuerna/holybeans-public/commit/1ed5964db111121ce7c3b12011645ec3edda57bd))
* **home:** reuse stock and recipe aggregations ([4ef029a](https://github.com/Mancuerna/holybeans-public/commit/4ef029a657bc8c1f45762ab47c26a84f2ba5554d))
* **labels:** convert raster pixels in a worker ([fd128a8](https://github.com/Mancuerna/holybeans-public/commit/fd128a8bfa6db168403a7f9c09b87bea9a3fa091))
* **labels:** debounce preview raster requests ([e4675f8](https://github.com/Mancuerna/holybeans-public/commit/e4675f8070f47e9f5a2de7461dcce938fdb6b023))
* **piston:** reuse analysis during sync progress ([5466720](https://github.com/Mancuerna/holybeans-public/commit/54667200e7c2ea78d1d8b1014aa1a79ece2401dd))
* **roasters:** reuse profiles for unchanged snapshots ([340acf7](https://github.com/Mancuerna/holybeans-public/commit/340acf7900c9cc87c0a68228b8bc5bd04f9faf4d))
* **shell:** retain unchanged offscreen journal tabs ([d711fdf](https://github.com/Mancuerna/holybeans-public/commit/d711fdfbfd74fd311a6c54484f0f18375aded096))
* **stats:** retain content while refreshing large histories ([0d09cf7](https://github.com/Mancuerna/holybeans-public/commit/0d09cf75dee504bdb60272410f0bb7d3133b19b1))
* **stats:** retain unchanged chart paints ([16dd684](https://github.com/Mancuerna/holybeans-public/commit/16dd684962c3ec8d952686f7d7a67223bc81b458))
* **stats:** reuse snapshot aggregates across tab builds ([b1e33c5](https://github.com/Mancuerna/holybeans-public/commit/b1e33c5d9cf83f1475eeba75d825c7796b21bf1a))
* **ui:** cache numeric field formatters ([09bc17d](https://github.com/Mancuerna/holybeans-public/commit/09bc17d9d7191b8fad5389220f2c4c65e6a1e816))
* **ui:** complete audit rendering optimizations ([ced6e0b](https://github.com/Mancuerna/holybeans-public/commit/ced6e0b3838c5c2fa98dd65baabc705692795ba0))
* **ui:** retain unchanged equipment chart paints ([8583185](https://github.com/Mancuerna/holybeans-public/commit/858318502f0200aed23b90aa4ad41d06a57d35bc))
* **year-review:** prepare large histories in a worker ([8036f31](https://github.com/Mancuerna/holybeans-public/commit/8036f31ed97a23960c9994d99e195650794b4ee5))

## [1.7.0](https://github.com/Mancuerna/holybeans-public/compare/v1.6.0...v1.7.0) (2026-11-09)


### Features

* **espresso:** weigh doses with saved portafilter tares ([#36](https://github.com/Mancuerna/holybeans-public/issues/36)) ([e8b48ad](https://github.com/Mancuerna/holybeans-public/commit/e8b48ad8bac1b4f6cf7ef09ec1d88d9cc8f528e6))
* **labels:** add horizontal and vertical image adjustments ([642c275](https://github.com/Mancuerna/holybeans-public/commit/642c275a94d34c7a6968e3a3e5d7859c62fa710c))
* **labels:** support Pristar Marklife P12 continuous tape ([#35](https://github.com/Mancuerna/holybeans-public/issues/35)) ([f5ffc16](https://github.com/Mancuerna/holybeans-public/commit/f5ffc1606d3650a13a95629d17885124ea72193b))
* **recap:** add visual stories and shareable year carousels ([55b5c70](https://github.com/Mancuerna/holybeans-public/commit/55b5c70b30943d1ca18c2e5893f3ef932fc7ff38))
* **scales:** support Timemore Dot with acknowledged timer controls ([2cc01e9](https://github.com/Mancuerna/holybeans-public/commit/2cc01e97fb52ab9bcbc25ac842a5c86dbca63ebb))
* **templates:** add days from roast tag ([#31](https://github.com/Mancuerna/holybeans-public/issues/31)) ([c1c1373](https://github.com/Mancuerna/holybeans-public/commit/c1c1373587575e8bbcda70531034cd613f2bb1f0))


### Bug Fixes

* **brews:** replace stale bloom totals with measured time ([ae4d87a](https://github.com/Mancuerna/holybeans-public/commit/ae4d87aa80264ec90d3f5ee489d0f8079bc47029))

## [1.6.0](https://github.com/Mancuerna/holybeans-public/compare/v1.5.0...v1.6.0) (2026-11-06)


### Features

* **sharing:** overlay brew details on coffee photos ([db7e51d](https://github.com/Mancuerna/holybeans-public/commit/db7e51dceb467d978635e72c458526b78a978c97))


### Bug Fixes

* **brews:** show flow guide weights and prioritize equipment details ([#26](https://github.com/Mancuerna/holybeans-public/issues/26)) ([de5cc8d](https://github.com/Mancuerna/holybeans-public/commit/de5cc8db39dd820799210fb7a63809fa0d4d161f))
* complete scale recording and release notes improvements ([#29](https://github.com/Mancuerna/holybeans-public/issues/29)) ([61838c0](https://github.com/Mancuerna/holybeans-public/commit/61838c08e26d552872b89575034996e1715458f4))
* **freshness:** clarify roaster rest and improve phase contrast ([#28](https://github.com/Mancuerna/holybeans-public/issues/28)) ([1b52d7c](https://github.com/Mancuerna/holybeans-public/commit/1b52d7c3fe744729f869a02728540965f04df62c))

## [1.5.0](https://github.com/Mancuerna/holybeans-public/compare/v1.4.1...v1.5.0) (2026-11-05)


### Features

* add a little stir between sips ([#24](https://github.com/Mancuerna/holybeans-public/issues/24)) ([f2af7d4](https://github.com/Mancuerna/holybeans-public/commit/f2af7d49d0933eb1ec08c351ca770b1b242b438f))


### Bug Fixes

* **charts:** align markers with the displayed extraction curve ([3e4a038](https://github.com/Mancuerna/holybeans-public/commit/3e4a03853112ba9b4372b2a0a9baf1a59c4e0f0d))
* **charts:** preserve recorded curves and time-weight flow smoothing ([7953cd5](https://github.com/Mancuerna/holybeans-public/commit/7953cd5dd683cb8e1c7e0bd7f3a450b4f2478bee))
* **release-notes:** generate in-app notes from the current release ([bdccbc5](https://github.com/Mancuerna/holybeans-public/commit/bdccbc560c563088a07a7b91ffcdd70ab98290ff))
* **ui:** show brew details before the curve and simplify settings ([#22](https://github.com/Mancuerna/holybeans-public/issues/22)) ([dae8068](https://github.com/Mancuerna/holybeans-public/commit/dae8068b183041e8adf69e7403774c10b1b71419))

## [1.4.1](https://github.com/Mancuerna/holybeans-public/compare/v1.4.0...v1.4.1) (2026-11-04)


### Bug Fixes

* add five-minute reminders and searchable cupping coffees ([0421d1c](https://github.com/Mancuerna/holybeans-public/commit/0421d1cb7bbba0b785225df485d387a21c877a88))


### Performance Improvements

* bound journal reads and incrementally prepare live curves ([c55c571](https://github.com/Mancuerna/holybeans-public/commit/c55c571bc78c92c344ef3119d22b1702c6a344a3))
* **journal:** keep large journals responsive ([#16](https://github.com/Mancuerna/holybeans-public/issues/16)) ([19a5225](https://github.com/Mancuerna/holybeans-public/commit/19a5225491e21f61ce7c4223a97966bb97aca5d7))

## [1.4.0](https://github.com/Mancuerna/holybeans-public/compare/v1.3.0...v1.4.0) (2026-11-04)


### Features

* add brew scale reset and responsive label editing ([484e71a](https://github.com/Mancuerna/holybeans-public/commit/484e71a0d5a9453b0cf0b906e55deae13e457d3b))
* **brews:** open coffee details from brew title ([4b29f0c](https://github.com/Mancuerna/holybeans-public/commit/4b29f0ce90a3f2d793131b7951b862aefd402e15))
* **equipment:** allow deleting unused methods and water profiles ([#14](https://github.com/Mancuerna/holybeans-public/issues/14)) ([b15f2a8](https://github.com/Mancuerna/holybeans-public/commit/b15f2a87754276b91986cba29b21243a3db9b0aa))


### Bug Fixes

* **release-notes:** announce unused equipment deletion ([#15](https://github.com/Mancuerna/holybeans-public/issues/15)) ([f8c849e](https://github.com/Mancuerna/holybeans-public/commit/f8c849ed3f003de9a231c4435b62321907b74fb2))

## [1.3.0](https://github.com/Mancuerna/holybeans-public/compare/v1.2.1...v1.3.0) (2026-11-03)


### Features

* **brews:** add gravimetric flow guide ([6ce55ea](https://github.com/Mancuerna/holybeans-public/commit/6ce55ea131792394717b7544ac61ccd513de53a2))
* **sharing:** copy brew text and images to clipboard ([543e21f](https://github.com/Mancuerna/holybeans-public/commit/543e21f295c66b5f2f44935e809f64a272a40563))


### Bug Fixes

* **brews:** reveal final weight after filter recording ([703250c](https://github.com/Mancuerna/holybeans-public/commit/703250c4a6ac62696cb837d52f911bbe2c508101))

## [1.2.1](https://github.com/Mancuerna/holybeans-public/compare/v1.2.0...v1.2.1) (2026-11-03)


### Bug Fixes

* **android:** include QR scanner ProGuard rules in release builds ([242cfca](https://github.com/Mancuerna/holybeans-public/commit/242cfcaad405644329815df7768f4a48402ed47b))

## [1.2.0](https://github.com/Mancuerna/holybeans-public/compare/v1.1.19...v1.2.0) (2026-11-03)


### Features

* **scales:** capture saved BOOKOO coffee doses ([7ecf744](https://github.com/Mancuerna/holybeans-public/commit/7ecf74466d5429bdcd19d212d2d0d9cb45f56c59))

## 1.1.19

- Share coffee and brew cards with transparent backgrounds and light or dark text.
- Add experimental Niimbot D11 and D11-H label-printer profiles.
- Refine espresso ratio suggestions and rounding.

This source snapshot continues the existing Android app version sequence.
The presence of an entry here does not indicate Google Play review approval.
