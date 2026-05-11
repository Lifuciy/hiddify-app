import 'dart:io';

import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:hiddify/features/settings/data/config_option_repository.dart';
import 'package:hiddify/singbox/model/singbox_config_enum.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class PxyConnectionModePanel extends ConsumerWidget {
  const PxyConnectionModePanel({super.key});

  Future<void> _repairConnection(BuildContext context, WidgetRef ref) async {
    try {
      await ref.read(ConfigOptions.serviceMode.notifier).update(ServiceMode.tun);

      if (Platform.isWindows) {
        const internetSettings = r'HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings';

        await Process.run('reg', [
          'add',
          internetSettings,
          '/v',
          'ProxyEnable',
          '/t',
          'REG_DWORD',
          '/d',
          '0',
          '/f',
        ]);

        await Process.run('reg', [
          'delete',
          internetSettings,
          '/v',
          'ProxyServer',
          '/f',
        ]);

        await Process.run('reg', [
          'delete',
          internetSettings,
          '/v',
          'AutoConfigURL',
          '/f',
        ]);

        await Process.run('netsh', ['winhttp', 'reset', 'proxy']);
      }

      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Подключение исправлено. Режим переключён на TUN. Переподключите PXY.')),
      );
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось починить подключение: $error')),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final mode = ref.watch(ConfigOptions.serviceMode);

    final isTun = mode == ServiceMode.tun || mode == ServiceMode.tunService;
    final selectedTun = isTun;

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
                  Icon(Icons.settings_ethernet_rounded, color: theme.colorScheme.primary),
                  const Gap(8),
                  Text(
                    'Режим подключения',
                    style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ],
              ),
              const Gap(8),
              Text(
                selectedTun
                    ? 'TUN-режим: рекомендуется для обычного использования. Перехватывает трафик всех приложений.'
                    : 'Системный прокси: запасной режим, если TUN не запускается или мешает сети.',
                style: theme.textTheme.bodyMedium,
              ),
              const Gap(12),
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment<bool>(
                    value: true,
                    icon: Icon(Icons.shield_rounded),
                    label: Text('TUN'),
                  ),
                  ButtonSegment<bool>(
                    value: false,
                    icon: Icon(Icons.public_rounded),
                    label: Text('Прокси'),
                  ),
                ],
                selected: {selectedTun},
                onSelectionChanged: (selected) async {
                  final useTun = selected.first;
                  await ref.read(ConfigOptions.serviceMode.notifier).update(
                        useTun ? ServiceMode.tun : ServiceMode.systemProxy,
                      );
                },
              ),
              const Gap(8),
              Text(
                'После смены режима отключите и снова подключите PXY.',
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
              const Gap(12),
              OutlinedButton.icon(
                onPressed: () => _repairConnection(context, ref),
                icon: const Icon(Icons.build_rounded),
                label: const Text('Починить подключение'),
              ),
              const Gap(6),
              Text(
                'Если после закрытия PXY в Windows остался включён системный прокси, нажмите эту кнопку.',
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
