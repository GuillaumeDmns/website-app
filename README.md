# App mobilité Île-de-France (Flutter)

Android, web et desktop (iOS et macOS en usage personnel). Architecture et conventions : `CLAUDE.md`.

## Deux environnements qui ne se mélangent pas

| | Dev (chez toi) | Prod |
|---|---|---|
| Backend | `website-back` lancé sur ta machine (`./mvnw spring-boot:run`) : `http://localhost:8080`, base PostgreSQL locale | `https://guillaumedamiens.com` (VPS, base sur le VPS) |
| App Android | **Guillaume Dev**, `com.guillaumedamiens.app.dev`, icône orange « DEV » | **Guillaume**, `com.guillaumedamiens.app` |
| Web | `http://localhost:5000` | `https://app.guillaumedamiens.com` |
| Repère | bandeau « DEV » en haut à droite | aucun |

Les deux apps Android s'installent côte à côte. Une build de dev garde ses jetons et ses données à part (clés préfixées `dev.` sur desktop, autre app sur Android, autre site sur le web).

## Développer

En dev, l'app appelle toujours `http://localhost:8080`. `flutter run` sans option lance l'app de dev (`default-flavor: dev`).

```bash
flutter run -d <device>                      # Android (téléphone ou émulateur), après adb reverse ci-dessous
flutter run -d chrome --web-port 5000
flutter run -d linux
```

Sur un téléphone ou un émulateur Android, `localhost` est l'appareil lui-même : rediriger le port vers ta machine (à refaire à chaque branchement) :

```bash
adb reverse tcp:8080 tcp:8080
```

## Builds de production

```bash
flutter build apk --flavor prod              # ou appbundle (Play Store)
flutter build web --dart-define=APP_ENV=prod --no-web-resources-cdn   # CanvasKit servi par nous, pas par Google
flutter build linux --flavor prod --dart-define=APP_ENV=prod
```

La variante `prod` (ou `APP_ENV=prod`) ne connaît que `guillaumedamiens.com`.
