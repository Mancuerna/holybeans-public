# Device integrations

Hardware compatibility depends on the model, firmware and platform. Protocol
support is not a claim that every combination has been physically tested.

HolyBeans includes Bluetooth scale adapters for **Acaia, BOOKOO, DiFluid and
Timemore**. Support is limited to the protocols and models implemented by each
adapter; it does not cover every scale sold by these brands. DiFluid R2
refractometers and BOOKOO pressure sensors have separate integrations.
Meticulous and Gaggimate history integrations read documented machine endpoints
without changing machine state.

Bluetooth GATT operations are serialized per device, so a slow operation on a
scale or printer does not hold up the BOOKOO pressure sensor's connection or
transmission controls. Reconnecting waits for the previous stop-transmission
command and Bluetooth disconnect to finish; an old close must not tear down the
replacement connection. These cases are covered by simulated transport tests.
They do not establish the cause of every physical disconnect; reports during
measurement still need a device log and confirmation on the affected hardware.

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

The label editor remembers a default template separately for coffee bags and
frozen portions. Select a saved template and choose **Use by default**; save any
pending edits first. To restore the built-in format, select **Basic template**
and choose **Use by default**. Deleting the default also restores the basic
format. These choices are included in journal backups.

Opening the label editor attempts to connect to the paired device for the saved
printer model. Selecting another paired model also attempts an automatic
connection, unless it was disconnected during this visit. Manual **Connect**
remains available if the printer is off, unavailable or Bluetooth is disabled.
Disconnecting does not trigger an automatic retry, and leaving the editor closes
the connection. Printing still requires pressing **Print**.

Niimbot label printing is experimental. Initial prints have been confirmed on
D110, B1, B1 Pro and D11-H. D11-H has been tried with 12 × 40 mm paper; margins
and broader reliability still need validation. D11, B21 variants, B2 and other
listed models without confirmed physical tests remain unverified. A selectable
model is not a guarantee of compatibility.

Select **D110_M** for devices advertising `D110_M-…` or `D110M-…`; the D110
profile deliberately excludes this different model. D110_M support checks model
ID 2320 and negotiates the print task using the printer's protocol response,
following [NiimBlueLib's task mapping](https://github.com/MultiMote/niimbluelib/blob/35110a716c960448ee17a9270e4c3a131149866f/src/print_tasks/index.ts).
It uses a 96-dot, 203 dpi head and remains unverified on physical hardware in
HolyBeans. Disconnect the official Niimbot app before searching in HolyBeans.
Connection reports include scan start, failure and supported-device count,
without advertised names, addresses or label contents.

Pristar / Marklife P12 support is experimental. A user confirmed a legible
40 mm test design on continuous 15 mm tape. The printable height is 12 mm;
30, 40 (default) and 50 mm design lengths are available, followed by about
12.5 mm of feed for manual cutting. Other P12 firmware and gap labels have not
been validated. Disconnect Marklife before searching for the P12 in the coffee label editor. Templates, images and saved printer/size
preferences use the same editor as Niimbot.

The P12 uses the published [Marklife L11 protocol](https://thermal-label.github.io/marklife/protocol/l11),
checks the advertised name and required GATT characteristics, and respects
printer credits and negotiated MTU. Each copy requires a device acknowledgement
before another starts; acknowledgement alone does not verify physical output.
Connection diagnostics omit device addresses, names and label contents.

Pristar / Marklife P15, Fichero 5836 and Typonos PM240 are available in the
coffee label editor. Physical printing on all three was confirmed by the user
in Printer Lab before promotion on 12 November 2026. That confirmation covers
the tested devices; other firmware and repeatability across units remain
unverified. The editor remembers each model's paper choice and paired device,
and uses the same coffee templates, images, preview and manual copy controls.

- P15 and Fichero use gap labels of 30 × 14 or 40 × 14 mm (select 14 × 30 or
  14 × 40 in the paper selector), with a 12 mm printable height. P15 uses L11;
  Fichero uses the AiYin D11s sequence and waits up to 60 seconds for its
  acknowledgement. The known GATT interface is selected before writing;
  transport failures do not cause fallback printing on another interface.
- PM240 uses 50 × 30 mm labels with a 48 × 28 mm printable area at 203 dpi.
  Its TSPL encoder preserves the tested orientation, bitmap polarity and
  vertical offset. Disconnect Labelnize before searching. Status is checked
  on connection and before and after each requested copy. A ready status
  does not acknowledge paper output, so the editor reports data sent and asks
  the user to inspect the label. PM240C is a different, unsupported model.

These integrations retain the lab's paced writes and stop on a failed or
uncertain job without retrying or sending the remaining copies. No calibration,
firmware, density or gap-setting commands are added. P12 continues to use its
continuous-tape profile; select the exact model rather than a similar name.

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
is never interpreted as the requested timer action. Commands are serialized.
After a reset ACK, the adapter waits for a new zero-time report before sending
the next tare or start. If the ACK or reset completion is missing, or a write
fails, the unusable connection is closed so **Connect** can recover it without
restarting the app. Pending controls are discarded, never replayed on reconnect.
These recovery paths are covered by simulated BLE and UI tests; recovery from
the reported physical Dot lockup still needs confirmation on the affected scale.
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
