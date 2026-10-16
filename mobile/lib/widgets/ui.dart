import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../i18n/strings.dart';
import '../services/sync_service.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';

/// Translation helper (worker-facing strings). Reads the current language.
String tr(BuildContext context, String key) {
  final lang = Provider.of<AppState>(context, listen: false).lang;
  return Strings.t(lang, key);
}

String curLang(BuildContext context) => Provider.of<AppState>(context, listen: false).lang;

void toast(BuildContext context, String message, {bool error = false}) {
  final m = ScaffoldMessenger.maybeOf(context);
  if (m == null) return;
  m.hideCurrentSnackBar();
  m.showSnackBar(SnackBar(
    content: Text(message),
    backgroundColor: error ? AppTheme.danger : AppTheme.primaryDark,
    behavior: SnackBarBehavior.floating,
  ));
}

class Pill extends StatelessWidget {
  final String text;
  final Color color;
  final Color background;
  final IconData? icon;
  const Pill(this.text, {super.key, required this.color, required this.background, this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(20)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (icon != null) ...[Icon(icon, size: 14, color: color), const SizedBox(width: 4)],
        Flexible(
          child: Text(text,
              style: TextStyle(color: color, fontSize: 12.5, fontWeight: FontWeight.w600),
              overflow: TextOverflow.ellipsis),
        ),
      ]),
    );
  }
}

Pill statusPill(BuildContext context, String status) {
  switch (status) {
    case 'signed_off':
      return Pill(tr(context, 'status_signed_off'),
          color: AppTheme.success, background: AppTheme.successSoft, icon: Icons.verified);
    case 'under_review':
      return Pill(tr(context, 'status_under_review'),
          color: AppTheme.info, background: AppTheme.infoSoft, icon: Icons.rate_review);
    case 'submitted':
      return Pill(tr(context, 'status_submitted'),
          color: AppTheme.warning, background: AppTheme.warningSoft, icon: Icons.hourglass_top);
    case 'needs_evidence':
      return Pill(tr(context, 'status_needs_evidence'),
          color: AppTheme.danger, background: AppTheme.dangerSoft, icon: Icons.add_a_photo);
    default:
      return Pill(tr(context, 'status_in_progress'),
          color: AppTheme.inkSoft, background: const Color(0xFFEDEAE2), icon: Icons.edit_note);
  }
}

/// Offline / online + pending-sync indicator. Tap to sync now.
class ConnectionChip extends StatelessWidget {
  const ConnectionChip({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final sync = context.watch<SyncService>();
    final online = app.serverReachable;
    final label = sync.syncing
        ? '…'
        : online
            ? (sync.pending > 0 ? '${sync.pending} ${tr(context, 'pending_sync')}' : tr(context, 'online'))
            : tr(context, 'offline');
    final color = online ? AppTheme.success : AppTheme.warning;
    final bg = online ? AppTheme.successSoft : AppTheme.warningSoft;
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: sync.syncing ? null : () => sync.syncAll(),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          sync.syncing
              ? SizedBox(
                  width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: color))
              : Icon(online ? Icons.cloud_done : Icons.cloud_off, size: 16, color: color),
          const SizedBox(width: 6),
          Text(label, style: TextStyle(color: color, fontSize: 12.5, fontWeight: FontWeight.w600)),
        ]),
      ),
    );
  }
}

class SectionTitle extends StatelessWidget {
  final String text;
  final Widget? trailing;
  const SectionTitle(this.text, {super.key, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 18, 4, 8),
      child: Row(children: [
        Expanded(
          child: Text(text,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: AppTheme.ink)),
        ),
        if (trailing != null) trailing!,
      ]),
    );
  }
}

class AppCard extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  final Color? color;
  final VoidCallback? onTap;
  final Color? border;
  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(14),
    this.color,
    this.onTap,
    this.border,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Material(
        color: color ?? AppTheme.surface,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Container(
            padding: padding,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: border ?? AppTheme.line),
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}

class InfoBanner extends StatelessWidget {
  final String text;
  final IconData icon;
  final Color color;
  final Color background;
  const InfoBanner(this.text,
      {super.key,
      this.icon = Icons.info_outline,
      this.color = AppTheme.info,
      this.background = AppTheme.infoSoft});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(12)),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, size: 20, color: color),
        const SizedBox(width: 10),
        Expanded(child: Text(text, style: TextStyle(color: color, height: 1.35))),
      ]),
    );
  }
}

class EmptyState extends StatelessWidget {
  final IconData icon;
  final String text;
  const EmptyState(this.icon, this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 56, color: AppTheme.line),
          const SizedBox(height: 12),
          Text(text, textAlign: TextAlign.center, style: const TextStyle(color: AppTheme.inkSoft, fontSize: 15)),
        ]),
      ),
    );
  }
}

Future<bool> confirm(BuildContext context, String message, {String? yes, String? no}) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      content: Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(no ?? tr(context, 'cancel'))),
        FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(90, 44)),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(yes ?? 'OK')),
      ],
    ),
  );
  return r == true;
}
