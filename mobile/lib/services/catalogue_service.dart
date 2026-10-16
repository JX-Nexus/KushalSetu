import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';
import '../models/models.dart';
import 'api_service.dart';
import 'match_engine.dart';

/// Qualification-pack catalogue: bundled asset -> cached copy -> refreshed from the server.
/// Nothing about trades or criteria is hardcoded in Dart; it all comes from this data.
class CatalogueService extends ChangeNotifier {
  List<QualPack> packs = [];
  String version = '';
  MatchEngine? engine;

  Future<File> _cacheFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/catalogue_cache.json');
  }

  Future<void> load() async {
    String? raw;
    try {
      final f = await _cacheFile();
      if (await f.exists()) raw = await f.readAsString();
    } catch (_) {}
    if (raw != null) {
      try {
        _apply(raw);
        return;
      } catch (_) {}
    }
    _apply(await rootBundle.loadString('assets/data/catalogue.json'));
  }

  void _apply(String raw) {
    final j = Map<String, dynamic>.from(jsonDecode(raw) as Map);
    final list = (j['packs'] as List)
        .map((e) => QualPack.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
    if (list.isEmpty) throw const FormatException('empty catalogue');
    packs = list;
    version = (j['version'] ?? '').toString();
    engine = MatchEngine(packs);
  }

  /// Returns true when a newer catalogue was downloaded.
  Future<bool> refresh(ApiService api) async {
    try {
      final j = await api.catalogueExport();
      final v = (j['version'] ?? '').toString();
      if (v.isEmpty || v == version) return false;
      final raw = jsonEncode(j);
      _apply(raw);
      final f = await _cacheFile();
      await f.writeAsString(raw, flush: true);
      notifyListeners();
      return true;
    } catch (_) {
      return false;
    }
  }

  QualPack? byCode(String? code) {
    if (code == null) return null;
    for (final p in packs) {
      if (p.code == code) return p;
    }
    return null;
  }
}
