import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import 'pxy_api.dart';
import 'device_id.dart';

import 'package:hiddify/features/profile/notifier/profile_notifier.dart';

class PxyActivationModal extends ConsumerStatefulWidget {
  const PxyActivationModal({super.key});

  static Future<void> show(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => const PxyActivationModal(),
    );
  }

  @override
  ConsumerState<PxyActivationModal> createState() => _PxyActivationModalState();
}

class _PxyActivationModalState extends ConsumerState<PxyActivationModal> {
  final _ctrl = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _activate() async {
    final code = _ctrl.text.trim();
    if (code.isEmpty) return;

    setState(() => _busy = true);
    try {
      final deviceId = await DeviceId.getOrCreate();
      final r = await PxyApi.activate(code: code, deviceId: deviceId);
      final vless = (r['vless'] ?? '') as String;
      if (vless.isEmpty) throw Exception('No vless from API');

      await ref.read(addProfileNotifierProvider.notifier).addClipboard(vless);

      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('PXY активирован ✅')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('Активировать PXY', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
          const SizedBox(height: 12),
          TextField(
            controller: _ctrl,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _activate(),
            decoration: const InputDecoration(
              labelText: 'Код активации',
              hintText: 'PXY-xxxxxxxxxxxxxxxx',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _busy ? null : _activate,
              child: Text(_busy ? '...' : 'Активировать'),
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
