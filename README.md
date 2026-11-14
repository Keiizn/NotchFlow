# NotchFlow ✨

Transforme le notch de ton MacBook (ou le haut de n'importe quel écran) en **Dynamic Island** animée.

## Fonctionnalités

### Notch fermé — « Live Activities »
| Activité | Ce qui s'affiche |
|---|---|
| 🎵 Musique | Pochette à gauche, égaliseur animé à droite (couleur extraite de la pochette) |
| ⏱ Minuteur | Compte à rebours en direct |
| 📅 Réunion imminente | « dans X min » quand un événement commence dans les 10 minutes |
| 🔊 Volume | HUD avec icône + jauge à chaque changement de volume |
| 🔋 Chargeur | Éclair animé + pourcentage au branchement / débranchement |

Le notch grossit légèrement au survol, s'ouvre au survol (délai réglable) ou au clic, avec des animations à ressort et un retour haptique.

### Notch ouvert — onglets
- **Accueil**
  - **Lecteur Spotify / Apple Music** : pochette, titre, artiste, barre de progression déplaçable, précédent / lecture / suivant. La pochette passe du notch fermé au lecteur avec une animation fluide (`matchedGeometryEffect`).
  - **Agenda** : événements d'aujourd'hui et de demain (couleur du calendrier, « En cours », toute la journée) + bouton **Rejoindre** si un lien Zoom / Meet / Teams / Webex / FaceTime est détecté.
  - **Météo** (Open-Meteo, sans clé API) : position approximative ou ville choisie.
- **Étagère** : glisse un fichier sur le notch, il s'ouvre et le garde. Tu peux ensuite le reglisser n'importe où, l'ouvrir, l'afficher dans le Finder ou l'envoyer par **AirDrop**.
- **Minuteur** : préréglages 1 / 5 / 10 / 15 / 25 (Pomodoro) / 45 min, pause, +1 min, son à la fin.
- **Presse-papiers** : historique des 30 derniers textes copiés (les mots de passe des gestionnaires sont ignorés), clic = recopier.
- **Miroir** : aperçu de la caméra avant une visio.

### Réglages
Style **Notch** ou **Dynamic Island** (île flottante sur les écrans sans notch), taille d'ouverture, ouverture au survol + délai, haptique, lancement au démarrage, activation de chaque module, ville météo, °C / °F.

## Prérequis
- macOS 14 Sonoma ou plus récent (idéalement un MacBook avec notch, mais ça fonctionne partout)
- Xcode 15+ ou les Command Line Tools (Swift 5.9+)

## Compiler et lancer

```bash
make run          # compile, assemble build/NotchFlow.app et le lance
make install      # copie dans /Applications
```

ou sans `make` :

```bash
bash scripts/build-app.sh
open build/NotchFlow.app
```

L'app vit dans la barre des menus (icône ✨) — pas d'icône dans le Dock.

> Pour développer dans Xcode : `open Package.swift`. Attention, lancé directement depuis Xcode
> (hors bundle `.app`), macOS ne trouve pas les descriptions d'autorisations de l'Info.plist :
> l'agenda, la caméra et la localisation ne marcheront pas. Utilise `make run` pour tester ces modules.

## Autorisations demandées
| Autorisation | Pourquoi |
|---|---|
| Automatisation (Spotify, Musique) | Lire le morceau en cours et piloter la lecture via AppleScript |
| Calendriers | Afficher les événements |
| Localisation | Météo locale (facultatif si tu choisis une ville) |
| Caméra | Onglet Miroir |

Si tu refuses par erreur : **Réglages Système → Confidentialité et sécurité**.

## Architecture

```
Sources/NotchFlow
├── App/            AppDelegate (menu bar, réglages), NotchWindowController (NSPanel transparent + suivi souris)
├── Core/           NotchViewModel (état, géométrie, survol, HUD), AppSettings, NotchGeometry (détection du notch)
├── Services/       MediaController, CalendarService, BatteryService, VolumeService,
│                   WeatherService, ShelfStore, TimerService, ClipboardService
├── Views/          NotchShape, NotchRootView, CompactNotchView (Live Activities), OpenNotchView, SettingsView
│   └── Tabs/       HomeView (lecteur, agenda, météo), ShelfView, TimerView, ClipboardView, MirrorView
└── Support/        Extensions (couleur dominante d'une pochette, formatage)
```

**Fonctionnement** : une fenêtre `NSPanel` sans bordure, transparente, est posée au-dessus de la barre des menus, centrée sur le notch (taille détectée via `safeAreaInsets` et `auxiliaryTopLeftArea` / `auxiliaryTopRightArea`). Les pixels transparents laissent passer les clics. Le survol est détecté par des moniteurs d'événements souris globaux. La forme noire change de taille avec des ressorts SwiftUI.

## Limites connues
- **Lecteurs pris en charge** : Spotify et Apple Music. Depuis macOS 15.4, Apple restreint le framework privé MediaRemote, donc les autres sources (navigateurs, YouTube…) ne sont pas gérées.
- **HUD du volume** : il s'ajoute au HUD système, il ne le remplace pas (le masquer nécessiterait d'intercepter les touches média, avec l'autorisation Accessibilité).
- Signature ad hoc : au premier lancement, fais **clic droit → Ouvrir** si Gatekeeper bloque l'app.

## Idées d'évolution
Luminosité, rappels, notifications, raccourci clavier global, prise en charge de plusieurs écrans, widgets Raccourcis.
