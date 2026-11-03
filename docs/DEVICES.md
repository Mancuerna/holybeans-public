# Device integrations

Hardware compatibility depends on the model, firmware and platform. Protocol
support is not a claim that every combination has been physically tested.

HolyBeans includes integrations for supported Bluetooth scales, DiFluid R2
refractometers and BOOKOO pressure sensors. Meticulous and Gaggimate history
integrations read documented machine endpoints without changing machine state.

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

Printing always starts from a user action. Do not retry automatically after an
uncertain result or issue calibration, firmware, power or unrelated settings
commands. See [contribution boundaries](../CONTRIBUTING.md#hardware-boundaries).

Timemore Dot support is not part of this production source snapshot.
