# App mobilité Île-de-France (Flutter)

Android, iOS, macOS, web et desktop (Linux, Windows). Architecture et conventions : `CLAUDE.md`.

## Deux environnements qui ne se mélangent pas

| | Dev (chez toi) | Prod |
|---|---|---|
| Backend | `website-back` lancé sur ta machine (`./mvnw spring-boot:run`) : `http://localhost:8080`, base PostgreSQL locale | `https://guillaumedamiens.com` (VPS, base sur le VPS) |
| App Android | **Nav' Dev**, `com.guillaumedamiens.app.dev`, icône orange « DEV » | **Nav'**, `com.guillaumedamiens.app` (Google Play) ; **Nav' Beta**, `com.guillaumedamiens.app.beta`, icône verte « BETA » (build de ta machine, installé avec adb) |
| App iOS / macOS | **Nav' Dev**, `com.guillaumedamiens.app.dev` (schéma Xcode `dev`) | **Nav'**, `com.guillaumedamiens.app` (schéma `prod`) |
| Web | `http://localhost:5000` | `https://app.guillaumedamiens.com` |
| Repère | bandeau « DEV » en haut à droite | aucun (bandeau vert « BETA » pour la bêta) |

Les trois apps Android s'installent côte à côte. La bêta sert à essayer sur les vraies données un build pas encore publié, sans toucher à l'app du Play Store (sans App Links : les liens partagés ouvrent l'app du Play Store). Une build de dev garde ses jetons et ses données à part (clés préfixées `dev.` sur desktop, autre app sur Android, autre site sur le web).

## Développer

En dev, l'app appelle toujours `http://localhost:8080`. `flutter run` sans option lance l'app de dev (`default-flavor: dev`).

```bash
flutter run -d <device>                      # Android (téléphone ou émulateur), après adb reverse ci-dessous
flutter run -d chrome --web-port 5000
flutter run -d linux
flutter run -d macos
flutter run -d <simulateur iOS>              # le simulateur atteint localhost:8080 du Mac
```

Sur un iPhone branché, `localhost` est le téléphone : `flutter run -d <iphone> --dart-define=API_BASE_URL=http://<ip-du-mac>:8080`. Le premier lancement iOS/macOS fait `pod install` ; Xcode signe avec l'équipe `L846MR2M2R` (signature automatique, à accepter une fois dans Xcode).

Sur un téléphone ou un émulateur Android, `localhost` est l'appareil lui-même : rediriger le port vers ta machine (à refaire à chaque branchement) :

```bash
adb reverse tcp:8080 tcp:8080
```

## Tests

```bash
flutter test                                 # unitaires, widgets et parcours complets de l'app, une dizaine de secondes
flutter test integration_test -d linux       # la vraie app Linux (ouvre une fenêtre)
```

Aucun test n'appelle le backend : un faux backend répond à la place de l'API (voir `test/support/`).

## CI

- Chaque pull request et chaque push sur `master` : check « Test » (analyse, tests, tests d'intégration de l'app Linux sous écran virtuel) et check « Build » (builds de prod : web, APK Android en artefact). Les deux doivent passer pour fusionner dans `master` : sur GitHub, *Settings → Rules → Rulesets → New branch ruleset*, cible *Default branch*, cocher *Require a pull request before merging*, *Require status checks to pass* (« Test » et « Build », visibles après un premier passage) et *Block force pushes*.
- Tag `v*` (ou lancement à la main sur un tag) : l'app web de prod est publiée dans la release GitHub du tag, puis le VPS la télécharge (`/var/www/guillaumedamiens-app`, lien `current`). Secrets GitHub du dépôt : `DEPLOY_HOST`, `DEPLOY_SSH_KEY`, `DEPLOY_KNOWN_HOSTS`, les mêmes que ceux de `website-back`.
- Tag `v*` aussi (`release.yml`) : les apps de prod sont construites et attachées à la même release GitHub (Android, Linux, Windows, voir « Installer une release »). L'APK n'est publié que s'il est signé avec la clé de release, donnée par quatre secrets du dépôt : `ANDROID_KEYSTORE_BASE64`, `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS`, `ANDROID_KEY_PASSWORD` (les valeurs de `android/key.properties` ; sans eux, la clé de debug du runner change à chaque build et l'APK ne pourrait jamais être mis à jour). Une pull request qui touche `release.yml` le lance à blanc : mêmes builds, gardés 7 jours en artefacts du run, rien de publié.

```bash
base64 -w0 <le keystore> | gh secret set ANDROID_KEYSTORE_BASE64
gh secret set ANDROID_KEYSTORE_PASSWORD      # puis ANDROID_KEY_ALIAS et ANDROID_KEY_PASSWORD : la valeur est demandée
```


## Builds de production

```bash
tool/build.sh appbundle --flavor prod        # Google Play (versionné depuis git)
tool/build.sh apk --flavor beta              # bêta, puis adb install -r build/app/outputs/flutter-apk/app-beta-release.apk
flutter build web --dart-define=APP_ENV=prod --no-web-resources-cdn   # CanvasKit servi par nous, pas par Google
flutter build linux --flavor prod --dart-define=APP_ENV=prod
```

Les variantes `prod` et `beta` (ou `APP_ENV=prod`) ne connaissent que `guillaumedamiens.com`.

## Installer une release

Chaque tag `vX.Y.Z` a sa [release GitHub](https://github.com/GuillaumeDmns/website-app/releases) avec les apps de prod. Rien pour iOS et macOS : sans compte Apple Developer payant, leurs builds ne peuvent pas être signés pour d'autres appareils.

| Fichier | Installation |
|---|---|
| `android-<tag>.apk` | L'ouvrir sur le téléphone et autoriser l'installation depuis cette source. |
| `linux-x64-<tag>.tar.gz` | Décompresser, lancer `website_app/website_app` (GTK 3 et libsecret, présents sur les bureaux courants). Au lancement, l'app s'ajoute à la liste des applications avec son icône (`~/.local/share/applications/com.guillaumedamiens.app.desktop`, mis à jour si le dossier est déplacé) : l'épingler au dock depuis là. Supprimer le dossier de l'app l'en retire (ce fichier peut ensuite être supprimé). |
| `windows-x64-<tag>.zip` | Décompresser, lancer `website_app.exe` ; SmartScreen prévient que l'éditeur est inconnu (*Informations complémentaires → Exécuter quand même*). |

Le build Windows n'est vérifié que par la CI (compilation) : personne ne l'a essayé sur une vraie machine.
