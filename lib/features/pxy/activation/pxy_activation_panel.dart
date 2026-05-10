import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:hiddify/features/profile/notifier/active_profile_notifier.dart';
import 'package:hiddify/features/profile/notifier/profile_notifier.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

class PxyActivationPanel extends ConsumerStatefulWidget {
  const PxyActivationPanel({super.key});

  @override
  ConsumerState<PxyActivationPanel> createState() => _PxyActivationPanelState();
}

class _PxyActivationPanelState extends ConsumerState<PxyActivationPanel> {
  static const _activationUrl = String.fromEnvironment('PXY_ACTIVATION_URL', defaultValue: '');

  final _codeController = TextEditingController();

  bool _loading = false;
  String? _message;
  String? _error;
  Map<String, dynamic>? _subscription;
  int? _refreshAfterSec;

  @override
  void initState() {
    super.initState();
    _loadStoredSubscription();
  }

  Future<void> _loadStoredSubscription() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('pxy_subscription_json');
    final refreshAfterSec = prefs.getInt('pxy_refresh_after_sec');

    if (!mounted) return;

    if (raw == null || raw.isEmpty) {
      setState(() {
        _refreshAfterSec = refreshAfterSec;
      });
      return;
    }

    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        setState(() {
          _subscription = Map<String, dynamic>.from(decoded);
          _refreshAfterSec = refreshAfterSec;
        });
      }
    } catch (_) {
      await prefs.remove('pxy_subscription_json');
    }
  }

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _activate() async {
    if (_loading) return;

    setState(() {
      _loading = true;
      _message = null;
      _error = null;
    });

    try {
      if (_activationUrl.trim().isEmpty) {
        throw Exception(
          'PXY_ACTIVATION_URL не задан. Собери приложение с --dart-define=PXY_ACTIVATION_URL=https://.../v1/activate',
        );
      }

      final dio = Dio(
        BaseOptions(
          connectTimeout: const Duration(seconds: 15),
          receiveTimeout: const Duration(seconds: 30),
          sendTimeout: const Duration(seconds: 15),
        ),
      );

      final code = _codeController.text.trim();
      if (code.isEmpty) {
        throw Exception('Введите код активации');
      }

      final prefs = await SharedPreferences.getInstance();
      var deviceId = prefs.getString('pxy_device_id');
      if (deviceId == null || deviceId.isEmpty) {
        deviceId = const Uuid().v4();
        await prefs.setString('pxy_device_id', deviceId);
      }

      final response = await dio.post(
        _activationUrl,
        data: <String, dynamic>{
          'code': code,
          'device_id': deviceId,
          'client': 'PXY Windows',
          'platform': defaultTargetPlatform.name,
        },
      );

      dynamic data = response.data;
      if (data is String) {
        data = jsonDecode(data);
      }

      if (data is! Map) {
        throw Exception('Некорректный ответ API: ожидался JSON-объект');
      }

      if (data['ok'] == false) {
        throw Exception(data['error'] ?? data['message'] ?? 'API вернул ok=false');
      }

      final vless = <dynamic>[data['vless'], data['link'], data['config']]
          .whereType<String>()
          .map((value) => value.trim())
          .firstWhere(
            (value) => value.startsWith('vless://'),
            orElse: () => '',
          );

      if (vless.isEmpty) {
        throw Exception('В ответе API не найден vless:// ключ');
      }

      await ref.read(addProfileNotifierProvider.notifier).addClipboard(vless);

      final importState = ref.read(addProfileNotifierProvider);
      if (importState.hasError) {
        throw importState.error ?? Exception('Не удалось импортировать профиль');
      }

      Map<String, dynamic>? subscription;
      final subscriptionRaw = data['subscription'];
      if (subscriptionRaw is Map) {
        subscription = Map<String, dynamic>.from(subscriptionRaw);
        await prefs.setString('pxy_subscription_json', jsonEncode(subscription));
      }

      final refreshRaw = data['refresh_after_sec'];
      int? refreshAfterSec;
      if (refreshRaw is int) {
        refreshAfterSec = refreshRaw;
        await prefs.setInt('pxy_refresh_after_sec', refreshAfterSec);
      }

      ref.invalidate(activeProfileProvider);

      setState(() {
        _subscription = subscription ?? _subscription;
        _refreshAfterSec = refreshAfterSec ?? _refreshAfterSec;
        _message = 'PXY активирован. Профиль добавлен и выбран активным.';
      });
    } catch (error) {
      setState(() {
        _error = _formatError(error);
      });
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  String _formatError(Object error) {
    if (error is DioException) {
      final responseData = error.response?.data;
      if (responseData != null) return responseData.toString();
      return error.message ?? error.toString();
    }
    return error.toString().replaceFirst('Exception: ', '');
  }

  String _subValue(String key) {
    final value = _subscription?[key];
    if (value == null) return '—';
    return value.toString();
  }

  String _formatExpiresAt() {
    final iso = _subscription?['expires_at_iso'];
    if (iso is String && iso.isNotEmpty) {
      final dt = DateTime.tryParse(iso);
      if (dt != null) {
        final local = dt.toLocal();
        final day = local.day.toString().padLeft(2, '0');
        final month = local.month.toString().padLeft(2, '0');
        final year = local.year.toString();
        final hour = local.hour.toString().padLeft(2, '0');
        final minute = local.minute.toString().padLeft(2, '0');
        return '$day.$month.$year $hour:$minute';
      }
      return iso;
    }

    final expiresMs = _subscription?['expires_at_ms'];
    if (expiresMs is int && expiresMs > 0) {
      final local = DateTime.fromMillisecondsSinceEpoch(expiresMs).toLocal();
      final day = local.day.toString().padLeft(2, '0');
      final month = local.month.toString().padLeft(2, '0');
      final year = local.year.toString();
      final hour = local.hour.toString().padLeft(2, '0');
      final minute = local.minute.toString().padLeft(2, '0');
      return '$day.$month.$year $hour:$minute';
    }

    return '—';
  }

  Widget _subscriptionInfo(BuildContext context) {
    final theme = Theme.of(context);
    final daysLeft = _subValue('days_left');
    final refreshText = _refreshAfterSec == null ? '—' : '${(_refreshAfterSec! / 60).round()} мин.';

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Информация о подписке',
            style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
          const Gap(8),
          _infoRow(context, 'Статус', _subValue('status') == 'active' ? 'Активна' : _subValue('status')),
          _infoRow(context, 'Telegram ID', _subValue('tg_id')),
          _infoRow(context, 'Порт', _subValue('port')),
          _infoRow(context, 'Действует до', _formatExpiresAt()),
          _infoRow(context, 'Осталось дней', daysLeft),
          _infoRow(context, 'Обновление ключа', refreshText),
        ],
      ),
    );
  }

  Widget _infoRow(BuildContext context, String label, String value) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ),
          const Gap(12),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final activeProfile = ref.watch(activeProfileProvider).valueOrNull;
    final isConfigured = _activationUrl.trim().isNotEmpty;
    final needsActivationCode = activeProfile == null || _subscription == null;

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
                  Icon(
                    needsActivationCode ? Icons.vpn_key_rounded : Icons.verified_rounded,
                    color: theme.colorScheme.primary,
                  ),
                  const Gap(8),
                  Text(
                    activeProfile == null
                        ? 'Активация PXY'
                        : (_subscription == null ? 'Обновите данные подписки' : 'PXY активирован'),
                    style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ],
              ),
              const Gap(8),
              Text(
                activeProfile == null
                    ? 'Введите код активации, чтобы получить ваш VLESS+Reality профиль.'
                    : (_subscription == null
                        ? 'Профиль уже активен, но данные подписки ещё не загружены. Введите новый код из Telegram-бота.'
                        : 'Активный профиль выбран. Можно подключаться.'),
                style: theme.textTheme.bodyMedium,
              ),
              if (!isConfigured) ...[
                const Gap(8),
                Text(
                  'API URL не задан в сборке.',
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error),
                ),
              ],
              if (activeProfile != null && _subscription != null) ...[
                const Gap(12),
                _subscriptionInfo(context),
              ],
              if (needsActivationCode) ...[
                const Gap(12),
                TextField(
                  controller: _codeController,
                  enabled: !_loading,
                  decoration: const InputDecoration(
                    labelText: 'Код активации',
                    hintText: 'Например: код из Telegram-бота',
                    border: OutlineInputBorder(),
                  ),
                ),
                const Gap(12),
                FilledButton.icon(
                  onPressed: _loading ? null : _activate,
                  icon: _loading
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.download_done_rounded),
                  label: Text(
                    _loading
                        ? 'Активация...'
                        : (activeProfile == null ? 'Активировать PXY' : 'Обновить данные подписки'),
                  ),
                ),
              ],
              if (_message != null) ...[
                const Gap(8),
                Text(
                  _message!,
                  style: theme.textTheme.bodySmall?.copyWith(color: Colors.green),
                ),
              ],
              if (_error != null) ...[
                const Gap(8),
                Text(
                  _error!,
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
