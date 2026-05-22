import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gap/gap.dart';
import 'package:hiddify/features/profile/notifier/active_profile_notifier.dart';
import 'package:hiddify/features/connection/notifier/connection_notifier.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

class PxyDiagnosticsPanel extends ConsumerStatefulWidget {
  const PxyDiagnosticsPanel({super.key});

  @override
  ConsumerState<PxyDiagnosticsPanel> createState() => _PxyDiagnosticsPanelState();
}

class _PxyDiagnosticsPanelState extends ConsumerState<PxyDiagnosticsPanel> {
  static const _accountApiUrl = String.fromEnvironment('PXY_ACCOUNT_API_URL', defaultValue: '');
  static const _supportUrl = 'https://t.me/MarketSellerVPN_help_bot';

  bool _loading = false;
  String? _message;
  List<_PxyDiagRow> _rows = const [];

  Future<void> _runDiagnostics() async {
    setState(() {
      _loading = true;
      _message = null;
      _rows = const [];
    });

    final rows = <_PxyDiagRow>[];

    final apiUrl = _accountApiUrl.trim();
    rows.add(
      _PxyDiagRow(
        title: 'Адрес API PXY',
        ok: apiUrl.isNotEmpty,
        details: apiUrl.isNotEmpty ? apiUrl : 'API URL не задан в сборке приложения',
      ),
    );

    if (apiUrl.isNotEmpty) {
      final healthUrl = '${apiUrl.replaceAll(RegExp(r"/+$"), "")}/health';

      try {
        final response = await Dio().get<dynamic>(
          healthUrl,
          options: Options(
            sendTimeout: const Duration(seconds: 8),
            receiveTimeout: const Duration(seconds: 8),
          ),
        );

        final data = response.data;
        final apiOk = response.statusCode == 200 &&
            (data is! Map || data['ok'] == true || data['ok']?.toString() == 'true');

        rows.add(
          _PxyDiagRow(
            title: 'Сервер PXY',
            ok: apiOk,
            details: apiOk ? 'Сервер отвечает' : 'Сервер ответил, но статус не подтверждён',
          ),
        );
      } catch (e) {
        rows.add(
          _PxyDiagRow(
            title: 'Сервер PXY',
            ok: false,
            details: 'Не удалось получить ответ от API',
          ),
        );
      }
    }

    final activeProfile = ref.read(activeProfileProvider).valueOrNull;
    rows.add(
      _PxyDiagRow(
        title: 'VPN-профиль',
        ok: activeProfile != null,
        details: activeProfile != null ? 'Профиль выбран и готов к подключению' : 'Профиль не выбран',
      ),
    );

    final connectionStatus = ref.read(connectionNotifierProvider).valueOrNull;
    final isConnected = connectionStatus?.isConnected ?? false;

    rows.add(
      _PxyDiagRow(
        title: 'Состояние VPN',
        ok: isConnected,
        details: isConnected
            ? 'PXY подключён'
            : 'PXY сейчас не подключён. Нажмите кнопку подключения и повторите проверку.',
      ),
    );

    try {
      final ipResponse = await Dio().get<String>(
        'https://api.ipify.org',
        options: Options(
          sendTimeout: const Duration(seconds: 8),
          receiveTimeout: const Duration(seconds: 8),
          responseType: ResponseType.plain,
        ),
      );

      final ip = ipResponse.data?.trim() ?? '';

      rows.add(
        _PxyDiagRow(
          title: 'Внешний IP',
          ok: ip.isNotEmpty,
          details: ip.isNotEmpty ? ip : 'Не удалось определить IP',
        ),
      );
    } catch (_) {
      rows.add(
        const _PxyDiagRow(
          title: 'Внешний IP',
          ok: false,
          details: 'Не удалось проверить внешний IP',
        ),
      );
    }

    rows.add(
      const _PxyDiagRow(
        title: 'Поддержка',
        ok: true,
        details: '@MarketSellerVPN_help_bot',
      ),
    );

    final hasError = rows.any((row) => !row.ok);

    setState(() {
      _loading = false;
      _rows = rows;
      _message = hasError
          ? 'Обнаружена проблема. Если PXY не подключён — подключитесь и повторите проверку. Если ошибка осталась, отправьте отчёт в поддержку.'
          : 'Проверка прошла успешно. PXY подключён, профиль выбран, сервер отвечает.';
    });
  }

  Future<void> _copyReport() async {
    final buffer = StringBuffer()
      ..writeln('PXY diagnostics')
      ..writeln('Time: ${DateTime.now().toIso8601String()}')
      ..writeln('API: ${_accountApiUrl.isEmpty ? "not configured" : _accountApiUrl}')
      ..writeln();

    for (final row in _rows) {
      buffer.writeln('${row.ok ? "OK" : "FAIL"}: ${row.title}');
      buffer.writeln(row.details);
      buffer.writeln();
    }

    await Clipboard.setData(ClipboardData(text: buffer.toString()));

    if (!mounted) return;
    setState(() {
      _message = 'Отчёт скопирован. Его можно отправить в поддержку.';
    });
  }

  Future<void> _openSupport() async {
    final uri = Uri.parse(_supportUrl);
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);

    if (!opened && mounted) {
      setState(() {
        _message = 'Не удалось открыть поддержку. Напишите: @MarketSellerVPN_help_bot';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      color: theme.colorScheme.surface,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.health_and_safety_rounded, color: theme.colorScheme.primary),
                const Gap(8),
                Text(
                  'Диагностика',
                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                ),
              ],
            ),
            const Gap(8),
            Text(
              'Проверьте базовые причины проблем с подключением перед обращением в поддержку.',
              style: theme.textTheme.bodyMedium,
            ),
            const Gap(12),
            FilledButton.icon(
              onPressed: _loading ? null : _runDiagnostics,
              icon: _loading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.search_rounded),
              label: Text(_loading ? 'Проверяем...' : 'Проверить подключение'),
            ),
            if (_rows.isNotEmpty) ...[
              const Gap(12),
              ..._rows.map((row) => _DiagListTile(row: row)),
              const Gap(8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: _copyReport,
                    icon: const Icon(Icons.copy_rounded),
                    label: const Text('Скопировать отчёт'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _openSupport,
                    icon: const Icon(Icons.support_agent_rounded),
                    label: const Text('Поддержка'),
                  ),
                ],
              ),
            ],
            if (_message != null) ...[
              const Gap(10),
              Text(
                _message!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _DiagListTile extends StatelessWidget {
  const _DiagListTile({required this.row});

  final _PxyDiagRow row;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        row.ok ? Icons.check_circle_rounded : Icons.error_rounded,
        color: row.ok ? theme.colorScheme.primary : theme.colorScheme.error,
      ),
      title: Text(row.title),
      subtitle: Text(row.details),
    );
  }
}

class _PxyDiagRow {
  const _PxyDiagRow({
    required this.title,
    required this.ok,
    required this.details,
  });

  final String title;
  final bool ok;
  final String details;
}
