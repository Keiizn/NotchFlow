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

### Nouveautés 1.4 — gestion de la batterie (façon AlDente)
- **Limite de charge** (20–100 %, 80 % recommandé) : le Mac reste alimenté par le secteur mais la batterie ne dépasse pas la limite.
- **Marge de reprise** (« sailing ») : la charge ne reprend que sous *limite − marge*, pour éviter les micro-recharges.
- **Décharge forcée** jusqu'à la limite même branché, **charge ponctuelle à 100 %** (avant un déplacement), **protection thermique**.
- **Santé** : capacité réelle vs d'origine, cycles, température, puissance entrante/sortante, adaptateur.
- Live Activity « 🍃 80 % max » quand la limite est atteinte ou au branchement.
- Fonctionne via un petit assistant root (`/usr/local/libexec/notchflow-smc`, code dans `Sources/notchflow-smc`) installé une fois avec le mot de passe administrateur. Il n'accepte que `charging on|off`, `adapter on|off`, `status` et `version`. Désinstallation depuis Réglages → Batterie.

### Nouveautés 1.3
- **Design Liquid Glass** : notch ouvert en verre dépoli translucide (reflets, liseré lumineux, cartes « widgets »), opacité réglable. Le thème « Noir classique » reste disponible.
- **HUD natifs volume & luminosité** : les touches du clavier affichent le HUD du notch à la place de celui de macOS, avec un curseur réglable à la souris (⌥⇧ = réglage fin). Nécessite l'autorisation Accessibilité.
- **Rappels** : rappels à cocher depuis le notch, ajout rapide, et Live Activity quand un rappel arrive à échéance.
- **Actions rapides** : verrouiller, veille de l'écran, capture, mode sombre, masquer le bureau, anti-veille, curseurs volume/luminosité et tes **Raccourcis** macOS.
- **Raccourci global ⌥⌘N** pour ouvrir/fermer le notch.
- **Paroles synchronisées** (LRCLIB) qui défilent avec la musique, **visualiseur** dans le lecteur.
- **Lecteurs web** : YouTube, Deezer, SoundCloud, Spotify Web… dans Safari, Chrome, Brave et Edge (activer « Autoriser JavaScript depuis les Apple Events » dans le navigateur).

### Réglages
Style **Notch** ou **Dynamic Island** (île flottante sur les écrans sans notch), taille d'ouverture, ouverture au survol + délai, haptique, lancement au démarrage, activation de chaque module, ville météo, °C / °F.

## Installation (une commande)

Ouvre le **Terminal** et colle :

```bash
curl -fsSL https://raw.githubusercontent.com/Keiizn/NotchFlow/main/install.sh | bash
```

La même commande sert pour les mises à jour. Elle télécharge la dernière version, l'installe dans
`/Applications` et la lance. Comme le fichier est téléchargé par `curl` et non par un navigateur,
macOS ne le met pas en quarantaine : le message « Impossible d'ouvrir l'application » n'apparaît pas.

## Compiler soi-même

### Prérequis
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
