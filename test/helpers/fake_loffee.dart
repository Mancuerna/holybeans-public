import 'dart:typed_data';

import 'package:holybeans/data/services/loffee_api.dart';
import 'package:holybeans/data/services/loffee_key_store.dart';
import 'package:holybeans/domain/loffee_bean.dart';

/// Synthetic documented fields; not a captured response from Loffee Labs.
const loffeeFixture = <String, Object?>{
  'id': 42,
  'roast-name': 'Patrol Loffee Gesha',
  'roaster': 'Test Roaster',
  'origin': 'Spain',
  'region': 'Canary Islands',
  'producer': 'Test farm',
  'variety': 'Gesha',
  'process': 'Washed',
  'harvest': '2026',
  'min-elev': 1200,
  'max-elev': 1600,
  'type': 'Omni',
  'degree': 'Light',
  'tasting': 'Jasmine, peach',
  'description': 'A synthetic catalogue description.',
  'link': 'https://shop.example/gesha',
  'date': '2026-10-01',
  'price-low': 15,
  'gram-low': 250,
  'soldout': true,
  'available': false,
  'roaster-country': 'UK',
};

class MemoryLoffeeKeys implements LoffeeKeyStore {
  MemoryLoffeeKeys([this.value]);
  String? value;
  bool fail = false;
  @override
  Future<String?> read() async {
    if (fail) throw StateError('Synthetic credential failure');
    return value;
  }

  @override
  Future<void> save(String key) async {
    if (fail) throw StateError('Synthetic credential failure');
    value = key;
  }

  @override
  Future<void> delete() async => value = null;
}

class FakeLoffeeApi implements LoffeeApi {
  final calls = <({String key, String query, int page})>[];
  LoffeeFailure? failure;
  List<LoffeeBean> beans = [LoffeeBean.fromJson(loffeeFixture)];
  bool hasMore = false;
  Uint8List? image;
  @override
  Future<LoffeePage> search({
    required String key,
    required String query,
    int page = 1,
  }) async {
    calls.add((key: key, query: query, page: page));
    if (failure case final problem?) throw LoffeeException(problem);
    return LoffeePage(beans, hasMore: hasMore);
  }

  @override
  Future<Uint8List> photo(String url) async {
    if (image == null) throw const LoffeeException(LoffeeFailure.network);
    return image!;
  }
}
