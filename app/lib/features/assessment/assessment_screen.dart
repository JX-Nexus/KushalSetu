import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../domain/models.dart';
import '../../widgets/common.dart';
import '../report/report_screen.dart';

/// Assessor-facing scoring workspace: per-criterion findings, photo evidence
/// capture and the final human determination. Fully on-device.
class AssessmentScreen extends ConsumerWidget {
  const AssessmentScreen({super.key, required this.sessionId});

  final String sessionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sessionAsync = ref.watch(sessionProvider(sessionId));
    return Scaffold(
      appBar: AppBar(title: const Text('Assessment')),
      body: sessionAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Could not load session: $e')),
        data: (session) => session == null
            ? const Center(child: Text('Session not found'))
            : _ScoringForm(session: session),
      ),
    );
  }
}

class _ScoringForm extends ConsumerWidget {
  const _ScoringForm({required this.session});

  final AssessmentSession session;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rubrics = ref.watch(rubricsProvider(session.tradeId));
    final findings = ref.watch(findingsProvider(session.id));

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      children: [
        const DisclaimerBanner(),
        const SizedBox(height: 12),
        SectionCard(
          title: 'Assessor scoring',
          subtitle: 'Record observable findings against each criterion.',
          child: rubrics.when(
            loading: () => const Center(child: Padding(padding: EdgeInsets.all(12), child: CircularProgressIndicator())),
            error: (e, _) => Text('Could not load rubrics: $e'),
            data: (criteria) {
              final byCode = <String, CriterionFinding>{
                for (final f in findings.asData?.value ?? const <CriterionFinding>[])
                  f.criterionCode: f,
              };
              if (criteria.isEmpty) {
                return const Text('No rubric criteria found for this trade.');
              }
              return Column(
                children: [
                  for (final c in criteria)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _CriterionCard(
                        sessionId: session.id,
                        criterion: c,
                        finding: byCode[c.criterionCode],
                      ),
                    ),
                ],
              );
            },
          ),
        ),
        const SizedBox(height: 12),
        _EvidenceSection(sessionId: session.id, tradeId: session.tradeId),
        const SizedBox(height: 12),
        _DecisionSection(session: session),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Criterion card
// ---------------------------------------------------------------------------

class _CriterionCard extends ConsumerStatefulWidget {
  const _CriterionCard({
    required this.sessionId,
    required this.criterion,
    required this.finding,
  });

  final String sessionId;
  final RubricCriterion criterion;
  final CriterionFinding? finding;

  @override
  ConsumerState<_CriterionCard> createState() => _CriterionCardState();
}

class _CriterionCardState extends ConsumerState<_CriterionCard> {
  late final TextEditingController _commentCtrl;

  @override
  void initState() {
    super.initState();
    _commentCtrl = TextEditingController(text: widget.finding?.comments ?? '');
  }

  @override
  void dispose() {
    _commentCtrl.dispose();
    super.dispose();
  }

  Future<void> _save(FindingStatus status) async {
    final repo = await ref.read(repositoryProvider.future);
    final prior = widget.finding;
    final finding = CriterionFinding(
      id: prior?.id ?? const Uuid().v4(),
      sessionId: widget.sessionId,
      criterionCode: widget.criterion.criterionCode,
      status: status,
      comments: _commentCtrl.text.trim(),
      gaps: prior?.gaps ?? const [],
      assessorOverride: true,
      updatedAt: DateTime.now(),
    );
    await repo.upsertFinding(finding);
    ref.invalidate(findingsProvider(widget.sessionId));
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.criterion;
    final current = widget.finding?.status ?? FindingStatus.notAssessed;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.line),
        borderRadius: BorderRadius.circular(14),
        color: AppColors.ivory,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(c.criterionCode,
                  style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.forest)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(c.title,
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          for (final ind in c.performanceIndicators)
            Padding(
              padding: const EdgeInsets.only(bottom: 3),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 6, right: 6),
                    child: Icon(Icons.circle, size: 5, color: AppColors.muted),
                  ),
                  Expanded(child: Text(ind, style: const TextStyle(fontSize: 12.5, height: 1.35))),
                ],
              ),
            ),
          const SizedBox(height: 8),
          _levelLine('Level 4', c.level4),
          _levelLine('Level 3', c.level3),
          _levelLine('Level 2', c.level2),
          _levelLine('Level 1', c.level1),
          const SizedBox(height: 10),
          Text('Evidence: ${c.evidenceRequirement}',
              style: const TextStyle(fontSize: 11.5, color: AppColors.muted, height: 1.35)),
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final s in FindingStatus.values)
                ChoiceChip(
                  label: Text(_findingLabel(s), style: const TextStyle(fontSize: 12)),
                  selected: current == s,
                  onSelected: (_) => _save(s),
                ),
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _commentCtrl,
            minLines: 1,
            maxLines: 3,
            decoration: const InputDecoration(
              hintText: 'Assessor comments (optional)',
              isDense: true,
            ),
          ),
        ],
      ),
    );
  }

  Widget _levelLine(String label, String text) => Padding(
        padding: const EdgeInsets.only(bottom: 2),
        child: RichText(
          text: TextSpan(
            style: const TextStyle(fontSize: 11.5, color: AppColors.ink, height: 1.3),
            children: [
              TextSpan(text: '$label: ', style: const TextStyle(fontWeight: FontWeight.w700)),
              TextSpan(text: text),
            ],
          ),
        ),
      );
}

String _findingLabel(FindingStatus s) => switch (s) {
      FindingStatus.notAssessed => 'Not assessed',
      FindingStatus.notYetCompetent => 'Not yet competent',
      FindingStatus.competentWithSupport => 'Competent with support',
      FindingStatus.competentIndependent => 'Competent independent',
    };

// ---------------------------------------------------------------------------
// Evidence section
// ---------------------------------------------------------------------------

class _EvidenceSection extends ConsumerStatefulWidget {
  const _EvidenceSection({required this.sessionId, required this.tradeId});

  final String sessionId;
  final String tradeId;

  @override
  ConsumerState<_EvidenceSection> createState() => _EvidenceSectionState();
}

class _EvidenceSectionState extends ConsumerState<_EvidenceSection> {
  String? _selectedCriterion;
  bool _saving = false;

  Future<void> _addPhoto(List<RubricCriterion> criteria) async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Take photo'),
              onTap: () => Navigator.pop(ctx, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choose from gallery'),
              onTap: () => Navigator.pop(ctx, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (source == null) return;

    final picked = await ImagePicker().pickImage(source: source, imageQuality: 80);
    if (picked == null) return;

    setState(() => _saving = true);
    try {
      final dir = await getApplicationDocumentsDirectory();
      final evDir = Directory(p.join(dir.path, 'evidence'));
      if (!evDir.existsSync()) evDir.createSync(recursive: true);
      final id = const Uuid().v4();
      final ext = p.extension(picked.path).isEmpty ? '.jpg' : p.extension(picked.path);
      final dest = p.join(evDir.path, '$id$ext');
      await File(picked.path).copy(dest);

      final repo = await ref.read(repositoryProvider.future);
      await repo.addEvidence(Evidence(
        id: id,
        sessionId: widget.sessionId,
        title: 'Photo evidence',
        description: '',
        sourceType: EvidenceSource.uploaded,
        filePath: dest,
        fileMime: 'image/jpeg',
        criterionCode: _selectedCriterion ?? (criteria.isNotEmpty ? criteria.first.criterionCode : ''),
        verificationStatus: VerificationStatus.pending,
        comments: '',
        createdAt: DateTime.now(),
      ));
      ref.invalidate(evidenceProvider(widget.sessionId));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _setStatus(Evidence ev, VerificationStatus status) async {
    final repo = await ref.read(repositoryProvider.future);
    final updated = Evidence(
      id: ev.id,
      sessionId: ev.sessionId,
      title: ev.title,
      description: ev.description,
      sourceType: ev.sourceType,
      filePath: ev.filePath,
      fileMime: ev.fileMime,
      criterionCode: ev.criterionCode,
      verificationStatus: status,
      comments: ev.comments,
      createdAt: ev.createdAt,
    );
    await repo.updateEvidence(updated);
    ref.invalidate(evidenceProvider(widget.sessionId));
  }

  @override
  Widget build(BuildContext context) {
    final rubrics = ref.watch(rubricsProvider(widget.tradeId));
    final evidence = ref.watch(evidenceProvider(widget.sessionId));
    final criteria = rubrics.asData?.value ?? const <RubricCriterion>[];

    return SectionCard(
      title: 'Supporting evidence',
      subtitle: 'Photo artifacts captured on device. Assessor-verified.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (criteria.isNotEmpty)
            DropdownButtonFormField<String>(
              initialValue: _selectedCriterion ?? criteria.first.criterionCode,
              decoration: const InputDecoration(labelText: 'Map photo to criterion', isDense: true),
              items: [
                for (final c in criteria)
                  DropdownMenuItem(value: c.criterionCode, child: Text('${c.criterionCode} — ${c.title}')),
              ],
              onChanged: (v) => setState(() => _selectedCriterion = v),
            ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: _saving ? null : () => _addPhoto(criteria),
            icon: const Icon(Icons.add_a_photo_outlined),
            label: Text(_saving ? 'Saving…' : 'Add photo evidence'),
          ),
          const SizedBox(height: 10),
          evidence.when(
            loading: () => const SizedBox.shrink(),
            error: (e, _) => Text('Could not load evidence: $e'),
            data: (list) {
              if (list.isEmpty) {
                return const Text('No evidence attached yet.',
                    style: TextStyle(color: AppColors.muted, fontSize: 13));
              }
              return Column(
                children: [
                  for (final ev in list) _evidenceTile(ev),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _evidenceTile(Evidence ev) {
    final file = ev.filePath == null ? null : File(ev.filePath!);
    final hasImage = file != null && file.existsSync();
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.line),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: hasImage
                ? Image.file(file, width: 56, height: 56, fit: BoxFit.cover)
                : Container(
                    width: 56,
                    height: 56,
                    color: AppColors.ivory,
                    child: const Icon(Icons.image_not_supported_outlined, color: AppColors.muted),
                  ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(ev.title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5)),
                if (ev.criterionCode.isNotEmpty)
                  Text('→ ${ev.criterionCode}',
                      style: const TextStyle(fontSize: 11.5, color: AppColors.muted)),
                const SizedBox(height: 4),
                StatusPill(
                  label: ev.verificationStatus.name,
                  color: _verifyColor(ev.verificationStatus),
                ),
              ],
            ),
          ),
          Column(
            children: [
              IconButton(
                tooltip: 'Accept',
                icon: const Icon(Icons.check_circle_outline, color: AppColors.forest),
                onPressed: () => _setStatus(ev, VerificationStatus.accepted),
              ),
              IconButton(
                tooltip: 'Reject',
                icon: const Icon(Icons.cancel_outlined, color: AppColors.danger),
                onPressed: () => _setStatus(ev, VerificationStatus.rejected),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

Color _verifyColor(VerificationStatus s) => switch (s) {
      VerificationStatus.accepted => AppColors.forest,
      VerificationStatus.rejected => AppColors.danger,
      VerificationStatus.needsMore => AppColors.amber,
      VerificationStatus.pending => AppColors.muted,
    };

// ---------------------------------------------------------------------------
// Final decision
// ---------------------------------------------------------------------------

class _DecisionSection extends ConsumerStatefulWidget {
  const _DecisionSection({required this.session});

  final AssessmentSession session;

  @override
  ConsumerState<_DecisionSection> createState() => _DecisionSectionState();
}

class _DecisionSectionState extends ConsumerState<_DecisionSection> {
  late final TextEditingController _reasoning;
  late final TextEditingController _comments;
  late final TextEditingController _signature;
  Recommendation? _recommendation;
  bool _ack = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _reasoning = TextEditingController(text: widget.session.overallReasoning);
    _comments = TextEditingController(text: widget.session.assessorFinalComments);
    _signature = TextEditingController(text: widget.session.assessorSignatureName);
    _recommendation = widget.session.recommendation;
    _ack = widget.session.disclaimerAcknowledged;
  }

  @override
  void dispose() {
    _reasoning.dispose();
    _comments.dispose();
    _signature.dispose();
    super.dispose();
  }

  bool get _canFinalise =>
      _ack && _signature.text.trim().isNotEmpty && _recommendation != null && !_busy;

  Future<void> _finalise() async {
    setState(() => _busy = true);
    try {
      final repo = await ref.read(repositoryProvider.future);
      final updated = widget.session.copyWith(
        status: SessionStatus.completed,
        recommendation: _recommendation,
        overallReasoning: _reasoning.text.trim(),
        assessorFinalComments: _comments.text.trim(),
        assessorSignatureName: _signature.text.trim(),
        disclaimerAcknowledged: true,
        completedAt: DateTime.now(),
      );
      await repo.updateSession(updated);
      ref.invalidate(sessionProvider(widget.session.id));
      if (!mounted) return;
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => ReportScreen(sessionId: widget.session.id)),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      title: 'Human determination',
      subtitle: 'The tool supports, but never replaces, the assessor.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DropdownButtonFormField<Recommendation>(
            initialValue: _recommendation,
            decoration: const InputDecoration(labelText: 'Recommendation', isDense: true),
            items: [
              for (final r in Recommendation.values)
                DropdownMenuItem(value: r, child: Text(_recommendationLabel(r))),
            ],
            onChanged: (v) => setState(() => _recommendation = v),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _reasoning,
            minLines: 2,
            maxLines: 4,
            decoration: const InputDecoration(labelText: 'Overall reasoning', isDense: true),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _comments,
            minLines: 2,
            maxLines: 4,
            decoration: const InputDecoration(labelText: 'Assessor final comments', isDense: true),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _signature,
            decoration: const InputDecoration(labelText: 'Assessor signature name', isDense: true),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 6),
          CheckboxListTile(
            value: _ack,
            onChanged: (v) => setState(() => _ack = v ?? false),
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            title: const Text(
              'I acknowledge this prototype does not issue official NSQF certification.',
              style: TextStyle(fontSize: 13),
            ),
          ),
          const SizedBox(height: 6),
          FilledButton.icon(
            onPressed: _canFinalise ? _finalise : null,
            icon: const Icon(Icons.verified_outlined),
            label: Text(_busy ? 'Finalising…' : 'Finalise assessment'),
          ),
        ],
      ),
    );
  }
}

String _recommendationLabel(Recommendation r) => switch (r) {
      Recommendation.provisionalCompetencyRecommended => 'Provisional competency recommended',
      Recommendation.gapTrainingRequired => 'Gap training required',
      Recommendation.additionalEvidenceNeeded => 'Additional evidence needed',
    };
