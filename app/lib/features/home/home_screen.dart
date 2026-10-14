import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../widgets/common.dart';
import '../intake/intake_screen.dart';
import '../matching/matching_screen.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final workers = ref.watch(workersProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('KaushalSetu', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 20)),
            Text('RPL Skill Assessment', style: TextStyle(fontSize: 12, color: AppColors.muted)),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppColors.forest,
        foregroundColor: Colors.white,
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const IntakeScreen()),
        ),
        icon: const Icon(Icons.person_add_alt_1),
        label: const Text('New worker'),
      ),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(workersProvider),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
          children: [
            const DisclaimerBanner(),
            const SizedBox(height: 16),
            Row(
              children: const [
                Icon(Icons.groups_outlined, size: 18, color: AppColors.forest),
                SizedBox(width: 8),
                Text('Workers', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
              ],
            ),
            const SizedBox(height: 12),
            workers.when(
              loading: () => const Padding(
                padding: EdgeInsets.only(top: 60),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (e, _) => Padding(
                padding: const EdgeInsets.only(top: 40),
                child: Text('Failed to load local data: $e'),
              ),
              data: (list) {
                if (list.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.only(top: 40),
                    child: EmptyState(
                      icon: Icons.badge_outlined,
                      title: 'No workers yet',
                      message:
                          'Start by capturing a worker\'s background and informal experience declaration. Everything is stored on this device.',
                    ),
                  );
                }
                return Column(
                  children: [
                    for (final w in list)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: _WorkerTile(
                          name: w.name,
                          trade: w.primaryTrade,
                          region: w.locationRegion,
                          years: w.yearsOfExperience,
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => MatchingScreen(workerId: w.id),
                            ),
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _WorkerTile extends StatelessWidget {
  final String name;
  final String trade;
  final String region;
  final double years;
  final VoidCallback onTap;

  const _WorkerTile({
    required this.name,
    required this.trade,
    required this.region,
    required this.years,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              CircleAvatar(
                backgroundColor: AppColors.forest,
                foregroundColor: Colors.white,
                child: Text(name.isNotEmpty ? name[0].toUpperCase() : '?'),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                    const SizedBox(height: 2),
                    Text('$trade • ${years.toStringAsFixed(1)} yrs',
                        style: const TextStyle(fontSize: 12.5, color: AppColors.muted)),
                    if (region.isNotEmpty)
                      Text(region,
                          style: const TextStyle(fontSize: 12, color: AppColors.muted),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: AppColors.muted),
            ],
          ),
        ),
      ),
    );
  }
}
