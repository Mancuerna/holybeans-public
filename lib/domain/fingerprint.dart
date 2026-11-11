/// FNV-1a over bytes, retaining native 64-bit integer overflow semantics.
int fnv1a64(Iterable<int> bytes) {
  var hash = 0xcbf29ce484222325;
  for (final byte in bytes) {
    hash ^= byte;
    hash *= 0x100000001b3;
  }
  return hash;
}
