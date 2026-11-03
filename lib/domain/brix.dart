/// Approximate coffee TDS from a Brix reading and an explicit coefficient.
double? brixToTds(double? brix, double? factor) {
  if (brix == null ||
      factor == null ||
      !brix.isFinite ||
      !factor.isFinite ||
      brix <= 0 ||
      brix > 100 ||
      factor <= 0 ||
      factor > 1) {
    return null;
  }
  return brix * factor;
}
