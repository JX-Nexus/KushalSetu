/// Localised text with fallback chain: lang -> hi (for mr) -> en.
class Loc {
  final Map<String, String> m;
  const Loc(this.m);

  factory Loc.from(dynamic v) {
    if (v is String) return Loc({'en': v});
    if (v is Map) {
      final out = <String, String>{};
      v.forEach((k, val) {
        if (val != null) out[k.toString()] = val.toString();
      });
      return Loc(out);
    }
    return const Loc({});
  }

  String get(String lang) {
    final chain = <String>[lang];
    if (lang == 'mr') chain.add('hi');
    chain.add('en');
    for (final k in chain) {
      final v = m[k];
      if (v != null && v.isNotEmpty) return v;
    }
    return m.values.isNotEmpty ? m.values.first : '';
  }

  String get all => m.values.join(' ');
}

class Indicator {
  final String en;
  final List<String> kw;
  const Indicator(this.en, this.kw);
  factory Indicator.fromJson(Map<String, dynamic> j) => Indicator(
        (j['en'] ?? '').toString(),
        ((j['kw'] ?? []) as List).map((e) => e.toString()).toList(),
      );
}

class Criterion {
  final String id;
  final Loc text;
  final Loc task;
  final bool critical;
  final double weight;
  final String evidence; // photo | video | none
  final List<Indicator> indicators;
  const Criterion({
    required this.id,
    required this.text,
    required this.task,
    required this.critical,
    required this.weight,
    required this.evidence,
    required this.indicators,
  });

  factory Criterion.fromJson(Map<String, dynamic> j) => Criterion(
        id: j['id'].toString(),
        text: Loc.from(j['text']),
        task: Loc.from(j['task']),
        critical: j['critical'] == true,
        weight: ((j['weight'] ?? 1) as num).toDouble(),
        evidence: (j['evidence'] ?? 'none').toString(),
        indicators: ((j['indicators'] ?? []) as List)
            .map((e) => Indicator.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
      );
}

class Nos {
  final String code;
  final Loc title;
  final double weight;
  final double passThreshold;
  final List<Criterion> criteria;
  const Nos({
    required this.code,
    required this.title,
    required this.weight,
    required this.passThreshold,
    required this.criteria,
  });

  factory Nos.fromJson(Map<String, dynamic> j) => Nos(
        code: j['code'].toString(),
        title: Loc.from(j['title']),
        weight: ((j['weight'] ?? 0) as num).toDouble(),
        passThreshold: ((j['pass_threshold'] ?? 0.6) as num).toDouble(),
        criteria: ((j['criteria'] ?? []) as List)
            .map((e) => Criterion.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
      );
}

class QualPack {
  final String code;
  final Loc title;
  final Loc description;
  final String sector;
  final int nsqfLevel;
  final bool verified;
  final String sourceNote;
  final Map<String, List<String>> keywords;
  final List<Nos> nos;
  const QualPack({
    required this.code,
    required this.title,
    required this.description,
    required this.sector,
    required this.nsqfLevel,
    required this.verified,
    required this.sourceNote,
    required this.keywords,
    required this.nos,
  });

  List<Criterion> get allCriteria => [for (final n in nos) ...n.criteria];

  Criterion? criterion(String id) {
    for (final c in allCriteria) {
      if (c.id == id) return c;
    }
    return null;
  }

  factory QualPack.fromJson(Map<String, dynamic> j) {
    final kw = <String, List<String>>{};
    final rawKw = j['keywords'];
    if (rawKw is Map) {
      rawKw.forEach((k, v) {
        kw[k.toString()] = (v as List).map((e) => e.toString()).toList();
      });
    }
    return QualPack(
      code: j['code'].toString(),
      title: Loc.from(j['title']),
      description: Loc.from(j['description']),
      sector: (j['sector'] ?? '').toString(),
      nsqfLevel: ((j['nsqf_level'] ?? 0) as num).toInt(),
      verified: j['verified'] == true,
      sourceNote: (j['source_note'] ?? '').toString(),
      keywords: kw,
      nos: ((j['nos'] ?? []) as List)
          .map((e) => Nos.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList(),
    );
  }
}

// ---------------------------------------------------------------- local entities

class Worker {
  final String id;
  final String name;
  final String phone;
  final String village;
  final String language;
  final String createdAt;
  const Worker({
    required this.id,
    required this.name,
    required this.phone,
    required this.village,
    required this.language,
    required this.createdAt,
  });

  Map<String, Object?> toMap() => {
        'id': id,
        'name': name,
        'phone': phone,
        'village': village,
        'language': language,
        'created_at': createdAt,
      };

  factory Worker.fromMap(Map<String, Object?> m) => Worker(
        id: m['id'] as String,
        name: (m['name'] ?? '') as String,
        phone: (m['phone'] ?? '') as String,
        village: (m['village'] ?? '') as String,
        language: (m['language'] ?? 'en') as String,
        createdAt: (m['created_at'] ?? '') as String,
      );
}

class Assessment {
  final String id;
  final String workerId;
  final String language;
  final String declarationText; // composed text sent to the mapper
  final String rawText;
  final double? years;
  final String setting;
  final String tools;
  final String? qpCode;
  final String status; // in_progress|submitted|under_review|needs_evidence|signed_off
  final bool dirty;
  final String createdAt;
  final String? matchJson;
  const Assessment({
    required this.id,
    required this.workerId,
    required this.language,
    required this.declarationText,
    required this.rawText,
    required this.years,
    required this.setting,
    required this.tools,
    required this.qpCode,
    required this.status,
    required this.dirty,
    required this.createdAt,
    required this.matchJson,
  });

  Assessment copyWith({
    String? declarationText,
    String? rawText,
    double? years,
    String? setting,
    String? tools,
    String? qpCode,
    String? status,
    bool? dirty,
    String? matchJson,
  }) =>
      Assessment(
        id: id,
        workerId: workerId,
        language: language,
        declarationText: declarationText ?? this.declarationText,
        rawText: rawText ?? this.rawText,
        years: years ?? this.years,
        setting: setting ?? this.setting,
        tools: tools ?? this.tools,
        qpCode: qpCode ?? this.qpCode,
        status: status ?? this.status,
        dirty: dirty ?? this.dirty,
        createdAt: createdAt,
        matchJson: matchJson ?? this.matchJson,
      );

  Map<String, Object?> toMap() => {
        'id': id,
        'worker_id': workerId,
        'language': language,
        'declaration_text': declarationText,
        'raw_text': rawText,
        'years': years,
        'setting': setting,
        'tools': tools,
        'qp_code': qpCode,
        'status': status,
        'dirty': dirty ? 1 : 0,
        'created_at': createdAt,
        'match_json': matchJson,
      };

  factory Assessment.fromMap(Map<String, Object?> m) => Assessment(
        id: m['id'] as String,
        workerId: m['worker_id'] as String,
        language: (m['language'] ?? 'en') as String,
        declarationText: (m['declaration_text'] ?? '') as String,
        rawText: (m['raw_text'] ?? '') as String,
        years: (m['years'] as num?)?.toDouble(),
        setting: (m['setting'] ?? '') as String,
        tools: (m['tools'] ?? '') as String,
        qpCode: m['qp_code'] as String?,
        status: (m['status'] ?? 'in_progress') as String,
        dirty: ((m['dirty'] ?? 0) as num).toInt() == 1,
        createdAt: (m['created_at'] ?? '') as String,
        matchJson: m['match_json'] as String?,
      );
}

class ResponseRow {
  final String id;
  final String assessmentId;
  final String criterionId;
  final String answerText;
  final int? selfRating;
  final String answeredAt;
  const ResponseRow({
    required this.id,
    required this.assessmentId,
    required this.criterionId,
    required this.answerText,
    required this.selfRating,
    required this.answeredAt,
  });

  Map<String, Object?> toMap() => {
        'id': id,
        'assessment_id': assessmentId,
        'criterion_id': criterionId,
        'answer_text': answerText,
        'self_rating': selfRating,
        'answered_at': answeredAt,
      };

  factory ResponseRow.fromMap(Map<String, Object?> m) => ResponseRow(
        id: m['id'] as String,
        assessmentId: m['assessment_id'] as String,
        criterionId: m['criterion_id'] as String,
        answerText: (m['answer_text'] ?? '') as String,
        selfRating: (m['self_rating'] as num?)?.toInt(),
        answeredAt: (m['answered_at'] ?? '') as String,
      );
}

class EvidenceRow {
  final String id;
  final String assessmentId;
  final String criterionId;
  final String kind; // photo | video
  final String localPath;
  final String capturedAt;
  final bool uploaded;
  const EvidenceRow({
    required this.id,
    required this.assessmentId,
    required this.criterionId,
    required this.kind,
    required this.localPath,
    required this.capturedAt,
    required this.uploaded,
  });

  Map<String, Object?> toMap() => {
        'id': id,
        'assessment_id': assessmentId,
        'criterion_id': criterionId,
        'kind': kind,
        'local_path': localPath,
        'captured_at': capturedAt,
        'uploaded': uploaded ? 1 : 0,
      };

  factory EvidenceRow.fromMap(Map<String, Object?> m) => EvidenceRow(
        id: m['id'] as String,
        assessmentId: m['assessment_id'] as String,
        criterionId: m['criterion_id'] as String,
        kind: (m['kind'] ?? 'photo') as String,
        localPath: (m['local_path'] ?? '') as String,
        capturedAt: (m['captured_at'] ?? '') as String,
        uploaded: ((m['uploaded'] ?? 0) as num).toInt() == 1,
      );
}
