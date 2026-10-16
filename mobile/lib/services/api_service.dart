import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import '../models/models.dart';

class ApiException implements Exception {
  final String message;
  final int? status;
  ApiException(this.message, [this.status]);
  bool get isNetwork => status == null;
  @override
  String toString() => message;
}

class ApiService {
  String baseUrl;
  static const Duration _timeout = Duration(seconds: 20);

  ApiService(this.baseUrl);

  Uri _uri(String path, [Map<String, String>? q]) {
    var b = baseUrl.trim();
    while (b.endsWith('/')) {
      b = b.substring(0, b.length - 1);
    }
    return Uri.parse('$b$path').replace(queryParameters: q);
  }

  Map<String, String> _headers(String? token, {bool json = false}) => {
        if (token != null) 'Authorization': 'Bearer $token',
        if (json) 'Content-Type': 'application/json',
      };

  dynamic _decode(http.Response r) {
    dynamic body;
    try {
      body = r.body.isEmpty ? null : jsonDecode(utf8.decode(r.bodyBytes));
    } catch (_) {
      body = null;
    }
    if (r.statusCode >= 200 && r.statusCode < 300) return body;
    var msg = 'Server error (${r.statusCode})';
    if (body is Map && body['detail'] != null) {
      final d = body['detail'];
      msg = d is String ? d : jsonEncode(d);
    }
    throw ApiException(msg, r.statusCode);
  }

  Future<dynamic> _send(Future<http.Response> Function() call) async {
    try {
      final r = await call().timeout(_timeout);
      return _decode(r);
    } on ApiException {
      rethrow;
    } on TimeoutException {
      throw ApiException('Server did not respond in time');
    } on SocketException {
      throw ApiException('Cannot reach the server');
    } on http.ClientException {
      throw ApiException('Cannot reach the server');
    } on HandshakeException {
      throw ApiException('Secure connection failed');
    }
  }

  Future<Map<String, dynamic>> _getMap(String path, {String? token, Map<String, String>? q}) async {
    final b = await _send(() => http.get(_uri(path, q), headers: _headers(token)));
    return Map<String, dynamic>.from(b as Map);
  }

  Future<Map<String, dynamic>> _postMap(String path, Map<String, dynamic> body, {String? token}) async {
    final b = await _send(
        () => http.post(_uri(path), headers: _headers(token, json: true), body: jsonEncode(body)));
    return Map<String, dynamic>.from(b as Map);
  }

  // ---- system
  Future<Map<String, dynamic>> health() => _getMap('/api/health');
  Future<Map<String, dynamic>> aiStatus() => _getMap('/api/ai/status');
  Future<Map<String, dynamic>> rubric() => _getMap('/api/rubric');

  Future<bool> ping() async {
    try {
      await health();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<Map<String, dynamic>> catalogueExport() => _getMap('/api/catalogue/export');

  // ---- auth
  Future<String> authWorker(Worker w) async {
    final r = await _postMap('/api/auth/worker', {
      'id': w.id,
      'name': w.name,
      'phone': w.phone.isEmpty ? null : w.phone,
      'language': w.language,
      'village': w.village.isEmpty ? null : w.village,
    });
    return r['token'] as String;
  }

  Future<Map<String, dynamic>> authAssessor(String user, String pass) =>
      _postMap('/api/auth/assessor', {'username': user, 'password': pass});

  Future<Map<String, dynamic>> mapDeclaration(String token, String text, String lang) =>
      _postMap('/api/map', {'text': text, 'language': lang, 'top_k': 4}, token: token);

  // ---- worker sync
  Future<Map<String, dynamic>> push(String token, Worker w, Assessment a, List<ResponseRow> rs, String status) {
    return _postMap(
        '/api/sync/push',
        {
          'worker': {
            'id': w.id,
            'name': w.name,
            'phone': w.phone.isEmpty ? null : w.phone,
            'language': w.language,
            'village': w.village.isEmpty ? null : w.village,
          },
          'assessment': {
            'id': a.id,
            'worker_id': a.workerId,
            'language': a.language,
            'declaration_text': a.declarationText,
            'declared_years': a.years,
            'qp_code': a.qpCode,
            'status': status,
            'created_at': a.createdAt,
          },
          'responses': [
            for (final r in rs)
              {
                'id': r.id,
                'criterion_id': r.criterionId,
                'answer_text': r.answerText,
                'self_rating': r.selfRating,
                'answered_at': r.answeredAt,
              }
          ],
        },
        token: token);
  }

  Future<void> uploadEvidence(String token, EvidenceRow e) async {
    final file = File(e.localPath);
    if (!await file.exists()) {
      throw ApiException('Evidence file is missing on this phone');
    }
    try {
      final req = http.MultipartRequest('POST', _uri('/api/evidence'))
        ..headers['Authorization'] = 'Bearer $token'
        ..fields['id'] = e.id
        ..fields['assessment_id'] = e.assessmentId
        ..fields['criterion_id'] = e.criterionId
        ..fields['kind'] = e.kind
        ..fields['captured_at'] = e.capturedAt
        ..files.add(await http.MultipartFile.fromPath('file', e.localPath));
      final streamed = await req.send().timeout(const Duration(minutes: 3));
      final r = await http.Response.fromStream(streamed);
      _decode(r);
    } on ApiException {
      rethrow;
    } on TimeoutException {
      throw ApiException('Upload timed out');
    } on SocketException {
      throw ApiException('Cannot reach the server');
    } on http.ClientException {
      throw ApiException('Cannot reach the server');
    }
  }

  Future<Map<String, dynamic>> assessmentDetail(String token, String id) =>
      _getMap('/api/assessments/$id', token: token);

  // ---- assessor
  Future<List<dynamic>> queue(String token) async {
    final b = await _send(() => http.get(_uri('/api/assessor/queue'), headers: _headers(token)));
    return b as List<dynamic>;
  }

  Future<Map<String, dynamic>> saveScores(
      String token, String id, List<Map<String, dynamic>> scores, bool aidsShown) async {
    final b = await _send(() => http.put(_uri('/api/assessor/assessments/$id/scores'),
        headers: _headers(token, json: true), body: jsonEncode({'scores': scores, 'aids_shown': aidsShown})));
    return Map<String, dynamic>.from(b as Map);
  }

  Future<Map<String, dynamic>> signOff(String token, String id, String decision, String reasoning) =>
      _postMap('/api/assessor/assessments/$id/sign-off', {'decision': decision, 'reasoning': reasoning},
          token: token);

  Future<Map<String, dynamic>> agreement(String token) => _getMap('/api/analytics/agreement', token: token);

  String evidenceUrl(String relative, String token) {
    final u = _uri(relative, {'token': token});
    return u.toString();
  }

  /// Downloads a file (PDF report / video evidence) to a temp file and returns its path.
  Future<String> download(String path, String token, String filename, {Map<String, String>? q}) async {
    try {
      final r = await http.get(_uri(path, q), headers: _headers(token)).timeout(const Duration(minutes: 2));
      if (r.statusCode < 200 || r.statusCode >= 300) {
        _decode(r);
      }
      final dir = await getTemporaryDirectory();
      final f = File('${dir.path}/$filename');
      await f.writeAsBytes(r.bodyBytes, flush: true);
      return f.path;
    } on ApiException {
      rethrow;
    } on TimeoutException {
      throw ApiException('Download timed out');
    } on SocketException {
      throw ApiException('Cannot reach the server');
    } on http.ClientException {
      throw ApiException('Cannot reach the server');
    }
  }
}
