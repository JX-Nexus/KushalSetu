import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Icon for a trade/sector, chosen from the catalogue text (nothing is hardcoded per trade).
IconData iconForTrade(String text) {
  final t = text.toLowerCase();
  if (t.contains('plumb')) return Icons.plumbing;
  if (t.contains('electr')) return Icons.electrical_services;
  if (t.contains('weld') || t.contains('fabric')) return Icons.local_fire_department;
  if (t.contains('mason') || t.contains('construct') || t.contains('building')) return Icons.foundation;
  if (t.contains('carpen') || t.contains('wood')) return Icons.carpenter;
  if (t.contains('paint')) return Icons.format_paint;
  return Icons.handyman;
}

/// Illustration from assets/images. Falls back to an icon if the file is missing,
/// so the app never breaks when artwork is added or removed.
class Illustration extends StatelessWidget {
  final String name; // file name without extension
  final double? height;
  final double? width;
  final IconData fallback;
  const Illustration(this.name, {super.key, this.height, this.width, this.fallback = Icons.image_outlined});

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      'assets/images/$name.png',
      height: height,
      width: width,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.high,
      excludeFromSemantics: true,
      errorBuilder: (_, __, ___) => SizedBox(
        height: height,
        width: width,
        child: Icon(fallback, size: (height ?? 64) * 0.5, color: AppTheme.line),
      ),
    );
  }
}

/// Trade artwork keyed by qualification-pack code (assets/images/trade_<code>.png).
/// New trades pick up their art automatically; otherwise a trade icon is shown.
class TradeArt extends StatelessWidget {
  final String code;
  final String hint; // sector/title text used to choose a fallback icon
  final double size;
  final Color background;
  const TradeArt({
    super.key,
    required this.code,
    required this.hint,
    this.size = 56,
    this.background = AppTheme.accentSoft,
  });

  @override
  Widget build(BuildContext context) {
    final key = code.toLowerCase().replaceAll('-', '_');
    return Container(
      width: size,
      height: size,
      padding: EdgeInsets.all(size * 0.08),
      decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(size * 0.28)),
      child: Image.asset(
        'assets/images/trade_$key.png',
        fit: BoxFit.contain,
        filterQuality: FilterQuality.high,
        excludeFromSemantics: true,
        errorBuilder: (_, __, ___) =>
            Icon(iconForTrade(hint), color: AppTheme.accent, size: size * 0.52),
      ),
    );
  }
}

/// Gentle entrance (fade + slide). Respects the "reduce motion" accessibility setting.
class FadeSlideIn extends StatelessWidget {
  final Widget child;
  final int delayMs;
  const FadeSlideIn({super.key, required this.child, this.delayMs = 0});

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.of(context).disableAnimations;
    if (reduce) return child;
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: Duration(milliseconds: 420 + delayMs),
      curve: Curves.easeOutCubic,
      builder: (context, v, c) => Opacity(
        opacity: v,
        child: Transform.translate(offset: Offset(0, 18 * (1 - v)), child: c),
      ),
      child: child,
    );
  }
}

class _HeroPatternPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawCircle(Offset(size.width * 0.92, size.height * 0.12), 74, Paint()..color = AppTheme.saffron.withAlpha(46));
    canvas.drawCircle(Offset(size.width * 0.78, size.height * 0.30), 26, Paint()..color = AppTheme.sun.withAlpha(60));
    canvas.drawCircle(Offset(size.width * 0.04, size.height * 0.95), 62, Paint()..color = AppTheme.teal.withAlpha(48));
    final dot = Paint()..color = Colors.white.withAlpha(34);
    for (var i = 0; i < 4; i++) {
      for (var j = 0; j < 3; j++) {
        canvas.drawCircle(Offset(size.width * 0.52 + i * 14.0, size.height * 0.10 + j * 14.0), 2.2, dot);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Saffron / white / green accent line (public-service identity, kept subtle).
class AccentStripe extends StatelessWidget {
  const AccentStripe({super.key});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 5,
      child: Row(children: const [
        Expanded(child: ColoredBox(color: AppTheme.saffron, child: SizedBox.expand())),
        Expanded(child: ColoredBox(color: Colors.white, child: SizedBox.expand())),
        Expanded(child: ColoredBox(color: AppTheme.accent, child: SizedBox.expand())),
      ]),
    );
  }
}

/// Header used at the top of main screens: navy gradient, soft colour shapes, accent stripe.
/// Handles the status-bar inset itself. `art` is an optional illustration at the right.
class HeroHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final VoidCallback? onBack;
  final List<Widget> actions;
  final Widget? child;
  final Widget? art;
  final double titleSize;
  const HeroHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.onBack,
    this.actions = const [],
    this.child,
    this.art,
    this.titleSize = 25,
  });

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.of(context).padding.top;
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(bottom: Radius.circular(AppTheme.rHero)),
      child: Container(
        width: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [AppTheme.primaryDark, AppTheme.navyLight],
          ),
        ),
        child: Stack(children: [
          Positioned.fill(child: CustomPaint(painter: _HeroPatternPainter())),
          Padding(
            padding: EdgeInsets.fromLTRB(8, top + 6, 8, 26),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                if (onBack != null)
                  IconButton(
                    tooltip: 'Back',
                    icon: const Icon(Icons.arrow_back, color: Colors.white),
                    onPressed: onBack,
                  )
                else
                  const SizedBox(width: 12),
                const Spacer(),
                ...actions,
              ]),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(title,
                          style: TextStyle(color: Colors.white, fontSize: titleSize, fontWeight: FontWeight.w800, height: 1.2)),
                      if (subtitle != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(subtitle!,
                              style: TextStyle(color: Colors.white.withAlpha(215), fontSize: 14.5, height: 1.35)),
                        ),
                    ]),
                  ),
                  if (art != null) Padding(padding: const EdgeInsets.only(left: 8), child: art!),
                ]),
              ),
              if (child != null) ...[const SizedBox(height: 14), Padding(padding: const EdgeInsets.symmetric(horizontal: 12), child: child!)],
            ]),
          ),
          const Positioned(left: 0, right: 0, bottom: 0, child: AccentStripe()),
        ]),
      ),
    );
  }
}

/// Illustrated "how it works" step.
class HowItWorksStep extends StatelessWidget {
  final String image;
  final int number;
  final String text;
  final Color color;
  final Color soft;
  const HowItWorksStep({
    super.key,
    required this.image,
    required this.number,
    required this.text,
    required this.color,
    required this.soft,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: soft, borderRadius: BorderRadius.circular(20)),
      child: Row(children: [
        SizedBox(width: 92, height: 92, child: Illustration(image, height: 92, fallback: Icons.image_outlined)),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              width: 28,
              height: 28,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              child: Text('$number', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
            ),
            const SizedBox(height: 6),
            Text(text, style: const TextStyle(fontSize: 15, height: 1.35, fontWeight: FontWeight.w600, color: AppTheme.ink)),
          ]),
        ),
      ]),
    );
  }
}

/// Coloured section header (one colour per competency area).
class NosHeader extends StatelessWidget {
  final int index;
  final String title;
  const NosHeader({super.key, required this.index, required this.title});

  @override
  Widget build(BuildContext context) {
    final c = AppTheme.sectionColors[index % AppTheme.sectionColors.length];
    return Container(
      margin: const EdgeInsets.fromLTRB(0, 18, 0, 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(color: c[1], borderRadius: BorderRadius.circular(14)),
      child: Row(children: [
        Container(
          width: 30,
          height: 30,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: c[0], borderRadius: BorderRadius.circular(9)),
          child: Text('${index + 1}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
        ),
        const SizedBox(width: 10),
        Expanded(child: Text(title, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: c[0]))),
      ]),
    );
  }
}

/// Circular progress with a centred label (e.g. 4/6 tasks).
class ProgressRing extends StatelessWidget {
  final double value; // 0..1
  final double size;
  final double stroke;
  final String label;
  final String? caption;
  final Color color;
  final Color track;
  final Color textColor;
  const ProgressRing({
    super.key,
    required this.value,
    required this.label,
    this.caption,
    this.size = 84,
    this.stroke = 9,
    this.color = AppTheme.accent,
    this.track = AppTheme.primarySoft,
    this.textColor = AppTheme.ink,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Stack(alignment: Alignment.center, children: [
        CustomPaint(
          size: Size(size, size),
          painter: _RingPainter(value.clamp(0.0, 1.0), stroke, color, track),
        ),
        Column(mainAxisSize: MainAxisSize.min, children: [
          Text(label, style: TextStyle(fontSize: size * 0.24, fontWeight: FontWeight.w800, color: textColor)),
          if (caption != null)
            Text(caption!, style: TextStyle(fontSize: size * 0.12, color: textColor.withAlpha(170))),
        ]),
      ]),
    );
  }
}

class _RingPainter extends CustomPainter {
  final double value;
  final double stroke;
  final Color color;
  final Color track;
  _RingPainter(this.value, this.stroke, this.color, this.track);

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(stroke / 2, stroke / 2, size.width - stroke, size.height - stroke);
    final base = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..color = track;
    canvas.drawArc(rect, 0, 2 * math.pi, false, base);
    if (value <= 0) return;
    final fg = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..color = color;
    canvas.drawArc(rect, -math.pi / 2, 2 * math.pi * value, false, fg);
  }

  @override
  bool shouldRepaint(covariant _RingPainter old) =>
      old.value != value || old.color != color || old.track != track || old.stroke != stroke;
}

/// Radar chart of competency per NOS (values 0..1). Needs 3+ axes; falls back to bars otherwise.
class RadarChart extends StatelessWidget {
  final List<String> labels;
  final List<double> values;
  final double height;
  const RadarChart({super.key, required this.labels, required this.values, this.height = 270});

  @override
  Widget build(BuildContext context) {
    if (labels.length < 3 || labels.length != values.length) {
      return Column(children: [
        for (var i = 0; i < labels.length && i < values.length; i++)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(children: [
              Expanded(flex: 4, child: Text(labels[i], style: const TextStyle(fontSize: 13))),
              Expanded(
                flex: 5,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                      value: values[i].clamp(0.0, 1.0), minHeight: 10, backgroundColor: AppTheme.primarySoft),
                ),
              ),
            ]),
          ),
      ]);
    }
    return SizedBox(
      height: height,
      width: double.infinity,
      child: CustomPaint(painter: _RadarPainter(labels, values)),
    );
  }
}

class _RadarPainter extends CustomPainter {
  final List<String> labels;
  final List<double> values;
  _RadarPainter(this.labels, this.values);

  Offset _pt(Offset c, double r, int i, int n) {
    final a = -math.pi / 2 + 2 * math.pi * i / n;
    return Offset(c.dx + r * math.cos(a), c.dy + r * math.sin(a));
  }

  @override
  void paint(Canvas canvas, Size size) {
    final n = labels.length;
    final c = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2 - 52;
    final grid = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = AppTheme.line;
    for (var ring = 1; ring <= 4; ring++) {
      final path = Path();
      for (var i = 0; i < n; i++) {
        final p = _pt(c, radius * ring / 4, i, n);
        if (i == 0) {
          path.moveTo(p.dx, p.dy);
        } else {
          path.lineTo(p.dx, p.dy);
        }
      }
      path.close();
      canvas.drawPath(path, grid);
    }
    for (var i = 0; i < n; i++) {
      canvas.drawLine(c, _pt(c, radius, i, n), grid);
    }
    final poly = Path();
    for (var i = 0; i < n; i++) {
      final p = _pt(c, radius * values[i].clamp(0.0, 1.0), i, n);
      if (i == 0) {
        poly.moveTo(p.dx, p.dy);
      } else {
        poly.lineTo(p.dx, p.dy);
      }
    }
    poly.close();
    canvas.drawPath(poly, Paint()..color = AppTheme.primary.withAlpha(60));
    canvas.drawPath(
        poly,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5
          ..color = AppTheme.primary);
    for (var i = 0; i < n; i++) {
      final p = _pt(c, radius * values[i].clamp(0.0, 1.0), i, n);
      canvas.drawCircle(p, 4.5, Paint()..color = AppTheme.accent);
    }
    // labels
    for (var i = 0; i < n; i++) {
      final text = '${labels[i]}\n${(values[i] * 100).round()}%';
      final tp = TextPainter(
        text: TextSpan(
          text: text,
          style: const TextStyle(color: AppTheme.ink, fontSize: 11.5, fontWeight: FontWeight.w700, height: 1.25),
        ),
        textAlign: TextAlign.center,
        textDirection: TextDirection.ltr,
        maxLines: 3,
        ellipsis: '…',
      )..layout(maxWidth: 104);
      final p = _pt(c, radius + 30, i, n);
      var dx = p.dx - tp.width / 2;
      dx = dx.clamp(0.0, math.max(0.0, size.width - tp.width)).toDouble();
      var dy = p.dy - tp.height / 2;
      dy = dy.clamp(0.0, math.max(0.0, size.height - tp.height)).toDouble();
      tp.paint(canvas, Offset(dx, dy));
    }
  }

  @override
  bool shouldRepaint(covariant _RadarPainter old) => old.labels != labels || old.values != values;
}

/// "Question 3 of 6" bar.
class StepProgressBar extends StatelessWidget {
  final int current;
  final int total;
  final String label;
  const StepProgressBar({super.key, required this.current, required this.total, required this.label});

  @override
  Widget build(BuildContext context) {
    final v = total == 0 ? 0.0 : (current / total).clamp(0.0, 1.0);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: const TextStyle(fontWeight: FontWeight.w700, color: AppTheme.inkSoft, fontSize: 13.5)),
      const SizedBox(height: 8),
      ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: LinearProgressIndicator(value: v, minHeight: 10, backgroundColor: AppTheme.primarySoft, color: AppTheme.accent),
      ),
    ]);
  }
}

/// Large radio-style choice tile (clear 56dp tap target).
class OptionTile extends StatelessWidget {
  final String label;
  final String? subtitle;
  final bool selected;
  final VoidCallback? onTap;
  final Color? accent;
  const OptionTile({super.key, required this.label, required this.selected, this.onTap, this.subtitle, this.accent});

  @override
  Widget build(BuildContext context) {
    final color = accent ?? AppTheme.accent;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: selected ? color.withAlpha(24) : AppTheme.surface,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Container(
            constraints: const BoxConstraints(minHeight: 56),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: selected ? color : AppTheme.line, width: selected ? 2 : 1),
            ),
            child: Row(children: [
              Icon(selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                  color: selected ? color : AppTheme.inkSoft),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(label,
                      style: TextStyle(
                          fontSize: 15.5, fontWeight: selected ? FontWeight.w700 : FontWeight.w500, color: AppTheme.ink)),
                  if (subtitle != null)
                    Text(subtitle!, style: const TextStyle(fontSize: 12.5, color: AppTheme.inkSoft)),
                ]),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Square action tile (icon over label), like the quick-access tiles in the references.
class ActionTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final Color color;
  final Color background;
  const ActionTile({
    super.key,
    required this.icon,
    required this.label,
    this.onTap,
    this.color = AppTheme.primary,
    this.background = AppTheme.primarySoft,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: background,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 88),
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 12),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(icon, size: 30, color: onTap == null ? AppTheme.inkSoft : color),
            const SizedBox(height: 6),
            Text(label,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: onTap == null ? AppTheme.inkSoft : color)),
          ]),
        ),
      ),
    );
  }
}

/// Trade card with a leading icon; used for matches and "browse all trades".
class TradeCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool highlighted;
  final Widget? footer;
  final String? artCode;
  const TradeCard({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.trailing,
    this.onTap,
    this.highlighted = false,
    this.footer,
    this.artCode,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Material(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: highlighted ? AppTheme.accent : AppTheme.line, width: highlighted ? 2 : 1),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                if (artCode != null)
                  TradeArt(code: artCode!, hint: title, size: 64)
                else
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(color: AppTheme.accentSoft, borderRadius: BorderRadius.circular(14)),
                    child: Icon(icon, color: AppTheme.accent, size: 28),
                  ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: AppTheme.ink)),
                    const SizedBox(height: 2),
                    Text(subtitle, style: const TextStyle(color: AppTheme.inkSoft, fontSize: 13)),
                  ]),
                ),
                if (trailing != null) trailing!,
              ]),
              if (footer != null) ...[const SizedBox(height: 10), footer!],
            ]),
          ),
        ),
      ),
    );
  }
}

/// Compact number + caption tile.
class StatTile extends StatelessWidget {
  final String value;
  final String caption;
  final Color color;
  final Color background;
  const StatTile({
    super.key,
    required this.value,
    required this.caption,
    this.color = AppTheme.primaryDark,
    this.background = AppTheme.surface,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
          color: background, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppTheme.line)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Text(value, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: color)),
        const SizedBox(height: 2),
        Text(caption, style: const TextStyle(fontSize: 12, color: AppTheme.inkSoft)),
      ]),
    );
  }
}

/// Numbered "how it works" step.
class NumberedStep extends StatelessWidget {
  final int number;
  final String text;
  const NumberedStep({super.key, required this.number, required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          width: 30,
          height: 30,
          alignment: Alignment.center,
          decoration: const BoxDecoration(color: AppTheme.primary, shape: BoxShape.circle),
          child: Text('$number', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
        ),
        const SizedBox(width: 12),
        Expanded(child: Padding(padding: const EdgeInsets.only(top: 4), child: Text(text, style: const TextStyle(fontSize: 15, height: 1.35)))),
      ]),
    );
  }
}
