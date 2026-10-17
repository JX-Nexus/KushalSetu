import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/design.dart';
import '../widgets/ui.dart';
import 'assessor/assessor_login_screen.dart';
import 'assessor/assessor_queue_screen.dart';
import 'settings_screen.dart';
import 'worker/worker_home_screen.dart';

class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key});
  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<AppState>().checkServer();
    });
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    return Scaffold(
      body: Column(children: [
        HeroHeader(
          title: tr(context, 'app_name'),
          subtitle: tr(context, 'tagline'),
          actions: [
            const ConnectionChip(),
            IconButton(
              tooltip: tr(context, 'settings'),
              icon: const Icon(Icons.settings, color: Colors.white),
              onPressed: () => Navigator.of(context)
                  .push(MaterialPageRoute(builder: (_) => const SettingsScreen())),
            ),
          ],
          art: const Illustration('logo_mark', height: 64, fallback: Icons.handyman),
        ),
        Expanded(
          child: ListView(padding: const EdgeInsets.fromLTRB(20, 18, 20, 24), children: [
            FadeSlideIn(
              child: Container(
                padding: const EdgeInsets.fromLTRB(12, 14, 12, 8),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                      begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [AppTheme.saffronSoft, AppTheme.tealSoft]),
                  borderRadius: BorderRadius.circular(24),
                ),
                child: const Illustration('hero_workers', height: 150, fallback: Icons.groups),
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              icon: const Icon(Icons.person),
              label: Text(tr(context, 'i_am_worker')),
              onPressed: () => Navigator.of(context)
                  .push(MaterialPageRoute(builder: (_) => const WorkerHomeScreen())),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              icon: const Icon(Icons.fact_check),
              label: Text(tr(context, 'i_am_assessor')),
              onPressed: () {
                final next = app.assessorToken == null
                    ? const AssessorLoginScreen()
                    : const AssessorQueueScreen();
                Navigator.of(context).push(MaterialPageRoute(builder: (_) => next));
              },
            ),
            const SizedBox(height: 22),
            Text(tr(context, 'language'),
                style: const TextStyle(fontWeight: FontWeight.w700, color: AppTheme.inkSoft)),
            const SizedBox(height: 8),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment<String>(value: 'en', label: Text('English')),
                ButtonSegment<String>(value: 'hi', label: Text('हिन्दी')),
                ButtonSegment<String>(value: 'mr', label: Text('मराठी')),
              ],
              selected: {app.lang},
              onSelectionChanged: (s) => app.setLang(s.first),
            ),
            SectionTitle(tr(context, 'how_it_works')),
            HowItWorksStep(image: 'illus_step1', number: 1, text: tr(context, 'hiw_1'), color: AppTheme.saffronDeep, soft: AppTheme.saffronSoft),
                HowItWorksStep(image: 'illus_step2', number: 2, text: tr(context, 'hiw_2'), color: AppTheme.teal, soft: AppTheme.tealSoft),
                HowItWorksStep(image: 'illus_assessor', number: 3, text: tr(context, 'hiw_3'), color: AppTheme.plum, soft: AppTheme.plumSoft),
            const SizedBox(height: 10),
            InfoBanner(tr(context, 'disclaimer'), icon: Icons.shield_outlined),
          ]),
        ),
      ]),
    );
  }
}
