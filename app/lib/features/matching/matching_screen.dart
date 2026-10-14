import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../domain/models.dart';
import '../../widgets/common.dart';
import '../assessment/assessment_screen.dart';

/// Ranked, non-binding qualification-pack suggestions for a worker.
///
/// Suggestions never certify the candidate; an assessor starts a separate
/// assessment session from any card.
class MatchingScreen extends ConsumerWidget {
  const MatchingScreen({super.key, required this.workerId});

  final String workerId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final worker = ref.watch(workerProvider(workerId));
    final experience = ref.watch(experienceProvider(workerId));
    final matches = ref.watch(matchesProvider(workerId));

    return Scaffold(
      appBar: AppBar(
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Qualification matches',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 20)),
            Text('Non-binding suggestions',
                style: TextStyle(fontSize: 12, color: AppColors.muted)),
          ],
        ),
      ),
      body: worker.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Failed to load worker: $e')),
        data: (w) {
          if (w == null) {
            return const EmptyState(
              icon: Icons.person_off_outlined,
              title: 'Worker not found',
              message: 'This worker record is missing on this device.',
            );
          }
          return experience.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) =>
                Center(child: Text('Failed to load declaration: $e')),
            data: (exp) => matches.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) =>
                  Center(child: Text('Failed to load matches: $e')),
              data: (list) => _MatchesBody(
                worker: w,
                workerId: workerId,
                hasExperience: exp != null,
                matches: list,
              ),
            ),
          );
        },
      ),
    );
  }
}

class _MatchesBody extends StatelessWidget {
  final Worker worker;
  final String workerId;
  final bool hasExperience;
  final List<QualificationMatch> matches;

  const _MatchesBody({
    required this.worker,
    required this.workerId,
    required this.hasExperience,
    required this.matches,
  });

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      children: [
        SectionCard(
          title: worker.name,
          subtitle: worker.primaryTrade,
          child: Column(
            children: [
              Row(
                children: [
                  const Icon(Icons.work_outline,
                      size: 15, color: AppColors.forestSoft),
                  const SizedBox(width: 6),
                  Text(
                    '${worker.yearsOfExperience.toStringAsFixed(1)} yrs of experience',
                    style: const TextStyle(fontSize: 13),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  const Icon(Icons.place_outlined,
                      size: 15, color: AppColors.forestSoft),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      worker.locationRegion.isEmpty
                          ? 'Region not recorded'
                          : worker.locationRegion,
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        const DisclaimerBanner(),
        const SizedBox(height: 12),
        const Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.gavel_outlined, size: 16, color: AppColors.amber),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'These matches are non-binding suggestions only. '
                'They do NOT certify the candidate — only an authorised '
                'assessor decision counts.',
                style: TextStyle(
                    fontSize: 12.5, color: AppColors.muted, height: 1.4),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (!hasExperience)
          const EmptyState(
            icon: Icons.assignment_outlined,
            title: 'No declaration yet',
            message:
                'Complete the worker\u2019s experience declaration first. '
                'Starting an assessment is disabled until then.',
          ),
        if (hasExperience && matches.isEmpty)
          const EmptyState(
            icon: Icons.search_off_outlined,
            title: 'No suggestions yet',
            message:
                'No qualification packs could be suggested for this declaration.',
          ),
        for (var i = 0; i < matches.length; i++) ...[
          const SizedBox(height: 10),
          _MatchCard(
            rank: i + 1,
            match: matches[i],
            workerId: workerId,
            enabled: hasExperience,
          ),
        ],
      ],
    );
  }
}

Color _uncertaintyColor(String level) {
  switch (level.toLowerCase()) {
    case 'low':
      return AppColors.forest;
    case 'moderate':
      return AppColors.amber;
    case 'high':
      return AppColors.danger;
    default:
      return AppColors.muted;
  }
}

class _MatchCard extends ConsumerWidget {
  final int rank;
  final QualificationMatch match;
  final String workerId;
  final bool enabled;

  const _MatchCard({
    required this.rank,
    required this.match,
    required this.workerId,
    required this.enabled,
  });

  Future<void> _startAssessment(BuildContext context, WidgetRef ref) async {
    final repo = await ref.read(repositoryProvider.future);
    final pack = await repo.qualificationPackById(match.qualificationId);
    if (pack == null) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Qualification pack not found on this device.')),
        );
      }
      return;
    }
    final session = AssessmentSession(
      id: const Uuid().v4(),
      workerId: workerId,
      tradeId: pack.tradeId,
      qualificationId: match.qualificationId,
      assessorName: 'Assessor (demo)',
      status: SessionStatus.draft,
      recommendation: null,
      overallReasoning: '',
      assessorFinalComments: '',
      assessorSignatureName: '',
      disclaimerAcknowledged: false,
      createdAt: DateTime.now(),
      completedAt: null,
    );
    await repo.createSession(session);
    if (context.mounted) {
      Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => AssessmentScreen(sessionId: session.id)));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scoreLabel = '${match.matchScorePct.toStringAsFixed(1)}%';

    return SectionCard(
      title: '#$rank · ${match.qualificationTitle}',
      subtitle: 'Ranked suggestion',
      trailing: StatusPill(
        label: 'Uncertainty: ${match.uncertaintyLevel}',
        color: _uncertaintyColor(match.uncertaintyLevel),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                scoreLabel,
                style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  color: AppColors.forest,
                ),
              ),
              const SizedBox(width: 8),
              const Padding(
                padding: EdgeInsets.only(bottom: 5),
                child: Text('match',
                    style: TextStyle(fontSize: 13, color: AppColors.muted)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          LinearProgressIndicator(
            value: (match.matchScorePct / 100).clamp(0.0, 1.0),
            minHeight: 8,
            borderRadius: BorderRadius.circular(999),
            backgroundColor: AppColors.line,
            valueColor:
                const AlwaysStoppedAnimation<Color>(AppColors.forest),
          ),
          const SizedBox(height: 10),
          Text(match.rationale,
              style: const TextStyle(fontSize: 13, height: 1.45)),
          _FactList(
            heading: 'Matched tasks',
            icon: Icons.task_alt_outlined,
            items: match.matchedTasks,
          ),
          _FactList(
            heading: 'Matched tools',
            icon: Icons.handyman_outlined,
            items: match.matchedTools,
          ),
          _FactList(
            heading: 'Missing units',
            icon: Icons.rule_outlined,
            items: match.missingUnits,
          ),
          _FactList(
            heading: 'Uncertainty factors',
            icon: Icons.help_outline,
            items: match.uncertaintyFactors,
          ),
          const SizedBox(height: 14),
          FilledButton(
            onPressed:
                !enabled ? null : () => _startAssessment(context, ref),
            child: const Text('Start assessment'),
          ),
          if (!enabled) ...[
            const SizedBox(height: 8),
            const Text(
              'Complete the worker\u2019s declaration first to start an assessment.',
              style:
                  TextStyle(fontSize: 12, color: AppColors.muted, height: 1.4),
            ),
          ],
        ],
      ),
    );
  }
}

class _FactList extends StatelessWidget {
  final String heading;
  final IconData icon;
  final List<String> items;

  const _FactList({
    required this.heading,
    required this.icon,
    required this.items,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 12),
        Row(
          children: [
            Icon(icon, size: 15, color: AppColors.forestSoft),
            const SizedBox(width: 6),
            Text(heading,
                style:
                    const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
          ],
        ),
        const SizedBox(height: 4),
        if (items.isEmpty)
          const Padding(
            padding: EdgeInsets.only(left: 2, top: 2),
            child: Text('None',
                style: TextStyle(fontSize: 13, color: AppColors.muted)),
          )
        else
          for (final item in items)
            Padding(
              padding: const EdgeInsets.only(left: 2, top: 3),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('\u2022  ',
                      style: TextStyle(color: AppColors.muted)),
                  Expanded(
                    child: Text(item,
                        style:
                            const TextStyle(fontSize: 13, height: 1.4)),
                  ),
                ],
              ),
            ),
      ],
    );
  }
}
