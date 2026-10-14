import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../domain/models.dart';
import '../../widgets/common.dart';

const _reportDisclaimer =
    'DEMO DATA — NOT AN OFFICIAL QUALIFICATION. This report supports, but does not replace, an authorised assessor\'s decision.';

String _recommendationLabel(Recommendation? value) => switch (value) {
      Recommendation.provisionalCompetencyRecommended =>
        'Provisional competency recommended',
      Recommendation.gapTrainingRequired => 'Gap training required',
      Recommendation.additionalEvidenceNeeded => 'Additional evidence needed',
      null => 'Not determined',
    };

String _findingLabel(FindingStatus value) => switch (value) {
      FindingStatus.notAssessed => 'Not assessed',
      FindingStatus.notYetCompetent => 'Not yet competent',
      FindingStatus.competentWithSupport => 'Competent with support',
      FindingStatus.competentIndependent => 'Competent (independent)',
    };

String _verificationLabel(VerificationStatus value) => switch (value) {
      VerificationStatus.pending => 'Pending',
      VerificationStatus.accepted => 'Accepted',
      VerificationStatus.rejected => 'Rejected',
      VerificationStatus.needsMore => 'Needs more evidence',
    };

String _sessionStatusLabel(SessionStatus value) => switch (value) {
      SessionStatus.draft => 'Draft',
      SessionStatus.inProgress => 'In progress',
      SessionStatus.completed => 'Completed',
    };

Color _findingColor(FindingStatus value) => switch (value) {
      FindingStatus.notAssessed => AppColors.muted,
      FindingStatus.notYetCompetent => AppColors.danger,
      FindingStatus.competentWithSupport => AppColors.amber,
      FindingStatus.competentIndependent => AppColors.forestSoft,
    };

Color _verificationColor(VerificationStatus value) => switch (value) {
      VerificationStatus.pending => AppColors.amber,
      VerificationStatus.accepted => AppColors.forestSoft,
      VerificationStatus.rejected => AppColors.danger,
      VerificationStatus.needsMore => AppColors.terracotta,
    };

class ReportScreen extends ConsumerWidget {
  const ReportScreen({super.key, required this.sessionId});

  final String sessionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider(sessionId));

    return Scaffold(
      appBar: AppBar(title: const Text('Competency report')),
      body: session.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text('Failed to load report: $e'),
          ),
        ),
        data: (value) {
          if (value == null) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text('Session not found on this device.'),
              ),
            );
          }
          return _ReportBody(sessionId: sessionId, session: value);
        },
      ),
    );
  }
}

class _ReportBody extends ConsumerWidget {
  const _ReportBody({required this.sessionId, required this.session});

  final String sessionId;
  final AssessmentSession session;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final worker = ref.watch(workerProvider(session.workerId));
    final rubrics = ref.watch(rubricsProvider(session.tradeId));
    final findings = ref.watch(findingsProvider(sessionId));
    final evidence = ref.watch(evidenceProvider(sessionId));
    final packs = ref.watch(qualificationPacksProvider(session.tradeId));

    final isLoading =
        worker.isLoading || rubrics.isLoading || findings.isLoading || evidence.isLoading || packs.isLoading;
    if (isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    final firstError = [worker, rubrics, findings, evidence, packs]
        .where((a) => a.hasError)
        .map((a) => a.error)
        .firstOrNull;
    if (firstError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text('Failed to load report: $firstError'),
        ),
      );
    }

    final workerData = worker.value;
    final rubricList = rubrics.value ?? const <RubricCriterion>[];
    final findingList = findings.value ?? const <CriterionFinding>[];
    final evidenceList = evidence.value ?? const <Evidence>[];
    final packList = packs.value ?? const <QualificationPack>[];

    final findingsByCode = <String, CriterionFinding>{
      for (final f in findingList) f.criterionCode: f,
    };

    var qualificationTitle = session.qualificationId;
    for (final p in packList) {
      if (p.id == session.qualificationId) {
        qualificationTitle = p.title;
        break;
      }
    }
    if (qualificationTitle.isEmpty) {
      qualificationTitle = '—';
    }

    final generatedAt = session.completedAt ?? session.createdAt;
    final generatedLabel = DateFormat('dd MMM yyyy, HH:mm').format(generatedAt);

    final workerName = (workerData?.name ?? '').isEmpty ? '—' : workerData!.name;
    final workerTrade =
        (workerData?.primaryTrade ?? '').isEmpty ? '—' : workerData!.primaryTrade;
    final workerRegion = (workerData?.locationRegion ?? '').isEmpty
        ? '—'
        : workerData!.locationRegion;
    final workerYears = workerData == null
        ? '—'
        : '${workerData.yearsOfExperience.toStringAsFixed(1)} yrs';

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'KaushalSetu',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 2),
                const Text(
                  'RPL Competency Demonstration Report',
                  style: TextStyle(fontSize: 13.5, color: AppColors.muted),
                ),
                const SizedBox(height: 12),
                const DisclaimerBanner(text: _reportDisclaimer),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        SectionCard(
          title: 'Worker',
          subtitle: 'On-device candidate record',
          child: Column(
            children: [
              _InfoRow(label: 'Name', value: workerName),
              const _InfoDivider(),
              _InfoRow(label: 'Primary trade', value: workerTrade),
              const _InfoDivider(),
              _InfoRow(label: 'Experience', value: workerYears),
              const _InfoDivider(),
              _InfoRow(label: 'Region', value: workerRegion),
            ],
          ),
        ),
        const SizedBox(height: 12),
        SectionCard(
          title: 'Assessment',
          subtitle: 'Session overview',
          trailing: StatusPill(
            label: _sessionStatusLabel(session.status),
            color: AppColors.forestSoft,
          ),
          child: Column(
            children: [
              _InfoRow(label: 'Qualification', value: qualificationTitle),
              const _InfoDivider(),
              _InfoRow(
                label: 'Assessor',
                value: session.assessorName.isEmpty ? '—' : session.assessorName,
              ),
              const _InfoDivider(),
              _InfoRow(label: 'Status', value: _sessionStatusLabel(session.status)),
              const _InfoDivider(),
              _InfoRow(label: 'Generated', value: generatedLabel),
            ],
          ),
        ),
        const SizedBox(height: 12),
        SectionCard(
          title: 'Criteria',
          subtitle: 'Rubric findings for this session',
          trailing: StatusPill(
            label: '${findingList.length}/${rubricList.length} assessed',
            color: AppColors.forest,
          ),
          child: rubricList.isEmpty
              ? const Text(
                  'No rubric criteria found for this trade.',
                  style: TextStyle(fontSize: 13, color: AppColors.muted),
                )
              : Column(
                  children: [
                    for (var i = 0; i < rubricList.length; i++) ...[
                      _CriterionRow(
                        criterion: rubricList[i],
                        finding: findingsByCode[rubricList[i].criterionCode],
                      ),
                      if (i < rubricList.length - 1)
                        const Divider(color: AppColors.line, height: 20),
                    ],
                  ],
                ),
        ),
        const SizedBox(height: 12),
        SectionCard(
          title: 'Evidence',
          subtitle: 'Linked demonstration evidence',
          trailing: StatusPill(
            label: '${evidenceList.length} item${evidenceList.length == 1 ? '' : 's'}',
            color: AppColors.forest,
          ),
          child: evidenceList.isEmpty
              ? const Text(
                  'No evidence linked to this session.',
                  style: TextStyle(fontSize: 13, color: AppColors.muted),
                )
              : Column(
                  children: [
                    for (var i = 0; i < evidenceList.length; i++) ...[
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.description_outlined,
                              size: 18, color: AppColors.forest),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  evidenceList[i].title,
                                  style: const TextStyle(
                                    fontSize: 13.5,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                if (evidenceList[i].criterionCode.isNotEmpty) ...[
                                  const SizedBox(height: 2),
                                  Text(
                                    evidenceList[i].criterionCode,
                                    style: const TextStyle(
                                      fontSize: 11.5,
                                      color: AppColors.muted,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          StatusPill(
                            label: _verificationLabel(
                                evidenceList[i].verificationStatus),
                            color: _verificationColor(
                                evidenceList[i].verificationStatus),
                          ),
                        ],
                      ),
                      if (i < evidenceList.length - 1)
                        const Divider(color: AppColors.line, height: 20),
                    ],
                  ],
                ),
        ),
        const SizedBox(height: 12),
        SectionCard(
          title: 'Determination',
          subtitle: 'Assessor decision on record',
          trailing: StatusPill(
            label: _recommendationLabel(session.recommendation),
            color: AppColors.terracotta,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Recommendation',
                style: TextStyle(fontSize: 12, color: AppColors.muted),
              ),
              const SizedBox(height: 4),
              Text(
                _recommendationLabel(session.recommendation),
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 12),
              const Text(
                'Overall reasoning',
                style: TextStyle(fontSize: 12, color: AppColors.muted),
              ),
              const SizedBox(height: 4),
              Text(
                session.overallReasoning.isEmpty ? '—' : session.overallReasoning,
                style: const TextStyle(fontSize: 13.5, height: 1.45),
              ),
              const SizedBox(height: 12),
              const Text(
                'Assessor final comments',
                style: TextStyle(fontSize: 12, color: AppColors.muted),
              ),
              const SizedBox(height: 4),
              Text(
                session.assessorFinalComments.isEmpty
                    ? '—'
                    : session.assessorFinalComments,
                style: const TextStyle(fontSize: 13.5, height: 1.45),
              ),
              const Divider(color: AppColors.line, height: 24),
              _InfoRow(
                label: 'Signature',
                value: session.assessorSignatureName.isEmpty
                    ? '—'
                    : session.assessorSignatureName,
              ),
              const _InfoDivider(),
              _InfoRow(
                label: 'Disclaimer acknowledged',
                value: session.disclaimerAcknowledged ? 'Yes' : 'No',
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        const DisclaimerBanner(text: _reportDisclaimer),
      ],
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 128,
          child: Text(
            label,
            style: const TextStyle(fontSize: 12, color: AppColors.muted),
          ),
        ),
        Expanded(
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }
}

class _InfoDivider extends StatelessWidget {
  const _InfoDivider();

  @override
  Widget build(BuildContext context) {
    return const Divider(color: AppColors.line, height: 16);
  }
}

class _CriterionRow extends StatelessWidget {
  const _CriterionRow({required this.criterion, required this.finding});

  final RubricCriterion criterion;
  final CriterionFinding? finding;

  @override
  Widget build(BuildContext context) {
    final f = finding;
    final label = f == null ? 'Not assessed' : _findingLabel(f.status);
    final color = f == null ? AppColors.muted : _findingColor(f.status);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: AppColors.ivory,
            border: Border.all(color: AppColors.line),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            criterion.criterionCode,
            style: const TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              color: AppColors.forest,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            criterion.title,
            style: const TextStyle(fontSize: 13.5, height: 1.4),
          ),
        ),
        const SizedBox(width: 8),
        StatusPill(label: label, color: color),
      ],
    );
  }
}
