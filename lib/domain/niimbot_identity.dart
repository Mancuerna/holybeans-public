import 'package:holybeans/domain/label_printer_profile.dart';

enum NiimbotPrintFamily { d110, b1, v4, b21, b21L2b, oldD11 }

class NiimbotIdentity {
  const NiimbotIdentity(this.model, this.id, this.family, this.protocolVersion);
  final LabelPrinterModel model;
  final int id;
  final NiimbotPrintFamily family;
  final int? protocolVersion;

  static NiimbotIdentity resolve(
    LabelPrinterModel model,
    int id, {
    int? protocolVersion,
  }) {
    if (!model.acceptsId(id) ||
        (model == LabelPrinterModel.d110M &&
            !const [0, 1, 3, 4, 5].contains(protocolVersion)) ||
        (model == LabelPrinterModel.d11 &&
            protocolVersion != 0 &&
            protocolVersion != 1) ||
        (model.needsProtocolVersion &&
            protocolVersion != 4 &&
            protocolVersion != 5)) {
      throw const FormatException('Unsupported Niimbot identity or protocol');
    }
    final family = switch (id) {
      512 =>
        protocolVersion == 0
            ? NiimbotPrintFamily.oldD11
            : NiimbotPrintFamily.d110,
      2304 || 2305 || 776 || 777 => NiimbotPrintFamily.d110,
      // NiimBlueLib selects V4 only for D110_M protocol 4; its default
      // (including protocol 5) is B1. Firmware numbers are not protocols.
      2320 =>
        protocolVersion == 4 ? NiimbotPrintFamily.v4 : NiimbotPrintFamily.b1,
      4096 || 771 || 775 => NiimbotPrintFamily.b1,
      528 || 4097 || 6912 || 6913 => NiimbotPrintFamily.v4,
      768 => NiimbotPrintFamily.b21,
      769 => NiimbotPrintFamily.b21L2b,
      _ => throw const FormatException('Unsupported Niimbot identity'),
    };
    return NiimbotIdentity(model, id, family, protocolVersion);
  }
}

// PrinterStatusData, following niimbluelib's negotiated-version mapping.
int niimbotProtocolVersion(List<int> payload) {
  if (payload.length < 13) return 0;
  final revision = payload[11] * 100 + payload[12];
  if (revision >= 204 && revision < 300) return 3;
  if (revision >= 300 && revision < 302) return 4;
  if (revision >= 302 && revision < 400) return 5;
  return 0;
}
