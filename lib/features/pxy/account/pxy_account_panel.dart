import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:hiddify/features/profile/notifier/active_profile_notifier.dart';
import 'package:hiddify/features/profile/notifier/profile_notifier.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:uuid/uuid.dart';

final pxyAccountReadyProvider = StateProvider<bool>((ref) => false);

class PxyAccountPanel extends ConsumerStatefulWidget {
  const PxyAccountPanel({super.key});

  @override
  ConsumerState<PxyAccountPanel> createState() => _PxyAccountPanelState();
}

class _PxyAccountPanelState extends ConsumerState<PxyAccountPanel> {
  static const _accountApiUrl = String.fromEnvironment('PXY_ACCOUNT_API_URL', defaultValue: '');
  static const _activationUrl = String.fromEnvironment('PXY_ACTIVATION_URL', defaultValue: '');

  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _telegramCodeController = TextEditingController();

  bool _loading = false;
  String? _message;
  String? _error;

  String? _accessToken;
  String? _refreshToken;
  Map<String, dynamic>? _user;
  Map<String, dynamic>? _subscription;
  int? _vpnSessionId;
  int? _profileVersion;
  Timer? _heartbeatTimer;
  String? _shareLink;

  @override
  void initState() {
    super.initState();
    _loadStoredAccount();
  }

  @override
  void dispose() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    _emailController.dispose();
    _passwordController.dispose();
    _telegramCodeController.dispose();
    super.dispose();
  }

  String _apiBaseUrl() {
    final accountUrl = _accountApiUrl.trim();
    if (accountUrl.isNotEmpty) {
      return accountUrl.replaceFirst(RegExp(r'/$'), '');
    }

    final activationUrl = _activationUrl.trim();
    if (activationUrl.endsWith('/v1/activate')) {
      return activationUrl.replaceFirst(RegExp(r'/v1/activate$'), '');
    }

    if (activationUrl.endsWith('/activate')) {
      return activationUrl.replaceFirst(RegExp(r'/activate$'), '');
    }

    return activationUrl.replaceFirst(RegExp(r'/$'), '');
  }

  Dio _dio() {
    final baseUrl = _apiBaseUrl();
    if (baseUrl.isEmpty) {
      throw Exception(
        'PXY API URL не задан. Собери приложение с --dart-define=PXY_ACCOUNT_API_URL=https://api.marakastaraka.ru',
      );
    }

    return Dio(
      BaseOptions(
        baseUrl: baseUrl,
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 30),
        sendTimeout: const Duration(seconds: 15),
      ),
    );
  }

  Future<String> _deviceUuid() async {
    final prefs = await SharedPreferences.getInstance();
    var deviceId = prefs.getString('pxy_device_id');
    if (deviceId == null || deviceId.isEmpty) {
      deviceId = const Uuid().v4();
      await prefs.setString('pxy_device_id', deviceId);
    }
    return deviceId;
  }

  bool get _isSubscriptionActive {
    final status = _subscription?['status']?.toString().toLowerCase();
    return status == 'active' || status == 'trial';
  }

  bool get _isAccountReadyForVpn {
    return _accessToken != null &&
        _accessToken!.isNotEmpty &&
        _isSubscriptionActive &&
        _vpnSessionId != null &&
        _shareLink != null &&
        _shareLink!.isNotEmpty;
  }

  void _syncReadyGate() {
    if (!mounted) return;
    ref.read(pxyAccountReadyProvider.notifier).state = _isAccountReadyForVpn;
    _restartHeartbeatTimer();
  }

  bool _accessTokenNeedsRefresh() {
    final token = _accessToken;

    if (token == null || token.isEmpty) return true;

    try {
      final parts = token.split('.');
      if (parts.length != 3) return true;

      final payloadJson = utf8.decode(base64Url.decode(base64Url.normalize(parts[1])));
      final payload = jsonDecode(payloadJson);

      if (payload is! Map) return true;

      final exp = payload['exp'];
      if (exp is! int) return true;

      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;

      return exp <= now + 90;
    } catch (_) {
      return true;
    }
  }

  Future<bool> _refreshAccessToken({bool silent = true}) async {
    final refreshToken = _refreshToken;

    if (refreshToken == null || refreshToken.isEmpty) {
      return false;
    }

    if (_accountApiUrl.isEmpty) {
      return false;
    }

    try {
      final response = await Dio(BaseOptions(baseUrl: _accountApiUrl)).post<dynamic>(
        '/v1/auth/refresh',
        data: {
          'refresh_token': refreshToken,
        },
      );

      final data = _asMap(response.data);
      final tokens = data['tokens'];

      if (tokens is! Map || tokens['access_token'] is! String) {
        return false;
      }

      final prefs = await SharedPreferences.getInstance();

      final newAccessToken = tokens['access_token'] as String;
      _accessToken = newAccessToken;
      await prefs.setString('pxy_v2_access_token', newAccessToken);

      if (tokens['refresh_token'] is String) {
        final newRefreshToken = tokens['refresh_token'] as String;
        _refreshToken = newRefreshToken;
        await prefs.setString('pxy_v2_refresh_token', newRefreshToken);
      }

      if (data['user'] is Map) {
        _user = Map<String, dynamic>.from(data['user'] as Map);
        await prefs.setString('pxy_v2_user_json', jsonEncode(_user));
      }

      if (data['subscription'] is Map) {
        _subscription = Map<String, dynamic>.from(data['subscription'] as Map);
        await prefs.setString('pxy_v2_subscription_json', jsonEncode(_subscription));
      }

      if (mounted) {
        setState(() {
          if (!silent) _message = 'Сессия обновлена.';
          _error = null;
        });
      }

      _syncReadyGate();
      return true;
    } catch (_) {
      return false;
    }
  }

  void _restartHeartbeatTimer() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;

    if (!_isAccountReadyForVpn || _vpnSessionId == null) {
      return;
    }

    _heartbeatTimer = Timer.periodic(const Duration(minutes: 5), (_) {
      unawaited(_sendHeartbeat(silent: true));
    });
  }

  Future<void> _handleRevokedVpnSession() async {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('pxy_v2_vpn_session_id');
    await prefs.remove('pxy_v2_profile_version');

    if (!mounted) return;

    setState(() {
      _vpnSessionId = null;
      _profileVersion = null;
      _error = 'Подписка активирована на другом устройстве. Чтобы использовать PXY здесь, нажмите “Восстановить профиль”.';
      _message = null;
    });

    _syncReadyGate();
  }

  Future<void> _sendHeartbeat({bool silent = true}) async {
    final sessionId = _vpnSessionId;

    if (sessionId == null) {
      return;
    }

    try {
      final response = await _authorizedPost(
        '/v1/vpn/session/heartbeat',
        <String, dynamic>{
          'vpn_session_id': sessionId,
          'profile_version': _profileVersion ?? 1,
        },
      );

      final data = _asMap(response.data);
      final sessionStatus = data['session_status']?.toString();

      if (sessionStatus == 'revoked') {
        await _handleRevokedVpnSession();
      }
    } catch (e) {
      if (!silent && mounted) {
        setState(() {
          _error = _formatError(e);
          _message = null;
        });
      }
    }
  }

  Future<void> _ensureLocalVpnProfile({bool silent = true}) async {
    final shareLink = _shareLink;

    if (!_isSubscriptionActive || shareLink == null || shareLink.isEmpty) {
      return;
    }

    final activeProfile = ref.read(activeProfileProvider).valueOrNull;
    if (activeProfile != null) {
      return;
    }

    try {
      await ref.read(addProfileNotifierProvider.notifier).addClipboard(_pxyDisplayShareLink(shareLink));
      ref.invalidate(profileProvider);
      ref.invalidate(activeProfileProvider);

      if (!silent && mounted) {
        setState(() {
          _message = 'VPN-профиль восстановлен. Можно подключаться.';
          _error = null;
        });
      }
    } catch (e) {
      if (!silent && mounted) {
        setState(() {
          _error = 'Не удалось восстановить VPN-профиль: ${_formatError(e)}';
          _message = null;
        });
      }
    }
  }

  Future<void> _loadStoredAccount() async {
    final prefs = await SharedPreferences.getInstance();

    final accessToken = prefs.getString('pxy_v2_access_token');
    final refreshToken = prefs.getString('pxy_v2_refresh_token');
    final userRaw = prefs.getString('pxy_v2_user_json');
    final subscriptionRaw = prefs.getString('pxy_v2_subscription_json');
    final vpnSessionId = prefs.getInt('pxy_v2_vpn_session_id');
    final profileVersion = prefs.getInt('pxy_v2_profile_version');
    final shareLink = prefs.getString('pxy_v2_share_link');

    Map<String, dynamic>? user;
    Map<String, dynamic>? subscription;

    try {
      if (userRaw != null && userRaw.isNotEmpty) {
        final decoded = jsonDecode(userRaw);
        if (decoded is Map) user = Map<String, dynamic>.from(decoded);
      }

      if (subscriptionRaw != null && subscriptionRaw.isNotEmpty) {
        final decoded = jsonDecode(subscriptionRaw);
        if (decoded is Map) subscription = Map<String, dynamic>.from(decoded);
      }
    } catch (_) {
      await prefs.remove('pxy_v2_user_json');
      await prefs.remove('pxy_v2_subscription_json');
    }

    if (!mounted) return;

    setState(() {
      _accessToken = accessToken;
      _refreshToken = refreshToken;
      _user = user;
      _subscription = subscription;
      _vpnSessionId = vpnSessionId;
      _profileVersion = profileVersion;
      _shareLink = shareLink;
    });
    _syncReadyGate();
    await _ensureLocalVpnProfile(silent: true);

    if (accessToken != null && accessToken.isNotEmpty) {
      await _refreshAccount(silent: true);
    }
  }

  Future<void> _saveAuth(Map<String, dynamic> data) async {
    final prefs = await SharedPreferences.getInstance();

    final user = data['user'];
    if (user is Map) {
      await prefs.setString('pxy_v2_user_json', jsonEncode(user));
      _user = Map<String, dynamic>.from(user);
    }

    final subscription = data['subscription'];
    if (subscription is Map) {
      await prefs.setString('pxy_v2_subscription_json', jsonEncode(subscription));
      _subscription = Map<String, dynamic>.from(subscription);
    } else {
      await prefs.remove('pxy_v2_subscription_json');
      _subscription = null;
    }

    final tokens = data['tokens'];
    if (tokens is Map && tokens['access_token'] is String) {
      _accessToken = tokens['access_token'] as String;
      await prefs.setString('pxy_v2_access_token', _accessToken!);

      if (tokens['refresh_token'] is String) {
        _refreshToken = tokens['refresh_token'] as String;
        await prefs.setString('pxy_v2_refresh_token', _refreshToken!);
      }
    }
  }

  Future<void> _register() async {
    await _auth(register: true);
  }

  Future<void> _login() async {
    await _auth(register: false);
  }

  Future<void> _auth({required bool register}) async {
    if (_loading) return;

    setState(() {
      _loading = true;
      _message = null;
      _error = null;
    });

    try {
      final email = _emailController.text.trim();
      final password = _passwordController.text;

      if (email.isEmpty) throw Exception('Введите email');
      if (password.isEmpty) throw Exception('Введите пароль');

      final deviceId = await _deviceUuid();

      final response = await _dio().post(
        register ? '/v1/auth/register' : '/v1/auth/login',
        data: <String, dynamic>{
          'email': email,
          'password': password,
          'display_name': email.split('@').first,
          'device': <String, dynamic>{
            'device_uuid': deviceId,
            'device_name': 'PXY ${defaultTargetPlatform.name}',
            'platform': defaultTargetPlatform.name,
            'app_version': '0.0.1',
            'os_version': defaultTargetPlatform.name,
          },
        },
      );

      final data = _asMap(response.data);
      await _saveAuth(data);

      if (!mounted) return;
      setState(() {
        _message = register ? 'Аккаунт создан.' : 'Вход выполнен.';
        _error = null;
      });

      await _refreshAccount(silent: true);
    } catch (error) {
      if (!mounted) return;
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

  Future<Response<dynamic>> _authorizedGet(String path) async {
    if (_accessTokenNeedsRefresh()) {
      await _refreshAccessToken(silent: true);
    }

    var token = _accessToken;
    if (token == null || token.isEmpty) {
      throw Exception('Требуется вход в аккаунт.');
    }

    final deviceId = await _deviceUuid();

    try {
      return await Dio(BaseOptions(baseUrl: _accountApiUrl)).get<dynamic>(
        path,
        options: Options(
          headers: {
            'Authorization': 'Bearer $token',
            'X-Device-ID': deviceId,
          },
        ),
      );
    } on DioException catch (e) {
      if (e.response?.statusCode == 401 && await _refreshAccessToken(silent: true)) {
        token = _accessToken;
        if (token != null && token.isNotEmpty) {
          return await Dio(BaseOptions(baseUrl: _accountApiUrl)).get<dynamic>(
            path,
            options: Options(
              headers: {
                'Authorization': 'Bearer $token',
                'X-Device-ID': deviceId,
              },
            ),
          );
        }
      }
      rethrow;
    }
  }

  Future<Response<dynamic>> _authorizedPost(String path, Map<String, dynamic> data) async {
    if (_accessTokenNeedsRefresh()) {
      await _refreshAccessToken(silent: true);
    }

    var token = _accessToken;
    if (token == null || token.isEmpty) {
      throw Exception('Требуется вход в аккаунт.');
    }

    final deviceId = await _deviceUuid();

    try {
      return await Dio(BaseOptions(baseUrl: _accountApiUrl)).post<dynamic>(
        path,
        data: data,
        options: Options(
          headers: {
            'Authorization': 'Bearer $token',
            'X-Device-ID': deviceId,
          },
        ),
      );
    } on DioException catch (e) {
      if (e.response?.statusCode == 401 && await _refreshAccessToken(silent: true)) {
        token = _accessToken;
        if (token != null && token.isNotEmpty) {
          return await Dio(BaseOptions(baseUrl: _accountApiUrl)).post<dynamic>(
            path,
            data: data,
            options: Options(
              headers: {
                'Authorization': 'Bearer $token',
                'X-Device-ID': deviceId,
              },
            ),
          );
        }
      }
      rethrow;
    }
  }

  Future<void> _refreshAccount({bool silent = false}) async {
    if (_accessTokenNeedsRefresh()) {
      await _refreshAccessToken(silent: true);
    }

    final token = _accessToken;
    if (token == null || token.isEmpty) return;

    if (!silent && mounted) {
      setState(() {
        _loading = true;
        _message = null;
        _error = null;
      });
    }

    try {
      final response = await _authorizedGet('/v1/account/me');

      final data = _asMap(response.data);
      final prefs = await SharedPreferences.getInstance();

      final user = data['user'];
      if (user is Map) {
        _user = Map<String, dynamic>.from(user);
        await prefs.setString('pxy_v2_user_json', jsonEncode(_user));
      }

      final subscription = data['subscription'];
      if (subscription is Map) {
        _subscription = Map<String, dynamic>.from(subscription);
        await prefs.setString('pxy_v2_subscription_json', jsonEncode(_subscription));
      } else {
        _subscription = null;
        await prefs.remove('pxy_v2_subscription_json');
      }

      if (!mounted) return;
      setState(() {
        if (!silent) _message = 'Данные аккаунта обновлены.';
        _error = null;
      });
      _syncReadyGate();
      await _ensureLocalVpnProfile(silent: true);

      if (_isSubscriptionActive && !_isAccountReadyForVpn) {
        await _startVpnSession();
      }
    } catch (error) {
      if (!silent && mounted) {
        setState(() {
          _error = _formatError(error);
        });
      }
    } finally {
      if (!silent && mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  Future<void> _linkTelegramCode() async {
    if (_accessTokenNeedsRefresh()) {
      await _refreshAccessToken(silent: true);
    }

    final token = _accessToken;
    if (token == null || token.isEmpty) {
      setState(() {
        _error = 'Сначала войдите в аккаунт.';
      });
      return;
    }

    final code = _telegramCodeController.text.trim();
    if (code.isEmpty) {
      setState(() {
        _error = 'Введите код привязки из Telegram.';
      });
      return;
    }

    setState(() {
      _loading = true;
      _message = null;
      _error = null;
    });

    try {
      final response = await _authorizedPost(
        '/v1/account/link-telegram-code',
        <String, dynamic>{
          'link_code': code,
        },
      );

      final data = _asMap(response.data);
      final subscription = data['subscription'];

      if (subscription is Map) {
        _subscription = Map<String, dynamic>.from(subscription);
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('pxy_v2_subscription_json', jsonEncode(_subscription));
      }

      if (!mounted) return;
      setState(() {
        _telegramCodeController.clear();
        _message = 'Покупка из Telegram привязана к аккаунту.';
        _error = null;
      });
      _syncReadyGate();

      if (_isSubscriptionActive && !_isAccountReadyForVpn) {
        await _startVpnSession();
      }
    } catch (error) {
      if (!mounted) return;
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

  String _pxyDisplayShareLink(String shareLink) {
    final displayName = Uri.encodeComponent('Автоматический сервер');
    final hashIndex = shareLink.indexOf('#');

    if (hashIndex < 0) {
      return '$shareLink#$displayName';
    }

    return '${shareLink.substring(0, hashIndex)}#$displayName';
  }

  Future<void> _startVpnSession() async {
    if (_accessTokenNeedsRefresh()) {
      await _refreshAccessToken(silent: true);
    }

    final token = _accessToken;
    if (token == null || token.isEmpty) {
      setState(() {
        _error = 'Сначала войдите в аккаунт.';
      });
      return;
    }

    setState(() {
      _loading = true;
      _message = null;
      _error = null;
    });

    try {
      final response = await _authorizedPost(
        '/v1/vpn/session/start',
        <String, dynamic>{
          'platform': defaultTargetPlatform.name,
          'app_version': '0.0.1',
          'connection_mode': 'system_proxy',
        },
      );

      final data = _asMap(response.data);
      final profile = data['profile'];
      if (profile is! Map) throw Exception('В ответе API нет VPN-профиля');

      final shareLink = profile['share_link'];
      if (shareLink is! String || !shareLink.startsWith('vless://')) {
        throw Exception('В ответе API не найден vless:// профиль');
      }

      final profileVersionRaw = profile['profile_version'];
      final profileVersion = profileVersionRaw is int ? profileVersionRaw : int.tryParse('$profileVersionRaw');

      final activeProfile = ref.read(activeProfileProvider).valueOrNull;
      final shouldImportProfile = activeProfile == null || _shareLink != shareLink;

      if (shouldImportProfile) {
        await ref.read(addProfileNotifierProvider.notifier).addClipboard(_pxyDisplayShareLink(shareLink));

        final importState = ref.read(addProfileNotifierProvider);
        if (importState.hasError) {
          throw importState.error ?? Exception('Не удалось импортировать профиль');
        }

        ref.invalidate(activeProfileProvider);
      }

      final vpnSession = data['vpn_session'];
      final subscription = data['subscription'];

      final prefs = await SharedPreferences.getInstance();

      if (vpnSession is Map && vpnSession['id'] is int) {
        _vpnSessionId = vpnSession['id'] as int;
        await prefs.setInt('pxy_v2_vpn_session_id', _vpnSessionId!);
      }

      if (profileVersion != null) {
        _profileVersion = profileVersion;
        await prefs.setInt('pxy_v2_profile_version', profileVersion);
      }

      _shareLink = shareLink;
      await prefs.setString('pxy_v2_share_link', shareLink);

      if (subscription is Map) {
        _subscription = Map<String, dynamic>.from(subscription);
        await prefs.setString('pxy_v2_subscription_json', jsonEncode(_subscription));
      }

      if (!mounted) return;
      setState(() {
        _message = shouldImportProfile
            ? 'VPN-профиль получен и добавлен. Можно подключаться.'
            : 'VPN-сессия активирована. Можно подключаться.';
        _error = null;
      });
      _syncReadyGate();
    } catch (error) {
      if (!mounted) return;
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

  Future<void> _repairVpnProfile() async {
    if (_accessToken == null || _accessToken!.isEmpty) {
      setState(() {
        _error = 'Сначала войдите в аккаунт.';
        _message = null;
      });
      return;
    }

    setState(() {
      _loading = true;
      _message = null;
      _error = null;
    });

    try {
      await _refreshAccount(silent: true);

      if (!_isSubscriptionActive) {
        throw Exception('Подписка не активна.');
      }

      if (_vpnSessionId == null || _shareLink == null || _shareLink!.isEmpty) {
        await _startVpnSession();
      } else {
        await _ensureLocalVpnProfile(silent: false);
      }

      if (!mounted) return;
      setState(() {
        _message = 'Профиль PXY восстановлен. Можно подключаться.';
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Не удалось восстановить профиль: ${_formatError(e)}';
        _message = null;
      });
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  Future<void> _logout() async {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;

    final prefs = await SharedPreferences.getInstance();

    await prefs.remove('pxy_v2_access_token');
    await prefs.remove('pxy_v2_refresh_token');
    await prefs.remove('pxy_v2_user_json');
    await prefs.remove('pxy_v2_subscription_json');
    await prefs.remove('pxy_v2_vpn_session_id');
    await prefs.remove('pxy_v2_profile_version');
    await prefs.remove('pxy_v2_share_link');

    if (!mounted) return;
    setState(() {
      _accessToken = null;
      _refreshToken = null;
      _user = null;
      _subscription = null;
      _vpnSessionId = null;
      _profileVersion = null;
      _shareLink = null;
      _message = 'Вы вышли из аккаунта.';
      _error = null;
    });
    _syncReadyGate();
  }

  Map<String, dynamic> _asMap(dynamic data) {
    if (data is String) {
      final decoded = jsonDecode(data);
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    }

    if (data is Map) return Map<String, dynamic>.from(data);

    throw Exception('Некорректный ответ API');
  }

  String _formatError(Object error) {
    if (error is DioException) {
      final data = error.response?.data;
      if (data is Map) {
        final detail = data['detail'];
        if (detail is Map && detail['message'] != null) {
          return detail['message'].toString();
        }
        if (data['message'] != null) return data['message'].toString();
      }
      return error.message ?? error.toString();
    }

    return error.toString().replaceFirst('Exception: ', '');
  }

  Future<void> _openSupport() async {
    final uri = Uri.parse('https://t.me/MarketSellerVPN_help_bot');
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);

    if (!opened && mounted) {
      setState(() {
        _error = 'Не удалось открыть поддержку. Напишите: @MarketSellerVPN_help_bot';
      });
    }
  }

  String _planTitle(String planCode) {
    switch (planCode) {
      case 'week_1':
        return 'Подписка на 7 дней';
      case 'month_1':
        return 'Подписка на 30 дней';
      case 'month_3':
        return 'Подписка на 90 дней';
      case 'test_unlimited':
        return 'Тестовый доступ';
      default:
        return 'Подписка';
    }
  }

  String _statusTitle(String status) {
    switch (status) {
      case 'active':
        return 'активна';
      case 'trial':
        return 'активна';
      case 'expired':
        return 'закончилась';
      case 'cancelled':
        return 'отменена';
      default:
        return 'неактивна';
    }
  }

  String _subscriptionText() {
    final sub = _subscription;
    if (sub == null) return 'Подписка не найдена';

    final status = sub['status']?.toString().toLowerCase() ?? '';
    final planCode = sub['plan_code']?.toString() ?? '';
    final expiresAt = sub['expires_at']?.toString() ?? '—';

    final planTitle = _planTitle(planCode);
    final statusTitle = _statusTitle(status);

    if (status == 'active' || status == 'trial') {
      if (planCode == 'test_unlimited') {
        return 'Тестовый доступ активен\nДействует до: $expiresAt';
      }
      return '$planTitle $statusTitle\nДействует до: $expiresAt';
    }

    if (status == 'expired') {
      return '$planTitle закончилась\nПродлите доступ, чтобы подключиться';
    }

    return '$planTitle $statusTitle\nДействует до: $expiresAt';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final loggedIn = _accessToken != null && _accessToken!.isNotEmpty;

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
                  Icon(Icons.account_circle_rounded, color: theme.colorScheme.primary),
                  const Gap(8),
                  Text(
                    loggedIn ? 'Аккаунт PXY' : 'Вход в PXY',
                    style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ],
              ),
              const Gap(8),
              if (!loggedIn) ...[
                Text(
                  'Войдите или создайте аккаунт. Если покупали в Telegram — после входа введите код привязки.',
                  style: theme.textTheme.bodyMedium,
                ),
                const Gap(12),
              ],
              if (!loggedIn) ...[
                TextField(
                  controller: _emailController,
                  enabled: !_loading,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    labelText: 'Email',
                    border: OutlineInputBorder(),
                  ),
                ),
                const Gap(8),
                TextField(
                  controller: _passwordController,
                  enabled: !_loading,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Пароль',
                    border: OutlineInputBorder(),
                  ),
                ),
                const Gap(12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilledButton.icon(
                      onPressed: _loading ? null : _login,
                      icon: const Icon(Icons.login_rounded),
                      label: const Text('Войти'),
                    ),
                    OutlinedButton.icon(
                      onPressed: _loading ? null : _register,
                      icon: const Icon(Icons.person_add_alt_1_rounded),
                      label: const Text('Создать аккаунт'),
                    ),
                  ],
                ),
              ] else ...[
                Text(
                  _user?['email']?.toString() ?? 'Аккаунт активен',
                  style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
                ),
                const Gap(8),
                Container(
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: theme.colorScheme.outlineVariant),
                  ),
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    _subscriptionText(),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: _isSubscriptionActive ? theme.colorScheme.primary : theme.colorScheme.error,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (!_isSubscriptionActive) ...[
                  const Gap(12),
                  TextField(
                    controller: _telegramCodeController,
                    enabled: !_loading,
                    decoration: const InputDecoration(
                      labelText: 'Код из Telegram',
                      hintText: 'Например: ABCD-1234',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const Gap(12),
                ],
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (!_isSubscriptionActive)
                      OutlinedButton.icon(
                        onPressed: _loading ? null : _linkTelegramCode,
                        icon: const Icon(Icons.link_rounded),
                        label: const Text('Привязать Telegram-покупку'),
                      ),
                    OutlinedButton.icon(
                      onPressed: _loading ? null : () => _refreshAccount(silent: false),
                      icon: const Icon(Icons.refresh_rounded),
                      label: const Text('Обновить'),
                    ),
                    if (_isSubscriptionActive)
                      OutlinedButton.icon(
                        onPressed: _loading ? null : _repairVpnProfile,
                        icon: const Icon(Icons.build_circle_rounded),
                        label: const Text('Восстановить профиль'),
                      ),
                    OutlinedButton.icon(
                      onPressed: _loading ? null : _openSupport,
                      icon: const Icon(Icons.support_agent_rounded),
                      label: const Text('Поддержка'),
                    ),
                    TextButton.icon(
                      onPressed: _loading ? null : _logout,
                      icon: const Icon(Icons.logout_rounded),
                      label: const Text('Сменить аккаунт'),
                    ),
                  ],
                ),
              ],
              if (_loading) ...[
                const Gap(12),
                const LinearProgressIndicator(),
              ],
              if (_message != null) ...[
                const Gap(12),
                Text(
                  _message!,
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.primary),
                ),
              ],
              if (_error != null) ...[
                const Gap(12),
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
