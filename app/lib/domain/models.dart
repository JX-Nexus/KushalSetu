// Domain models for the KaushalSetu local-first RPL app.
//
// Plain Dart classes with sqflite-friendly map serialisation. No codegen,
// no network. Everything is designed to persist locally on-device.

// ---------------------------------------------------------------------------
// Enums
// ---------------------------------------------------------------------------

enum LanguageCode { en, hi, mr }

LanguageCode languageFromName(String? v) => LanguageCode.values.firstWhere(
      (e) => e.name == v,
      orElse: () => LanguageCode.en,
    );

enum EvidenceSource { selfReported, uploaded, assessorObserved }

enum VerificationStatus { pending, accepted, rejected, needsMore }

enum FindingStatus { notAssessed, notYetCompetent, competentWithSupport, competentIndependent }

enum Recommendation {
  provisionalCompetencyRecommended,
  gapTrainingRequired,
  additionalEvidenceNeeded,
}

enum SessionStatus { draft, inProgress, completed }

T _enumFromName<T extends Enum>(List<T> values, String? name, T fallback) =>
    values.firstWhere((e) => e.name == name, orElse: () => fallback);

// ---------------------------------------------------------------------------
// Trade & qualifications (seeded, read-mostly)
// ---------------------------------------------------------------------------

class Trade {
  final String id;
  final String code;
  final String name;
  final String sector;
  final String description;

  const Trade({
    required this.id,
    required this.code,
    required this.name,
    required this.sector,
    required this.description,
  });

  Map<String, Object?> toMap() => {
        'id': id,
        'code': code,
        'name': name,
        'sector': sector,
        'description': description,
      };

  factory Trade.fromMap(Map<String, Object?> m) => Trade(
        id: m['id'] as String,
        code: m['code'] as String,
        name: m['name'] as String,
        sector: m['sector'] as String,
        description: m['description'] as String,
      );
}

/// A competence unit inside a qualification pack.
class QpUnit {
  final String unitCode;
  final String title;
  final String description;

  const QpUnit({required this.unitCode, required this.title, required this.description});

  Map<String, Object?> toMap() =>
      {'unitCode': unitCode, 'title': title, 'description': description};

  factory QpUnit.fromMap(Map<String, Object?> m) => QpUnit(
        unitCode: m['unitCode'] as String,
        title: m['title'] as String,
        description: m['description'] as String,
      );
}

class QualificationPack {
  final String id;
  final String tradeId;
  final String code;
  final String title;
  final int nsqfLevel;
  final List<String> typicalTools;
  final List<QpUnit> units;

  /// Every seeded pack is explicitly demo data, never an official NSQF pack.
  final String sourceNote;

  const QualificationPack({
    required this.id,
    required this.tradeId,
    required this.code,
    required this.title,
    required this.nsqfLevel,
    required this.typicalTools,
    required this.units,
    required this.sourceNote,
  });

  Map<String, Object?> toMap() => {
        'id': id,
        'trade_id': tradeId,
        'code': code,
        'title': title,
        'nsqf_level': nsqfLevel,
        'typical_tools': typicalTools.join('||'),
        'units': units.map((u) => '${u.unitCode}::~${u.title}::~${u.description}').join('||'),
        'source_note': sourceNote,
      };

  factory QualificationPack.fromMap(Map<String, Object?> m) => QualificationPack(
        id: m['id'] as String,
        tradeId: m['trade_id'] as String,
        code: m['code'] as String,
        title: m['title'] as String,
        nsqfLevel: (m['nsqf_level'] as num).toInt(),
        typicalTools: _splitList(m['typical_tools'] as String?),
        units: _splitList(m['units'] as String?).map((s) {
          final parts = s.split('::~');
          return QpUnit(
            unitCode: parts.isNotEmpty ? parts[0] : '',
            title: parts.length > 1 ? parts[1] : '',
            description: parts.length > 2 ? parts[2] : '',
          );
        }).toList(),
        sourceNote: m['source_note'] as String,
      );
}

// ---------------------------------------------------------------------------
// Rubrics (seeded)
// ---------------------------------------------------------------------------

class RubricCriterion {
  final String id;
  final String tradeId;
  final String criterionCode;
  final String title;
  final List<String> performanceIndicators;
  final String evidenceRequirement;
  final String level4;
  final String level3;
  final String level2;
  final String level1;

  const RubricCriterion({
    required this.id,
    required this.tradeId,
    required this.criterionCode,
    required this.title,
    required this.performanceIndicators,
    required this.evidenceRequirement,
    required this.level4,
    required this.level3,
    required this.level2,
    required this.level1,
  });

  Map<String, Object?> toMap() => {
        'id': id,
        'trade_id': tradeId,
        'criterion_code': criterionCode,
        'title': title,
        'performance_indicators': performanceIndicators.join('||'),
        'evidence_requirement': evidenceRequirement,
        'level4': level4,
        'level3': level3,
        'level2': level2,
        'level1': level1,
      };

  factory RubricCriterion.fromMap(Map<String, Object?> m) => RubricCriterion(
        id: m['id'] as String,
        tradeId: m['trade_id'] as String,
        criterionCode: m['criterion_code'] as String,
        title: m['title'] as String,
        performanceIndicators: _splitList(m['performance_indicators'] as String?),
        evidenceRequirement: m['evidence_requirement'] as String,
        level4: m['level4'] as String,
        level3: m['level3'] as String,
        level2: m['level2'] as String,
        level1: m['level1'] as String,
      );
}

// ---------------------------------------------------------------------------
// Worker + self-declaration
// ---------------------------------------------------------------------------

class Worker {
  final String id;
  final String name;
  final LanguageCode preferredLanguage;
  final String primaryTrade;
  final double yearsOfExperience;
  final String locationRegion;
  final bool priorFormalTraining;
  final DateTime createdAt;

  const Worker({
    required this.id,
    required this.name,
    required this.preferredLanguage,
    required this.primaryTrade,
    required this.yearsOfExperience,
    required this.locationRegion,
    required this.priorFormalTraining,
    required this.createdAt,
  });

  Map<String, Object?> toMap() => {
        'id': id,
        'name': name,
        'preferred_language': preferredLanguage.name,
        'primary_trade': primaryTrade,
        'years_of_experience': yearsOfExperience,
        'location_region': locationRegion,
        'prior_formal_training': priorFormalTraining ? 1 : 0,
        'created_at': createdAt.toIso8601String(),
      };

  factory Worker.fromMap(Map<String, Object?> m) => Worker(
        id: m['id'] as String,
        name: m['name'] as String,
        preferredLanguage: languageFromName(m['preferred_language'] as String?),
        primaryTrade: m['primary_trade'] as String,
        yearsOfExperience: (m['years_of_experience'] as num).toDouble(),
        locationRegion: m['location_region'] as String,
        priorFormalTraining: (m['prior_formal_training'] as num? ?? 0) == 1,
        createdAt: DateTime.parse(m['created_at'] as String),
      );
}

class ExperienceDeclaration {
  final String id;
  final String workerId;
  final String tradeContext;
  final List<String> dailyTasks;
  final List<String> toolsUsed;
  final List<String> safetyPractices;
  final String freeTextDescription;
  final String informalLearningSource;
  final DateTime createdAt;

  const ExperienceDeclaration({
    required this.id,
    required this.workerId,
    required this.tradeContext,
    required this.dailyTasks,
    required this.toolsUsed,
    required this.safetyPractices,
    required this.freeTextDescription,
    required this.informalLearningSource,
    required this.createdAt,
  });

  Map<String, Object?> toMap() => {
        'id': id,
        'worker_id': workerId,
        'trade_context': tradeContext,
        'daily_tasks': dailyTasks.join('||'),
        'tools_used': toolsUsed.join('||'),
        'safety_practices': safetyPractices.join('||'),
        'free_text_description': freeTextDescription,
        'informal_learning_source': informalLearningSource,
        'created_at': createdAt.toIso8601String(),
      };

  factory ExperienceDeclaration.fromMap(Map<String, Object?> m) => ExperienceDeclaration(
        id: m['id'] as String,
        workerId: m['worker_id'] as String,
        tradeContext: m['trade_context'] as String,
        dailyTasks: _splitList(m['daily_tasks'] as String?),
        toolsUsed: _splitList(m['tools_used'] as String?),
        safetyPractices: _splitList(m['safety_practices'] as String?),
        freeTextDescription: m['free_text_description'] as String,
        informalLearningSource: m['informal_learning_source'] as String,
        createdAt: DateTime.parse(m['created_at'] as String),
      );
}

// ---------------------------------------------------------------------------
// Matching output
// ---------------------------------------------------------------------------

class QualificationMatch {
  final String qualificationId;
  final String qualificationTitle;
  final double matchScorePct;
  final String uncertaintyLevel;
  final List<String> uncertaintyFactors;
  final List<String> matchedTasks;
  final List<String> matchedTools;
  final List<String> missingUnits;
  final String rationale;

  const QualificationMatch({
    required this.qualificationId,
    required this.qualificationTitle,
    required this.matchScorePct,
    required this.uncertaintyLevel,
    required this.uncertaintyFactors,
    required this.matchedTasks,
    required this.matchedTools,
    required this.missingUnits,
    required this.rationale,
  });
}

// ---------------------------------------------------------------------------
// Assessment session, evidence, findings
// ---------------------------------------------------------------------------

class AssessmentSession {
  final String id;
  final String workerId;
  final String tradeId;
  final String qualificationId;
  final String assessorName;
  final SessionStatus status;
  final Recommendation? recommendation;
  final String overallReasoning;
  final String assessorFinalComments;
  final String assessorSignatureName;
  final bool disclaimerAcknowledged;
  final DateTime createdAt;
  final DateTime? completedAt;

  const AssessmentSession({
    required this.id,
    required this.workerId,
    required this.tradeId,
    required this.qualificationId,
    required this.assessorName,
    required this.status,
    required this.recommendation,
    required this.overallReasoning,
    required this.assessorFinalComments,
    required this.assessorSignatureName,
    required this.disclaimerAcknowledged,
    required this.createdAt,
    required this.completedAt,
  });

  AssessmentSession copyWith({
    SessionStatus? status,
    Recommendation? recommendation,
    String? overallReasoning,
    String? assessorFinalComments,
    String? assessorSignatureName,
    bool? disclaimerAcknowledged,
    DateTime? completedAt,
  }) =>
      AssessmentSession(
        id: id,
        workerId: workerId,
        tradeId: tradeId,
        qualificationId: qualificationId,
        assessorName: assessorName,
        status: status ?? this.status,
        recommendation: recommendation ?? this.recommendation,
        overallReasoning: overallReasoning ?? this.overallReasoning,
        assessorFinalComments: assessorFinalComments ?? this.assessorFinalComments,
        assessorSignatureName: assessorSignatureName ?? this.assessorSignatureName,
        disclaimerAcknowledged: disclaimerAcknowledged ?? this.disclaimerAcknowledged,
        createdAt: createdAt,
        completedAt: completedAt ?? this.completedAt,
      );

  Map<String, Object?> toMap() => {
        'id': id,
        'worker_id': workerId,
        'trade_id': tradeId,
        'qualification_id': qualificationId,
        'assessor_name': assessorName,
        'status': status.name,
        'recommendation': recommendation?.name,
        'overall_reasoning': overallReasoning,
        'assessor_final_comments': assessorFinalComments,
        'assessor_signature_name': assessorSignatureName,
        'disclaimer_acknowledged': disclaimerAcknowledged ? 1 : 0,
        'created_at': createdAt.toIso8601String(),
        'completed_at': completedAt?.toIso8601String(),
      };

  factory AssessmentSession.fromMap(Map<String, Object?> m) => AssessmentSession(
        id: m['id'] as String,
        workerId: m['worker_id'] as String,
        tradeId: m['trade_id'] as String,
        qualificationId: m['qualification_id'] as String,
        assessorName: m['assessor_name'] as String,
        status: _enumFromName(SessionStatus.values, m['status'] as String?, SessionStatus.draft),
        recommendation:
            (m['recommendation'] as String?) == null
                ? null
                : _enumFromName(Recommendation.values, m['recommendation'] as String?, Recommendation.additionalEvidenceNeeded),
        overallReasoning: (m['overall_reasoning'] as String?) ?? '',
        assessorFinalComments: (m['assessor_final_comments'] as String?) ?? '',
        assessorSignatureName: (m['assessor_signature_name'] as String?) ?? '',
        disclaimerAcknowledged: (m['disclaimer_acknowledged'] as num? ?? 0) == 1,
        createdAt: DateTime.parse(m['created_at'] as String),
        completedAt: m['completed_at'] == null ? null : DateTime.parse(m['completed_at'] as String),
      );
}

class Evidence {
  final String id;
  final String sessionId;
  final String title;
  final String description;
  final EvidenceSource sourceType;
  final String? filePath;
  final String? fileMime;
  final String criterionCode;
  final VerificationStatus verificationStatus;
  final String comments;
  final DateTime createdAt;

  const Evidence({
    required this.id,
    required this.sessionId,
    required this.title,
    required this.description,
    required this.sourceType,
    required this.filePath,
    required this.fileMime,
    required this.criterionCode,
    required this.verificationStatus,
    required this.comments,
    required this.createdAt,
  });

  Map<String, Object?> toMap() => {
        'id': id,
        'session_id': sessionId,
        'title': title,
        'description': description,
        'source_type': sourceType.name,
        'file_path': filePath,
        'file_mime': fileMime,
        'criterion_code': criterionCode,
        'verification_status': verificationStatus.name,
        'comments': comments,
        'created_at': createdAt.toIso8601String(),
      };

  factory Evidence.fromMap(Map<String, Object?> m) => Evidence(
        id: m['id'] as String,
        sessionId: m['session_id'] as String,
        title: m['title'] as String,
        description: (m['description'] as String?) ?? '',
        sourceType: _enumFromName(EvidenceSource.values, m['source_type'] as String?, EvidenceSource.selfReported),
        filePath: m['file_path'] as String?,
        fileMime: m['file_mime'] as String?,
        criterionCode: (m['criterion_code'] as String?) ?? '',
        verificationStatus: _enumFromName(VerificationStatus.values, m['verification_status'] as String?, VerificationStatus.pending),
        comments: (m['comments'] as String?) ?? '',
        createdAt: DateTime.parse(m['created_at'] as String),
      );
}

class CriterionFinding {
  final String id;
  final String sessionId;
  final String criterionCode;
  final FindingStatus status;
  final String comments;
  final List<String> gaps;
  final bool assessorOverride;
  final DateTime updatedAt;

  const CriterionFinding({
    required this.id,
    required this.sessionId,
    required this.criterionCode,
    required this.status,
    required this.comments,
    required this.gaps,
    required this.assessorOverride,
    required this.updatedAt,
  });

  Map<String, Object?> toMap() => {
        'id': id,
        'session_id': sessionId,
        'criterion_code': criterionCode,
        'status': status.name,
        'comments': comments,
        'gaps': gaps.join('||'),
        'assessor_override': assessorOverride ? 1 : 0,
        'updated_at': updatedAt.toIso8601String(),
      };

  factory CriterionFinding.fromMap(Map<String, Object?> m) => CriterionFinding(
        id: m['id'] as String,
        sessionId: m['session_id'] as String,
        criterionCode: m['criterion_code'] as String,
        status: _enumFromName(FindingStatus.values, m['status'] as String?, FindingStatus.notAssessed),
        comments: (m['comments'] as String?) ?? '',
        gaps: _splitList(m['gaps'] as String?),
        assessorOverride: (m['assessor_override'] as num? ?? 0) == 1,
        updatedAt: DateTime.parse(m['updated_at'] as String),
      );
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

List<String> _splitList(String? raw) {
  if (raw == null || raw.isEmpty) return const [];
  return raw
      .split('||')
      .map((e) => e.trim())
      .where((e) => e.isNotEmpty)
      .toList(growable: false);
}
