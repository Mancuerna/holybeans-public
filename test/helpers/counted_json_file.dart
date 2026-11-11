import 'package:holybeans/data/services/atomic_json_file.dart';

class CountedJsonFile extends AtomicJsonFile {
  CountedJsonFile(super.file);
  int reads = 0;
  int writes = 0;

  @override
  Future<Object?> read() {
    reads++;
    return super.read();
  }

  @override
  Future<void> write(Object? value) {
    writes++;
    return super.write(value);
  }
}
