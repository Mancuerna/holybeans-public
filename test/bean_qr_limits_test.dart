import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/domain/bean_exchange.dart';

String link(List<int> bytes) => '$beanQrPrefix${base64Url.encode(bytes)}';
List<int> packed(int size) => const GZipEncoder().encodeBytes(
  utf8.encode('{"name":"Safe"}'.padRight(size)),
);

void main() {
  test('a small link cannot expand beyond 256 KiB', () {
    final text = link(packed(256 * 1024 + 1));
    expect(text.length, lessThan(8192));
    expect(
      () => readBeans(text),
      throwsA(
        isA<BeanReadException>().having(
          (error) => error.error,
          'error',
          BeanReadError.tooLarge,
        ),
      ),
    );
  });
  test('exactly 256 KiB is accepted', () {
    expect(readBeans(link(packed(256 * 1024))).single.bean.name, 'Safe');
  });
  test('the output limit covers concatenated gzip members', () {
    final text = link([
      ...packed(128 * 1024),
      ...const GZipEncoder().encodeBytes(utf8.encode(' ' * (128 * 1024 + 1))),
    ]);
    expect(
      () => readBeans(text),
      throwsA(
        isA<BeanReadException>().having(
          (error) => error.error,
          'error',
          BeanReadError.tooLarge,
        ),
      ),
    );
  });
  test('the link boundary is 8 KiB, including UTF-8 bytes', () {
    final full = beanQrPrefix.padRight(beanQrMaxBytes, 'A');
    expect(
      () => readBeans(full),
      throwsA(
        isA<BeanReadException>().having(
          (e) => e.error,
          'error',
          BeanReadError.notJson,
        ),
      ),
    );
    for (final text in ['$full A', '$beanQrPrefix${'é' * 4096}']) {
      expect(
        () => readBeans(text),
        throwsA(
          isA<BeanReadException>().having(
            (e) => e.error,
            'error',
            BeanReadError.tooLarge,
          ),
        ),
      );
    }
  });
  test('a forged gzip size cannot bypass the output cap', () {
    final bytes = packed(beanQrMaxDecodedBytes + 1);
    bytes.fillRange(bytes.length - 4, bytes.length, 0);
    expect(
      () => readBeans(link(bytes)),
      throwsA(
        isA<BeanReadException>().having(
          (e) => e.error,
          'error',
          BeanReadError.tooLarge,
        ),
      ),
    );
  });
  test('truncated and corrupt gzip data are rejected', () {
    final bytes = packed(64);
    for (final damaged in [
      bytes.sublist(0, bytes.length - 8),
      [...bytes]..[bytes.length - 8] ^= 1,
    ]) {
      expect(() => readBeans(link(damaged)), throwsA(isA<BeanReadException>()));
    }
  });
}
