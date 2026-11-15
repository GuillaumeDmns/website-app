import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../app/theme.dart';
import '../../core/platform/browser_stub.dart' if (dart.library.js_interop) '../../core/platform/browser_web.dart' as browser;
import '../../core/widgets/ui.dart';
import '../../l10n/l10n.dart';
import 'remote_config.dart';

const _channel = MethodChannel('com.guillaumedamiens.live_notification/bridge');

/// Shown instead of the app when the backend no longer supports its version ([updateRequiredProvider]): what to do,
/// and the way there where the app has one (the store's page on Android, a reload on the web)
class UpdateRequiredScreen extends StatelessWidget {
  const UpdateRequiredScreen({super.key});

  static bool get _android => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  Future<void> _update() async {
    if (kIsWeb) {
      browser.reload();
      return;
    }
    try {
      await _channel.invokeMethod<void>('openStore');
    } catch (e) {
      debugPrint('Store not opened: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.system_update_outlined, size: 48, color: theme.colorScheme.primary),
                  const SizedBox(height: 16),
                  Text(l10n.updateRequiredTitle, style: theme.textTheme.headlineSmall, textAlign: TextAlign.center),
                  const SizedBox(height: 8),
                  Text(
                    kIsWeb
                        ? l10n.updateRequiredWeb
                        : _android
                            ? l10n.updateRequiredStore
                            : l10n.updateRequiredOther,
                    style: TextStyle(color: context.colors.muted),
                    textAlign: TextAlign.center,
                  ),
                  if (kIsWeb || _android) ...[
                    const SizedBox(height: 24),
                    FilledButton(onPressed: _update, child: Text(kIsWeb ? l10n.updateRequiredReload : l10n.updateRequiredAction)),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The backend's message for everyone (strike, major outage, maintenance), on the home page; nothing without one
class RemoteNotice extends ConsumerWidget {
  const RemoteNotice({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = ref.watch(remoteNoticeProvider);
    if (text == null) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: AppCard(
        padding: const EdgeInsets.all(12),
        child: NoticeLine(icon: Icons.campaign_outlined, text: text),
      ),
    );
  }
}
