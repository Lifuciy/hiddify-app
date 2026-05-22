import 'package:dartx/dartx.dart';
import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:hiddify/core/app_info/app_info_provider.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/features/home/widget/connection_button.dart';
import 'package:hiddify/features/pxy/account/pxy_account_panel.dart';
import 'package:hiddify/features/pxy/connection/pxy_connection_mode_panel.dart';
import 'package:hiddify/features/pxy/diagnostics/pxy_diagnostics_panel.dart';
import 'package:hiddify/features/pxy/traffic/pxy_traffic_rules_panel.dart';
import 'package:hiddify/features/proxy/active/active_proxy_delay_indicator.dart';
import 'package:hiddify/gen/assets.gen.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:sliver_tools/sliver_tools.dart';

class HomePage extends HookConsumerWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pxyAccountReady = ref.watch(pxyAccountReadyProvider);
    final theme = Theme.of(context);
    final t = ref.watch(translationsProvider).requireValue;
    // final hasAnyProfile = ref.watch(hasAnyProfileProvider);

    return Scaffold(
      appBar: AppBar(
        // leading: (RootScaffold.stateKey.currentState?.hasDrawer ?? false) && showDrawerButton(context)
        //     ? DrawerButton(
        //         onPressed: () {
        //           RootScaffold.stateKey.currentState?.openDrawer();
        //         },
        //       )
        //     : null,
        title: Row(
          children: [
            Assets.images.logo.svg(height: 24),
            const Gap(8),
            Text.rich(
              TextSpan(
                children: [
                  const TextSpan(text: "PXY"),
                  const TextSpan(text: " "),
                  const WidgetSpan(child: AppVersionLabel(), alignment: PlaceholderAlignment.middle),
                ],
              ),
            ),
          ],
        ),
        actions: const [],
      ),
      body: Container(
        decoration: BoxDecoration(
          image: DecorationImage(
            image: const AssetImage('assets/images/world_map.png'), // Replace with your image path
            fit: BoxFit.cover,
            opacity: 0.09,
            colorFilter: theme.brightness == Brightness.dark
                ? ColorFilter.mode(Colors.white.withValues(alpha: .15), BlendMode.srcIn) //
                : ColorFilter.mode(
                    Colors.grey.withValues(alpha: 1),
                    BlendMode.srcATop,
                  ), // Apply white tint in dark mode
          ),
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: 600, // Set the maximum width here
                ),
                child: CustomScrollView(
                  slivers: [
                    // switch (activeProfile) {
                    // AsyncData(value: final profile?) =>
                    MultiSliver(
                      children: [
                        if (pxyAccountReady)
                          const SliverToBoxAdapter(
                            child: Padding(
                              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  ConnectionButton(),
                                  Gap(8),
                                  ActiveProxyDelayIndicator(),
                                  Gap(8),
                                  PxyConnectionSummary(),
                                ],
                              ),
                            ),
                          ),
                        const SliverToBoxAdapter(
                          child: PxyAccountPanel(),
                        ),
                        if (pxyAccountReady)
                          const SliverToBoxAdapter(
                            child: PxyAdvancedSettingsPanel(),
                          ),
                      ],
                    ),
                    // AsyncData() => switch (hasAnyProfile) {
                    //     AsyncData(value: true) => const EmptyActiveProfileHomeBody(),
                    //     _ => const EmptyProfilesHomeBody(),
                    //   },
                    // AsyncError(:final error) => SliverErrorBodyPlaceholder(t.presentShortError(error)),
                    // _ => const SliverToBoxAdapter(),
                    // },
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}



class PxyConnectionSummary extends StatelessWidget {
  const PxyConnectionSummary({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Card(
        color: theme.colorScheme.surface,
        child: ListTile(
          leading: Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: theme.colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              Icons.shield_rounded,
              color: theme.colorScheme.primary,
            ),
          ),
          title: Text(
            'Автоматический сервер',
            style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          subtitle: const Text('Защищённое подключение PXY'),
          trailing: Icon(
            Icons.check_circle_rounded,
            color: theme.colorScheme.primary,
          ),
        ),
      ),
    );
  }
}


class PxyAdvancedSettingsPanel extends StatelessWidget {
  const PxyAdvancedSettingsPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Card(
        color: theme.colorScheme.surfaceContainer,
        child: ExpansionTile(
          initiallyExpanded: false,
          leading: Icon(Icons.tune_rounded, color: theme.colorScheme.primary),
          title: Text(
            'Расширенные настройки',
            style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          children: const [
            PxyConnectionModePanel(),
            PxyTrafficRulesPanel(),
            PxyDiagnosticsPanel(),
            Gap(8),
          ],
        ),
      ),
    );
  }
}


class AppVersionLabel extends HookConsumerWidget {
  const AppVersionLabel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider).requireValue;
    final theme = Theme.of(context);

    final version = ref.watch(appInfoProvider).requireValue.presentVersion;
    if (version.isBlank) return const SizedBox();

    return Semantics(
      label: t.common.version,
      button: false,
      child: Container(
        decoration: BoxDecoration(color: theme.colorScheme.secondaryContainer, borderRadius: BorderRadius.circular(4)),
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
        child: Text(
          version,
          textDirection: TextDirection.ltr,
          style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSecondaryContainer),
        ),
      ),
    );
  }
}
