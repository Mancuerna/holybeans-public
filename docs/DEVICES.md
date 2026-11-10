# Device integrations

Hardware compatibility depends on the model, firmware and platform. Protocol
support is not a claim that every combination has been physically tested.

HolyBeans includes Bluetooth scale adapters for **Acaia, BOOKOO, DiFluid and
Timemore**. Support is limited to the protocols and models implemented by each
adapter; it does not cover every scale sold by these brands. DiFluid R2
refractometers and BOOKOO pressure sensors have separate integrations.
Meticulous and Gaggimate history integrations read documented machine endpoints
without changing machine state.

Android permits cleartext HTTP (`usesCleartextTraffic="true"`) so Meticulous and
Gaggimate can be reached at their configured addresses on the local network.
That manifest setting applies to the app as a whole, not just those two hosts.
Use machine addresses on a trusted local network. The Loffee Labs integration
below uses HTTPS.

For a new espresso, **Extraction assistant** offers **Pressure** and **Flow**
reference modes. Flow needs only a connected Bluetooth scale and an earlier
espresso with a usable cup-weight curve. Both the reference and live flow are
calculated from weight in g/s with the same trailing one-second smoothing;
machine flow in ml/s is never treated as gravimetric flow. Start the timer at
the same point as in the original shot. Pauses, missing readings, tare and
sudden load changes interrupt the displayed trace. The assistant does not
control the machine or stop it at the end of the reference.

BOOKOO Themis Ultra dose capture has been physically verified on Android with
firmware 4.0.1. With a brew form open and the scale in Ratio mode, double-tap the
left (power/timer) button to save the weighed dose and fill HolyBeans' dose field.
Manual entry and the existing copy-weight button remain available. The right
button tares the scale. Dose notifications require compatible firmware (release
4.0.0 or later, or beta 3.2.4 or later, according to the maker's
[protocol](https://github.com/BooKooCode/OpenSource/blob/main/bookoo_ultra_scale/protocols.md#receiving-powder-weight)).

Niimbot label printing is experimental. Initial prints have been confirmed on
D110, B1, B1 Pro and D11-H. D11-H has been tried with 12 × 40 mm paper; margins
and broader reliability still need validation. D11, B21 variants, B2 and other
listed models without confirmed physical tests remain unverified. A selectable
model is not a guarantee of compatibility.

Pristar / Marklife P12 support is experimental. A user confirmed a legible
40 mm test design on continuous 15 mm tape. The printable height is 12 mm;
30, 40 (default) and 50 mm design lengths are available, followed by about
12.5 mm of feed for manual cutting. Other firmware, gap labels and other
Marklife models have not been validated. Disconnect Marklife before searching
for the P12 in the coffee label editor. Templates, images and saved printer/size
preferences use the same editor as Niimbot.

The P12 uses the published [Marklife L11 protocol](https://thermal-label.github.io/marklife/protocol/l11),
checks the advertised name and required GATT characteristics, and respects
printer credits and negotiated MTU. Each copy requires a device acknowledgement
before another starts; acknowledgement alone does not verify physical output.
Connection diagnostics omit device addresses, names and label contents.

Printing always starts from a user action. Do not retry automatically after an
uncertain result or issue calibration, firmware, power or unrelated settings
commands. See [contribution boundaries](../CONTRIBUTING.md#hardware-boundaries).

Timemore Dot TES017 supports weight in grams, tare and start/pause/reset of its
timer. Weight and controls were confirmed with a physical v1.0.4 scale in Scale
Lab; the production integration is covered by transport tests and a replay of
the captured control sequence. Other firmware versions remain unverified.
Close other apps connected to the scale and accept Bluetooth pairing if asked.
Ounce readings are not converted or displayed as grams.

The adapter checks the standard model/manufacturer identity before sending
protocol commands. It accepts the reserved zero CRC trailer only for verified
TES017 / TIMEMORE firmware v1.0.4; other firmware retains CRC validation.
Startup reads units, battery and timer state without changing settings. Timer
state follows notifications and acknowledged controls; an ACK's success byte
is never interpreted as the requested timer action. Commands are serialized,
and an uncertain command requires reconnection before another control is sent.
The implementation uses the manufacturer's
[BLE protocol](https://github.com/TIMEMORE-COFFEE/open-scale-protocol/blob/main/Timemore%20Black%20Mirror%20SCALE%20BLE%20Protocol.md).

## Loffee Labs coffee catalog

Loffee Labs search is optional and requires the user's API key. A search sends
the entered search text, page number and page size to
`https://www.loffeelabs.com/api/v2/beans`, with the key in the HTTPS Authorization
header. It does not upload the journal, tasting notes or local photos. Selecting
a coffee opens a review before saving its catalog data in the journal.

Catalog photos are downloaded from their HTTPS image URLs without the API key.
The client does not follow redirects on authenticated requests or photo downloads.

On Android, the API key is encrypted with AES-GCM using an Android Keystore key
and stored in `noBackupFilesDir/loffee-key.enc`. It is separate from journal
preferences and excluded from HolyBeans and Android backups. The search screen's
key settings allow it to be replaced or deleted; a new installation needs its
own key configuration.
