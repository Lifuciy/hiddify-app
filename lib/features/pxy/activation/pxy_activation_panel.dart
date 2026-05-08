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

      ref.invalidate(activeProfileProvider);

      setState(() {
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final activeProfile = ref.watch(activeProfileProvider).valueOrNull;
    final isConfigured = _activationUrl.trim().isNotEmpty;

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
                    activeProfile == null ? Icons.vpn_key_rounded : Icons.verified_rounded,
                    color: theme.colorScheme.primary,
                  ),
                  const Gap(8),
                  Text(
                    activeProfile == null ? 'Активация PXY' : 'PXY активирован',
                    style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ],
              ),
              const Gap(8),
              Text(
                activeProfile == null
                    ? 'Введите код активации, чтобы получить ваш VLESS+Reality профиль.'
                    : 'Активный профиль уже выбран. Можно подключаться.',
                style: theme.textTheme.bodyMedium,
              ),
              if (!isConfigured) ...[
                const Gap(8),
                Text(
                  'API URL не задан в сборке.',
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error),
                ),
              ],
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
                label: Text(_loading ? 'Активация...' : 'Активировать PXY'),
              ),
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
