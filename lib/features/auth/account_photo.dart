import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../app/theme.dart';
import '../../core/storage/local_store.dart';
import 'auth_controller.dart';

const _key = 'account_photo';

/// The address of the profile picture a Google ID token names (its `picture` claim), null without one. The token
/// is only read here, never checked: the backend does that, and a wrong picture would be the only harm.
String? googlePhotoOf(String idToken) {
  try {
    final parts = idToken.split('.');
    if (parts.length != 3) {
      return null;
    }
    final claims = jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))));
    final picture = claims is Map ? claims['picture'] : null;
    return picture is String && Uri.tryParse(picture)?.scheme == 'https' ? picture : null;
  } catch (_) {
    return null;
  }
}

/// The account's Google profile picture: its address, taken from the ID token at sign-in and kept on the device only
/// (the backend never gets it); the picture itself comes from Google's servers. None after a sign-in through the
/// browser (Linux, Windows: the app gets no ID token there), nor for a guest.
class AccountPhotoController extends Notifier<String?> {
  @override
  String? build() {
    _load();
    return null;
  }

  Future<void> _load() async {
    final stored = await ref.read(localStoreProvider).readJson(_key);
    if (ref.mounted && state == null && stored is String) {
      state = stored;
    }
  }

  /// At sign-in ([photo] from [googlePhotoOf]) and sign-out (null)
  Future<void> set(String? photo) async {
    state = photo;
    final store = ref.read(localStoreProvider);
    await (photo == null ? store.remove(_key) : store.writeJson(_key, photo));
  }
}

final accountPhotoProvider = NotifierProvider<AccountPhotoController, String?>(AccountPhotoController.new);

/// Who uses the app, as a disc: the account's Google picture, else a person on the brand's green when signed in, an
/// outlined one for a guest
class AccountAvatar extends ConsumerWidget {
  const AccountAvatar({super.key, this.size = 36});

  final double size;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final signedIn = ref.watch(authControllerProvider) == AuthStatus.signedIn;
    final photo = signedIn ? ref.watch(accountPhotoProvider) : null;
    final plain = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: signedIn ? scheme.primary : context.colors.card,
        border: signedIn ? null : Border.all(color: scheme.outline),
      ),
      child: Icon(
        signedIn ? Icons.person : Icons.person_outline,
        size: size * 0.6,
        color: signedIn ? scheme.onPrimary : scheme.onSurface,
      ),
    );
    if (photo == null) {
      return plain;
    }
    return ClipOval(
      child: Image.network(
        photo,
        width: size,
        height: size,
        fit: BoxFit.cover,
        // The web can't read an image of another site without its consent: shown by the browser itself then
        webHtmlElementStrategy: WebHtmlElementStrategy.fallback,
        // Offline, or a picture Google no longer serves
        errorBuilder: (_, _, _) => plain,
        frameBuilder: (_, child, frame, _) => frame == null ? plain : child,
      ),
    );
  }
}
