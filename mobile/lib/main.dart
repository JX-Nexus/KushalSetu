import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';

import 'screens/welcome_screen.dart';
import 'services/catalogue_service.dart';
import 'services/local_db.dart';
import 'services/sync_service.dart';
import 'state/app_state.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);

  final app = AppState();
  await app.init();
  final db = LocalDb();
  await db.init();
  final catalogue = CatalogueService();
  await catalogue.load();
  final sync = SyncService(db, app);

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<AppState>.value(value: app),
        Provider<LocalDb>.value(value: db),
        ChangeNotifierProvider<CatalogueService>.value(value: catalogue),
        ChangeNotifierProvider<SyncService>.value(value: sync),
      ],
      child: const KaushalSetuApp(),
    ),
  );

  // Background work after the first frame: never blocks start-up, never needs a network.
  app.checkServer().then((ok) {
    if (ok) catalogue.refresh(app.api);
  });
  sync.start();
}

class KaushalSetuApp extends StatelessWidget {
  const KaushalSetuApp({super.key});

  @override
  Widget build(BuildContext context) {
    final lang = context.select<AppState, String>((s) => s.lang);
    return MaterialApp(
      title: 'KaushalSetu',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      locale: Locale(lang),
      supportedLocales: const [Locale('en'), Locale('hi'), Locale('mr')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: const WelcomeScreen(),
    );
  }
}
