import 'package:flutter/material.dart';

import '../data/station.dart';
import 'format.dart';
import 'strings.dart';

/// Station detail sheet: prices (if any), address, opening hours and directions.
class StationSheet extends StatelessWidget {
  const StationSheet({
    super.key,
    required this.station,
    required this.fuel,
    required this.distance,
    required this.rank,
    required this.total,
    required this.change,
    required this.publisher,
    required this.updatedAt,
    required this.onDirections,
    required this.onWaze,
  });

  final Station station;
  final Fuel fuel;
  final double? distance;
  final int? rank;
  final int total;
  final double? change;
  final String? publisher;
  final DateTime? updatedAt;
  final VoidCallback onDirections, onWaze;

  @override
  Widget build(BuildContext context) {
    final t = T.current;
    final theme = Theme.of(context);
    final s = station;
    final selectedPrice = s.prices[fuel];
    final schedule = s.schedule == '24/7' ? t.open247 : s.schedule;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(s.brand.isEmpty ? t.station : s.brand, style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 4),
                  Text(
                    [s.address, s.town, if (s.postcode.isNotEmpty) s.postcode, s.region, if (s.country.isNotEmpty) t.country(s.country)]
                        .where((e) => e.isNotEmpty)
                        .join(', '),
                    style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                ]),
              ),
              if (selectedPrice != null)
                Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Text(formatPrice(selectedPrice, s.currency),
                      style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900, color: theme.colorScheme.primary)),
                  Text(t.fuel(fuel), style: theme.textTheme.bodySmall),
                ]),
            ]),
            const SizedBox(height: 14),
            Wrap(spacing: 8, runSpacing: 8, children: [
              if (rank != null)
                _Tag(
                  icon: rank == 1 ? Icons.emoji_events_rounded : Icons.leaderboard_rounded,
                  text: rank == 1 ? t.cheapestHere : t.rankOf(rank!, total),
                  color: rank == 1 ? cheapColor : null,
                ),
              if (distance != null) _Tag(icon: Icons.near_me_rounded, text: t.away(formatDistance(distance!))),
              if (change != null)
                _Tag(
                  icon: change! < 0 ? Icons.trending_down_rounded : Icons.trending_up_rounded,
                  text: change! < 0 ? t.wentDown(formatCents(change!)) : t.wentUp(formatCents(change!)),
                  color: change! < 0 ? cheapColor : expensiveColor,
                ),
            ]),
            const SizedBox(height: 18),
            Row(children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: onDirections,
                  icon: const Icon(Icons.directions_rounded),
                  label: Text(t.directions),
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onWaze,
                  icon: const Icon(Icons.navigation_rounded),
                  label: const Text('Waze'),
                  style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                ),
              ),
            ]),
            const SizedBox(height: 22),
            if (s.hasPrices) ...[
              Text(t.prices, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              for (final f in Fuel.values)
                if (s.prices[f] != null)
                  Container(
                    margin: const EdgeInsets.only(bottom: 6),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                    decoration: BoxDecoration(
                      color: f == fuel ? theme.colorScheme.primaryContainer : theme.colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(children: [
                      Expanded(child: Text(t.fuel(f), style: TextStyle(fontWeight: f == fuel ? FontWeight.w700 : FontWeight.w500))),
                      Text(formatPrice(s.prices[f]!, s.currency), style: const TextStyle(fontWeight: FontWeight.w800)),
                    ]),
                  ),
              const SizedBox(height: 16),
            ] else if (s.fuels.isNotEmpty) ...[
              Text(t.fuels, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              Wrap(spacing: 8, runSpacing: 8, children: [for (final f in Fuel.values) if (s.fuels.contains(f)) Chip(label: Text(t.fuel(f)))]),
              const SizedBox(height: 16),
            ],
            if (schedule.isNotEmpty) ...[
              Text(t.hours, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Icon(Icons.schedule_rounded, size: 18),
                const SizedBox(width: 8),
                Expanded(child: Text(schedule.replaceAll('; ', '\n'))),
              ]),
              const SizedBox(height: 16),
            ],
            Text(
              s.hasPrices && publisher != null
                  ? t.publishedBy(publisher!, updatedAt == null ? '' : '${formatClock(updatedAt!)} ${formatDayMonth(updatedAt!)}')
                  : t.noPriceNote,
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag({required this.icon, required this.text, this.color});
  final IconData icon;
  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color ?? Theme.of(context).colorScheme.onSurfaceVariant;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(color: c.withValues(alpha: .1), borderRadius: BorderRadius.circular(99)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 16, color: c),
        const SizedBox(width: 5),
        Flexible(child: Text(text, style: TextStyle(color: c, fontWeight: FontWeight.w600, fontSize: 13))),
      ]),
    );
  }
}
