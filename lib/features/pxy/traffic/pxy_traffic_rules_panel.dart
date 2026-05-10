import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:hiddify/core/model/region.dart';
import 'package:hiddify/features/settings/data/config_option_repository.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class PxyTrafficRulesPanel extends ConsumerWidget {
  const PxyTrafficRulesPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final region = ref.watch(ConfigOptions.region);
    final isRecommended = region == Region.ru;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Card(
        color: theme.colorScheme.surfaceContainer,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(Icons.route_rounded, color: theme.colorScheme.primary),
                  const Gap(8),
                  Text(
                    'Правила трафика',
                    style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ],
              ),
              const Gap(8),
              Text(
                isRecommended
                    ? 'Сейчас российские ресурсы идут напрямую, остальное — через PXY.'
                    : 'Сейчас весь трафик идёт через PXY.',
                style: theme.textTheme.bodyMedium,
              ),
              const Gap(12),
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment<bool>(
                    value: true,
                    icon: Icon(Icons.auto_awesome_rounded),
                    label: Text('Рекомендуемый'),
                  ),
                  ButtonSegment<bool>(
                    value: false,
                    icon: Icon(Icons.lock_rounded),
                    label: Text('Полный VPN'),
                  ),
                ],
                selected: {isRecommended},
                onSelectionChanged: (selected) async {
                  final recommended = selected.first;
                  await ref.read(ConfigOptions.region.notifier).update(
                        recommended ? Region.ru : Region.other,
                      );
                },
              ),
              const Gap(8),
              Text(
                'После смены режима лучше переподключить PXY.',
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
