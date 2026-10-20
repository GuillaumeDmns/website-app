import 'package:flutter/material.dart';

import '../../app/theme.dart';

/// Title of a section of a page, with an optional action on the right ("Tout voir")
class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key, this.trailing, this.padding = const EdgeInsets.fromLTRB(4, 18, 4, 8)});

  final String text;
  final Widget? trailing;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) => Padding(
        padding: padding,
        child: Row(
          children: [
            Expanded(child: Semantics(header: true, child: Text(text, style: Theme.of(context).textTheme.titleMedium))),
            ?trailing,
          ],
        ),
      );
}

/// White rounded card of the pages (grey background), tappable when [onTap] is given
class AppCard extends StatelessWidget {
  const AppCard({super.key, required this.child, this.onTap, this.onLongPress, this.padding = const EdgeInsets.all(16), this.color, this.border});

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final EdgeInsets padding;
  final Color? color;

  /// Outlines a selected card
  final Color? border;

  @override
  Widget build(BuildContext context) {
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppTheme.radius),
      side: border == null ? BorderSide.none : BorderSide(color: border!, width: 2),
    );
    return Card(
      color: color,
      shape: border == null ? null : shape,
      clipBehavior: Clip.antiAlias,
      child: onTap == null && onLongPress == null
          ? Padding(padding: padding, child: child)
          : InkWell(onTap: onTap, onLongPress: onLongPress, onSecondaryTap: onLongPress, child: Padding(padding: padding, child: child)),
    );
  }
}

/// Round action with its label below, like the actions of Citymapper's stop pages; [primary] is filled
class RoundAction extends StatelessWidget {
  const RoundAction({super.key, required this.icon, required this.label, required this.onPressed, this.primary = false, this.color});

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final bool primary;

  /// Icon color of a plain action (a saved favorite's star)
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final colors = context.colors;
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: primary ? scheme.primary : colors.card,
                  shape: BoxShape.circle,
                  border: primary ? null : Border.all(color: scheme.outline),
                ),
                child: Icon(icon, size: 22, color: primary ? scheme.onPrimary : color ?? scheme.onSurface),
              ),
              const SizedBox(height: 6),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(color: scheme.onSurface),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Small colored tag, with an icon or not: real time, a delay, boarding position, last metro, the next stop
class PillTag extends StatelessWidget {
  const PillTag({super.key, this.icon, required this.text, required this.color});

  final IconData? icon;
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(999)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 14, color: color),
              const SizedBox(width: 4),
            ],
            Flexible(child: Text(text, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600))),
          ],
        ),
      );
}

/// An icon on a round tinted background (place kinds, saved places)
class IconBubble extends StatelessWidget {
  const IconBubble(this.icon, {super.key, this.color, this.size = 40});

  final IconData icon;
  final Color? color;
  final double size;

  @override
  Widget build(BuildContext context) {
    final tint = color ?? Theme.of(context).colorScheme.onSurface;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: color == null ? context.colors.subtle : tint.withValues(alpha: 0.14), shape: BoxShape.circle),
      child: Icon(icon, size: size * 0.5, color: tint),
    );
  }
}

/// A line of a card telling something to watch (last metro, schedule only): icon and text in the warning color
class NoticeLine extends StatelessWidget {
  const NoticeLine({super.key, required this.icon, required this.text, this.color});

  final IconData icon;
  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final tint = color ?? context.colors.warning;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: tint),
        const SizedBox(width: 6),
        Expanded(child: Text(text, style: TextStyle(color: tint, fontSize: 13, fontWeight: FontWeight.w600))),
      ],
    );
  }
}
