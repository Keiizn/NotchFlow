import SwiftUI
import ServiceManagement

// MARK: - Fenêtre de réglages (style Réglages Système)

@MainActor
struct SettingsView: View {
    enum Section: String, CaseIterable, Identifiable {
        case general, faceUnlock, appearance, activities, battery, controls, music, tabs, apps, widgets, about
        var id: String { rawValue }
        var title: String {
            switch self {
            case .general: "Général"
            case .faceUnlock: "Déverrouillage facial"
            case .battery: "Batterie"
            case .appearance: "Apparence"
            case .activities: "Activités en direct"
            case .controls: "Contrôles & raccourcis"
            case .music: "Musique"
            case .tabs: "Onglets"
            case .apps: "Applications"
            case .widgets: "Agenda, météo & outils"
            case .about: "À propos"
            }
        }
        var icon: String {
            switch self {
            case .general: "gearshape.fill"
            case .faceUnlock: "faceid"
            case .appearance: "paintbrush.fill"
            case .activities: "waveform"
            case .controls: "keyboard.fill"
            case .battery: "battery.100.bolt"
            case .music: "music.note"
            case .tabs: "square.grid.2x2.fill"
            case .apps: "app.badge.fill"
            case .widgets: "calendar"
            case .about: "info.circle.fill"
            }
        }
        var color: Color {
            switch self {
            case .general: .gray
            case .faceUnlock: .mint
            case .appearance: .purple
            case .activities: .pink
            case .controls: .cyan
            case .battery: .green
            case .music: .red
            case .tabs: .blue
            case .apps: .indigo
            case .widgets: .orange
            case .about: .teal
            }
        }
    }

    @State private var selection: Section? = .general

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                ForEach(Section.allCases) { section in
                    Label {
                        Text(section.title)
                    } icon: {
                        Image(systemName: section.icon)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 22, height: 22)
                            .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(section.color.gradient))
                    }
                    .tag(section)
                }
            }
            .navigationSplitViewColumnWidth(min: 200, ideal: 215, max: 260)
        } detail: {
            Group {
                switch selection ?? .general {
                case .general: GeneralSettings()
                case .faceUnlock: FaceUnlockSettings()
                case .appearance: AppearanceSettings()
                case .activities: ActivitiesSettings()
                case .controls: ControlsSettings()
                case .battery: BatterySettings()
                case .music: MusicSettings()
                case .tabs: TabsSettings()
                case .apps: AppsSettings()
                case .widgets: WidgetsSettings()
                case .about: AboutSettings()
                }
            }
            .navigationTitle((selection ?? .general).title)
        }
        .frame(minWidth: 720, minHeight: 500)
    }
}

// MARK: - Général

@MainActor
private struct GeneralSettings: View {
    @EnvironmentObject private var settings: AppSettings
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?
    @State private var confirmReset = false

    var body: some View {
        Form {
            Section("Démarrage") {
                Toggle("Lancer NotchFlow à l'ouverture de session", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in
                        do {
                            if enabled { try SMAppService.mainApp.register() }
                            else { try SMAppService.mainApp.unregister() }
                            loginError = nil
                        } catch {
                            loginError = "Impossible de modifier le lancement automatique. Placez l'app dans /Applications."
                        }
                    }
                if let loginError {
                    Text(loginError).font(.caption).foregroundStyle(.red)
                }
            }

            Section {
                Toggle("Ouvrir au survol", isOn: $settings.openOnHover)
                if settings.openOnHover {
                    LabeledContent("Délai d'ouverture") {
                        HStack {
                            Slider(value: $settings.hoverDelay, in: 0...1, step: 0.05)
                            Text(String(format: "%.2f s", settings.hoverDelay))
                                .monospacedDigit()
                                .frame(width: 48, alignment: .trailing)
                        }
                    }
                }
                Toggle("Fermer en cliquant ailleurs", isOn: $settings.closeOnClickOutside)
                Toggle("Retour haptique (trackpad)", isOn: $settings.haptics)
                FooterText("Vous pouvez aussi cliquer sur le notch, ou y glisser un fichier pour ouvrir l'étagère.")
            } header: {
                Text("Ouverture et fermeture")
            }

            Section {
                Toggle(isOn: $settings.showOnAllScreens) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Afficher sur tous les écrans")
                        Text("Un notch (ou une île) en haut de chaque écran branché")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("Écrans")
            }

            Section("Réinitialisation") {
                Button("Rétablir les réglages par défaut…", role: .destructive) { confirmReset = true }
                    .confirmationDialog("Rétablir tous les réglages par défaut ?", isPresented: $confirmReset) {
                        Button("Rétablir", role: .destructive) { settings.resetToDefaults() }
                    }
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Apparence

@MainActor
private struct AppearanceSettings: View {
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        Form {
            Section {
                NotchPreview(style: settings.style)
                    .frame(maxWidth: .infinity)
                    .listRowInsets(EdgeInsets())
                Picker("Style", selection: $settings.style) {
                    Text("Notch").tag(AppSettings.Style.notch)
                    Text("Dynamic Island").tag(AppSettings.Style.island)
                }
                .pickerStyle(.segmented)
                FooterText("« Dynamic Island » flotte sous le bord de l'écran sur les Mac sans notch.")
            } header: {
                Text("Forme")
            }

            Section {
                Picker("Thème du notch ouvert", selection: $settings.theme) {
                    ForEach(AppSettings.Theme.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                if settings.theme == .glass {
                    LabeledContent("Opacité du verre") {
                        HStack {
                            Slider(value: $settings.glassTint, in: 0...0.7, step: 0.05)
                            Text("\(Int(settings.glassTint * 100)) %").monospacedDigit().frame(width: 44, alignment: .trailing)
                        }
                    }
                }
                FooterText("Liquid Glass : verre dépoli translucide dans l'esprit de macOS Tahoe. Le notch fermé reste noir pour se fondre dans le notch matériel.")
            } header: {
                Text("Matière")
            }

            Section("Taille du notch ouvert") {
                LabeledContent("Largeur") {
                    HStack {
                        Slider(value: $settings.openWidth, in: 600...860, step: 10)
                        Text("\(Int(settings.openWidth)) pt").monospacedDigit().frame(width: 52, alignment: .trailing)
                    }
                }
                LabeledContent("Hauteur") {
                    HStack {
                        Slider(value: $settings.openHeight, in: 140...240, step: 10)
                        Text("\(Int(settings.openHeight)) pt").monospacedDigit().frame(width: 52, alignment: .trailing)
                    }
                }
            }

            Section {
                Toggle("Halo coloré pendant les activités", isOn: $settings.activityGlow)
                if settings.activityGlow {
                    LabeledContent("Intensité") {
                        HStack {
                            Slider(value: $settings.glowIntensity, in: 0.2...1, step: 0.1)
                            Text("\(Int(settings.glowIntensity * 100)) %").monospacedDigit().frame(width: 44, alignment: .trailing)
                        }
                    }
                    Toggle("Ambilight : pulser au rythme de la musique", isOn: $settings.musicGlowReactive)
                }
                FooterText("Le notch fermé s'éclaire de la couleur de l'activité : orange pour le minuteur et le micro, vert pour la charge… En mode Ambilight, il reprend les couleurs de la pochette et bat au rythme du son (macOS demande l'accès « Enregistrement audio du système » ; rien n'est enregistré).")
            } header: {
                Text("Halo")
            }

            Section("Effets") {
                Toggle("Grossir légèrement au survol", isOn: $settings.hoverGrow)
                Toggle("Ombre sous le notch ouvert", isOn: $settings.showShadow)
                Toggle("Batterie dans la barre du notch", isOn: $settings.showBatteryInHeader)
            }
        }
        .formStyle(.grouped)
    }
}

/// Petit aperçu animé du style choisi.
@MainActor
private struct NotchPreview: View {
    let style: AppSettings.Style
    @State private var open = false

    var body: some View {
        ZStack(alignment: .top) {
            LinearGradient(colors: [.blue.opacity(0.6), .purple.opacity(0.6)], startPoint: .topLeading, endPoint: .bottomTrailing)
            Group {
                if style == .notch {
                    Color.black.clipShape(NotchShape(topRadius: open ? 10 : 5, bottomRadius: open ? 18 : 8))
                } else {
                    Color.black.clipShape(RoundedRectangle(cornerRadius: open ? 20 : 11, style: .continuous))
                        .padding(.top, 4)
                }
            }
            .frame(width: open ? 260 : 120, height: open ? 90 : 22)
        }
        .frame(height: 120)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .padding(12)
        .onTapGesture { withAnimation(.spring(response: 0.45, dampingFraction: 0.75)) { open.toggle() } }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1.6))
                withAnimation(.spring(response: 0.45, dampingFraction: 0.75)) { open.toggle() }
            }
        }
        .animation(.spring(response: 0.45, dampingFraction: 0.75), value: style)
    }
}

// MARK: - Activités en direct

@MainActor
private struct ActivitiesSettings: View {
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        Form {
            Section {
                row("Musique en cours", "Pochette et égaliseur autour du notch", "music.note", .pink, $settings.showMusicActivity)
                row("Réunion imminente", "« dans X min » 10 minutes avant un événement", "calendar.badge.clock", .red, $settings.showEventActivity)
                row("Chargeur", "Animation au branchement / débranchement", "bolt.fill", .green, $settings.showBatteryActivity)
                row("Volume & luminosité", "HUD avec curseur lors d'un changement", "speaker.wave.2.fill", .blue, $settings.showVolumeHUD)
                row("Rappel à échéance", "Le titre du rappel s'affiche autour du notch", "checklist", .orange, $settings.showReminderActivity)
                FooterText("Le minuteur et le chronomètre s'affichent toujours dans le notch quand ils sont lancés.")
            } header: {
                Text("Quand le notch est fermé")
            }

            Section {
                row("Appareils Bluetooth", "AirPods, casque, clavier… à la connexion, avec leur batterie", "airpodspro", .blue, $settings.showDeviceActivity)
                row("Micro & caméra", "Pastille orange / verte quand une app les utilise", "mic.fill", .orange, $settings.showPrivacyActivity)
                row("Téléchargements", "Progression des téléchargements des navigateurs", "arrow.down.circle.fill", .indigo, $settings.showDownloadActivity)
                if settings.showDownloadActivity {
                    Toggle("Ajouter les téléchargements terminés à l'étagère", isOn: $settings.downloadsToShelf)
                }
                FooterText("Les téléchargements sont suivis dans le dossier Téléchargements : macOS demandera l'accès à ce dossier la première fois.")
            } header: {
                Text("Live Activities connectées")
            }
        }
        .formStyle(.grouped)
    }

    private func row(_ title: String, _ subtitle: String, _ icon: String, _ color: Color, _ binding: Binding<Bool>) -> some View {
        Toggle(isOn: binding) {
            SettingsRowLabel(title: title, subtitle: subtitle, icon: icon, color: color)
        }
    }
}

// MARK: - Batterie

@MainActor
private struct BatterySettings: View {
    @EnvironmentObject private var settings: AppSettings
    @ObservedObject private var manager = BatteryManager.shared

    var body: some View {
        Form {
            Section {
                LabeledContent("Assistant de charge") {
                    switch manager.helperState {
                    case .checking:
                        ProgressView().controlSize(.small)
                    case .ready:
                        HStack {
                            Label("Installé", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                            Button("Désinstaller…", role: .destructive) { manager.uninstallHelper() }
                        }
                    case .notInstalled:
                        Button("Installer…") { manager.installHelper() }
                    case .outdated:
                        Button("Mettre à jour…") { manager.installHelper() }
                    case .unsupported:
                        Text("Non pris en charge sur ce Mac").foregroundStyle(.secondary)
                    }
                }
                if let error = manager.lastError {
                    Text(error).font(.caption).foregroundStyle(.orange)
                }
                FooterText("Pour limiter la charge, macOS exige des droits administrateur. NotchFlow installe un petit assistant (/usr/local/libexec/notchflow-smc) qui ne sait faire que « charge on/off » et « adaptateur on/off », autorisé sans mot de passe pour votre compte uniquement. Votre mot de passe est demandé une seule fois.")
            } header: {
                Text("Installation")
            }

            Section {
                Toggle(isOn: $settings.chargeLimiterEnabled) {
                    SettingsRowLabel(title: "Limiter la charge", subtitle: "Le Mac reste alimenté par le secteur, la batterie ne dépasse pas la limite", icon: "leaf.fill", color: .green)
                }
                .disabled(manager.helperState != .ready)

                LabeledContent("Limite de charge") {
                    HStack {
                        Slider(value: Binding(
                            get: { Double(settings.chargeLimit) },
                            set: { settings.chargeLimit = Int($0) }
                        ), in: 20...100, step: 5)
                        Text("\(settings.chargeLimit) %").monospacedDigit().frame(width: 48, alignment: .trailing)
                    }
                }
                LabeledContent("Marge de reprise") {
                    HStack {
                        Slider(value: Binding(
                            get: { Double(settings.sailingRange) },
                            set: { settings.sailingRange = Int($0) }
                        ), in: 1...15, step: 1)
                        Text("\(settings.sailingRange) %").monospacedDigit().frame(width: 48, alignment: .trailing)
                    }
                }
                Toggle("Décharger automatiquement jusqu'à la limite quand le Mac est branché", isOn: $settings.dischargeToLimit)
                FooterText("Exemple : limite 80 %, marge 5 % → la charge s'arrête à 80 % et ne reprend que sous 75 %, ce qui évite les micro-recharges qui usent la batterie. Désactivez « Recharge optimisée » dans Réglages Système → Batterie pour éviter les conflits.")
            } header: {
                Text("Limite de charge")
            }

            Section {
                Picker("Pendant la veille", selection: $settings.sleepCharging) {
                    ForEach(AppSettings.SleepCharging.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }
                if manager.preventingSleep {
                    Label("Veille bloquée jusqu'à \(settings.chargeLimit) %", systemImage: "moon.zzz.fill")
                        .font(.caption).foregroundStyle(.orange)
                }
                FooterText("Quand le Mac dort, NotchFlow ne peut plus arrêter la charge à la limite : sans précaution, la batterie monte à 100 % pendant la nuit. « Couper la charge » met la charge en pause avant la veille (elle reprend au réveil si besoin). « Rester éveillé » empêche la veille sur secteur tant que la limite n'est pas atteinte, puis coupe la charge. La décharge forcée est toujours arrêtée avant la veille.")
            } header: {
                Text("Veille")
            }

            Section {
                Toggle("Protection thermique", isOn: $settings.heatProtection)
                if settings.heatProtection {
                    LabeledContent("Pause de la charge au-dessus de") {
                        HStack {
                            Slider(value: $settings.heatLimit, in: 30...45, step: 1)
                            Text("\(Int(settings.heatLimit)) °C").monospacedDigit().frame(width: 48, alignment: .trailing)
                        }
                    }
                }
                Toggle("Rétablir la charge normale quand NotchFlow se ferme", isOn: $settings.restoreChargingOnQuit)
                FooterText("La chaleur est l'ennemie n°1 des batteries lithium : la charge est mise en pause si la batterie dépasse la température choisie.")
            } header: {
                Text("Protection")
            }

            if manager.helperState == .ready {
                Section {
                    LabeledContent("Clés SMC", value: manager.smcKeys.isEmpty ? "—" : manager.smcKeys)
                    LabeledContent("Charge (SMC)") { smcLabel(manager.smcCharging, on: "Autorisée", off: "En pause") }
                    LabeledContent("Adaptateur (SMC)") { smcLabel(manager.smcAdapter, on: "Utilisé", off: "Coupé (décharge)") }
                    LabeledContent("Batterie", value: String(format: "%+.1f W", manager.health.batteryWatts))
                    LabeledContent("Raison de non-charge (macOS)",
                                   value: manager.notChargingReason == 0 ? "Aucune" : String(format: "0x%X", manager.notChargingReason))
                    if let warning = manager.stallWarning {
                        Text(warning).font(.caption).foregroundStyle(.orange)
                    }
                    HStack {
                        Button("Relire l'état") { manager.syncWithSMC() }
                        Button("Rétablir la charge normale") { manager.restoreNormalCharging() }
                    }
                    FooterText("État lu directement dans le contrôleur de charge du Mac, toutes les 15 s. Si la charge reste « Autorisée » au-dessus de la limite, envoyez une capture de cette section.")
                } header: {
                    Text("Diagnostic")
                }
            }

            Section("Santé de la batterie") {
                LabeledContent("Capacité maximale", value: manager.health.healthPercent > 0 ? "\(manager.health.healthPercent) %" : "—")
                LabeledContent("Cycles", value: "\(manager.health.cycleCount)")
                LabeledContent("Capacité", value: "\(manager.health.maxCapacity) / \(manager.health.designCapacity) mAh")
                LabeledContent("Température", value: String(format: "%.1f °C", manager.health.temperature))
                if manager.health.adapterWatts > 0 {
                    LabeledContent("Adaptateur", value: "\(manager.health.adapterWatts) W \(manager.health.adapterName)")
                }
            }
        }
        .formStyle(.grouped)
        .onAppear {
            manager.refreshHealth()
            manager.syncWithSMC()
        }
    }

    @ViewBuilder
    private func smcLabel(_ value: String, on: String, off: String) -> some View {
        switch value {
        case "enabled": Label(on, systemImage: "checkmark.circle.fill").foregroundStyle(.green)
        case "disabled": Label(off, systemImage: "pause.circle.fill").foregroundStyle(.orange)
        default: Text("Inconnu").foregroundStyle(.secondary)
        }
    }
}

// MARK: - Contrôles & raccourcis

@MainActor
private struct ControlsSettings: View {
    @EnvironmentObject private var settings: AppSettings
    @ObservedObject private var keys = MediaKeyService.shared

    var body: some View {
        Form {
            Section {
                Toggle(isOn: $settings.replaceSystemHUD) {
                    SettingsRowLabel(title: "Remplacer les HUD de macOS",
                                     subtitle: "Les touches volume et luminosité affichent le HUD du notch",
                                     icon: "speaker.wave.3.fill", color: .blue)
                }
                .onChange(of: settings.replaceSystemHUD) { _, _ in MediaKeyService.shared.start() }

                if settings.replaceSystemHUD {
                    LabeledContent("Autorisation Accessibilité") {
                        if keys.isActive {
                            Label("Active", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                        } else {
                            HStack {
                                Button("Autoriser…") { keys.requestTrust() }
                                Button("Réglages") { keys.openAccessibilitySettings() }
                            }
                        }
                    }
                }
                FooterText("macOS demande l'autorisation « Accessibilité » pour intercepter ces touches. ⌥⇧ + touche = réglage fin. Après une mise à jour, il peut falloir réactiver NotchFlow dans Réglages Système → Confidentialité et sécurité → Accessibilité.")
            } header: {
                Text("Volume et luminosité")
            }

            Section {
                Toggle(isOn: $settings.gesturesEnabled) {
                    SettingsRowLabel(title: "Balayer sur le notch",
                                     subtitle: "Deux doigts vers la gauche / droite : morceau suivant / précédent",
                                     icon: "hand.draw.fill", color: .pink)
                }
                Toggle(isOn: $settings.scrollVolume) {
                    SettingsRowLabel(title: "Défiler pour le volume",
                                     subtitle: "Défilement vertical (trackpad ou molette) au-dessus du notch",
                                     icon: "speaker.wave.2.fill", color: .blue)
                }
                .disabled(!settings.gesturesEnabled)
                FooterText("Les gestes fonctionnent sur le notch fermé et sur la barre du haut du notch ouvert.")
            } header: {
                Text("Gestes")
            }

            Section {
                Toggle(isOn: $settings.hotKeyEnabled) {
                    SettingsRowLabel(title: "Raccourci global \(HotKeyService.displayString)",
                                     subtitle: "Ouvre ou ferme le notch depuis n'importe quelle app",
                                     icon: "command", color: .gray)
                }
                .onChange(of: settings.hotKeyEnabled) { _, _ in HotKeyService.shared.register() }
            } header: {
                Text("Raccourci clavier")
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Musique

@MainActor
private struct MusicSettings: View {
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        Form {
            Section {
                Toggle(isOn: $settings.showLyrics) {
                    SettingsRowLabel(title: "Paroles synchronisées",
                                     subtitle: "Bouton « paroles » dans le lecteur (source : LRCLIB)",
                                     icon: "quote.bubble.fill", color: .pink)
                }
            } header: {
                Text("Lecteur")
            }

            Section {
                Toggle(isOn: $settings.browserMedia) {
                    SettingsRowLabel(title: "Lecteurs web",
                                     subtitle: "YouTube, Deezer, SoundCloud, Spotify Web… dans Safari, Chrome, Brave, Edge",
                                     icon: "globe", color: .blue)
                }
                VStack(alignment: .leading, spacing: 4) {
                    FooterText("Pour que NotchFlow puisse lire et piloter la lecture, autorisez le JavaScript depuis les événements Apple :")
                    FooterText("• Safari : Réglages → Avancées → « Afficher les fonctionnalités pour les développeurs Web », puis menu Développement → « Autoriser JavaScript depuis les Apple Events ».")
                    FooterText("• Chrome / Brave / Edge : menu Affichage → Options pour les développeurs → « Autoriser JavaScript à partir des Apple Events ».")
                }
            } header: {
                Text("Navigateurs")
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Onglets

@MainActor
private struct TabsSettings: View {
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        Form {
            Section {
                ForEach(NotchViewModel.Tab.allCases) { tab in
                    Toggle(isOn: Binding(
                        get: { settings.isTabEnabled(tab.rawValue) },
                        set: { settings.setTab(tab.rawValue, enabled: $0) }
                    )) {
                        SettingsRowLabel(title: tab.title, subtitle: tab.subtitle, icon: tab.icon, color: .blue)
                    }
                }
                FooterText("Les onglets sont répartis de chaque côté du notch. Au moins un onglet doit rester actif.")
            } header: {
                Text("Onglets du notch ouvert")
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Applications (lanceur)

@MainActor
private struct AppsSettings: View {
    @EnvironmentObject private var settings: AppSettings
    @ObservedObject private var launcher = AppLauncher.shared

    var body: some View {
        Form {
            Section {
                if launcher.favorites.isEmpty {
                    Text("Aucune application favorite").foregroundStyle(.secondary)
                }
                List {
                    ForEach(launcher.favorites) { item in
                        HStack(spacing: 10) {
                            Image(nsImage: launcher.icon(for: item.url))
                                .resizable()
                                .frame(width: 24, height: 24)
                            Text(item.name)
                            Spacer()
                            Button {
                                launcher.removeFavorite(item)
                            } label: {
                                Image(systemName: "minus.circle.fill").foregroundStyle(.red)
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                    .onMove { launcher.moveFavorite(from: $0, to: $1) }
                }
                .frame(minHeight: 220)
                HStack {
                    Button("Ajouter des applications…") { launcher.pickApps() }
                    Spacer()
                    Text("Glissez pour réordonner").font(.caption).foregroundStyle(.secondary)
                }
            } header: {
                Text("Favoris de l'onglet Applications")
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Agenda, météo & outils

@MainActor
private struct WidgetsSettings: View {
    @EnvironmentObject private var settings: AppSettings
    @ObservedObject private var calendar = CalendarService.shared

    var body: some View {
        Form {
            Section("Agenda") {
                Toggle("Afficher l'agenda sur l'accueil", isOn: $settings.showCalendar)
                LabeledContent("Accès au calendrier") {
                    if calendar.isAuthorized {
                        Label("Autorisé", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                    } else if calendar.isDenied {
                        Button("Ouvrir les réglages de confidentialité") { calendar.openPrivacySettings() }
                    } else {
                        Button("Autoriser") { calendar.requestAccess() }
                    }
                }
            }

            Section {
                Toggle("Afficher la météo sur l'accueil", isOn: $settings.showWeather)
                    .onChange(of: settings.showWeather) { _, on in if on { WeatherService.shared.refresh() } }
                TextField("Ville", text: $settings.weatherCity, prompt: Text("Vide = position actuelle"))
                    .onSubmit { WeatherService.shared.refresh() }
                Picker("Unité", selection: $settings.useFahrenheit) {
                    Text("°C").tag(false)
                    Text("°F").tag(true)
                }
                .pickerStyle(.segmented)
                .onChange(of: settings.useFahrenheit) { _, _ in WeatherService.shared.refresh() }
                Button("Actualiser maintenant") { WeatherService.shared.refresh() }
                FooterText("Données Open-Meteo, sans compte ni clé API.")
            } header: {
                Text("Météo")
            }

            Section("Presse-papiers") {
                Toggle("Garder l'historique du presse-papiers", isOn: $settings.clipboardEnabled)
                Button("Effacer l'historique", role: .destructive) { ClipboardService.shared.clear() }
            }

            WorldClockSettings()

            Section {
                Toggle("Envoyer les captures d'écran dans l'étagère", isOn: $settings.screenshotsToShelf)
                Button("Afficher les fichiers convertis dans le Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([ShelfStore.workFolder])
                }
                Button("Vider l'étagère") { ShelfStore.shared.clear() }
                Button("Effacer les notes rapides", role: .destructive) { NotesStore.shared.clear() }
                FooterText("Clic droit sur un fichier de l'étagère → Convertir : images (PNG, JPEG, HEIC, TIFF, PDF), PDF (images, texte, fusion), documents (Word, RTF, HTML, ODT, texte, PDF), audio (AAC, WAV, AIFF), vidéo (MP4, MOV, 720p, extraction audio). Les fichiers créés sont ajoutés à l'étagère.")
            } header: {
                Text("Étagère & notes")
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Horloges mondiales

@MainActor
private struct WorldClockSettings: View {
    @EnvironmentObject private var settings: AppSettings
    @State private var search = ""

    private var matches: [String] {
        let query = search.trimmingCharacters(in: .whitespaces).lowercased()
        guard query.count >= 2 else { return [] }
        return TimeZone.knownTimeZoneIdentifiers
            .filter { !settings.worldClocks.contains($0) }
            .filter { $0.lowercased().replacingOccurrences(of: "_", with: " ").contains(query) }
            .prefix(6)
            .map { $0 }
    }

    var body: some View {
        Section {
            ForEach(settings.worldClocks, id: \.self) { identifier in
                HStack {
                    Text(WorldClock.city(identifier))
                    Text(identifier).font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    if let zone = TimeZone(identifier: identifier) {
                        Text(WorldClock.time(zone, now: Date())).monospacedDigit().foregroundStyle(.secondary)
                    }
                    Button {
                        settings.worldClocks.removeAll { $0 == identifier }
                    } label: {
                        Image(systemName: "minus.circle.fill").foregroundStyle(.red)
                    }
                    .buttonStyle(.borderless)
                }
            }
            TextField("Ajouter une ville", text: $search, prompt: Text("Paris, Tokyo, New York…"))
            ForEach(matches, id: \.self) { identifier in
                Button {
                    settings.worldClocks.append(identifier)
                    search = ""
                } label: {
                    Label(identifier.replacingOccurrences(of: "_", with: " "), systemImage: "plus.circle.fill")
                }
                .buttonStyle(.borderless)
            }
            FooterText("Recherchez une grande ville en anglais (ex. « Los Angeles », « Sydney »).")
        } header: {
            Text("Horloges mondiales (onglet Outils)")
        }
    }
}

// MARK: - À propos

@MainActor
private struct AboutSettings: View {
    @EnvironmentObject private var settings: AppSettings
    @ObservedObject private var updater = UpdateChecker.shared

    var body: some View {
        Form {
            Section {
                VStack(spacing: 8) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .frame(width: 96, height: 96)
                    Text("NotchFlow").font(.title.bold())
                    Text("Version \(UpdateChecker.version)")
                        .font(.headline)
                    Text("Build \(UpdateChecker.build)\(UpdateChecker.commit.map { " · \($0)" } ?? "")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                    Text("Le notch de votre Mac devient un centre de contrôle animé : musique, agenda, météo, apps, fichiers, minuteur, notes, presse-papiers et statistiques système.")
                        .font(.callout)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: 400)
                        .padding(.top, 4)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }

            Section {
                LabeledContent("État") { statusView }
                if case .available = updater.status, !updater.releaseNotes.isEmpty {
                    Text(updater.releaseNotes)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(6)
                }
                HStack {
                    Button("Rechercher les mises à jour") { updater.check() }
                        .disabled(isBusy)
                    if case .available = updater.status {
                        Button("Installer maintenant") { updater.installUpdate() }
                            .buttonStyle(.borderedProminent)
                    }
                    Spacer()
                    if let last = updater.lastCheck {
                        Text("Vérifié \(last.formatted(.relative(presentation: .named)))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Toggle("Rechercher automatiquement (au lancement puis toutes les 6 h)", isOn: $settings.autoCheckUpdates)
                Toggle("Télécharger et installer automatiquement", isOn: $settings.autoInstallUpdates)
                    .disabled(!settings.autoCheckUpdates)
                if !UpdateChecker.canSelfUpdate {
                    Text("L'app ne peut pas se mettre à jour seule à cet emplacement. Placez-la dans /Applications, ou installez avec la commande Terminal.")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                FooterText("La mise à jour est téléchargée depuis GitHub, installée, puis NotchFlow redémarre tout seul. macOS peut redemander certaines autorisations ensuite.")
            } header: {
                Text("Mises à jour")
            }

            Section {
                Link("Code source sur GitHub", destination: URL(string: "https://github.com/\(UpdateChecker.repository)")!)
                Link("Historique des versions", destination: UpdateChecker.releasesURL)
            }
        }
        .formStyle(.grouped)
        .onAppear {
            if updater.status == .idle { updater.check() }
        }
    }

    private var isBusy: Bool {
        switch updater.status {
        case .checking, .downloading, .installing: true
        default: false
        }
    }

    @ViewBuilder
    private var statusView: some View {
        switch updater.status {
        case .idle:
            Text("—").foregroundStyle(.secondary)
        case .checking:
            HStack(spacing: 6) { ProgressView().controlSize(.small); Text("Vérification…") }
        case .upToDate:
            Label("À jour", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
        case .available(let version):
            Label("Version \(version) disponible", systemImage: "arrow.down.circle.fill").foregroundStyle(.blue)
        case .downloading(let version):
            HStack(spacing: 6) { ProgressView().controlSize(.small); Text("Téléchargement de la \(version)…") }
        case .installing(let version):
            HStack(spacing: 6) { ProgressView().controlSize(.small); Text("Installation de la \(version)…") }
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
        }
    }
}

// MARK: - Composants

@MainActor
private struct SettingsRowLabel: View {
    let title: String
    let subtitle: String
    let icon: String
    let color: Color

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 26, height: 26)
                .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(color.gradient))
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

/// Texte d'explication, affiché comme dernière ligne de la section (pleine largeur de la carte).
struct FooterText: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
