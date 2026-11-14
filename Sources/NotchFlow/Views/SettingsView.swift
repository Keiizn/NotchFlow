import SwiftUI
import ServiceManagement

// MARK: - Fenêtre de réglages (style Réglages Système)

@MainActor
struct SettingsView: View {
    enum Section: String, CaseIterable, Identifiable {
        case general, appearance, activities, tabs, apps, widgets, about
        var id: String { rawValue }
        var title: String {
            switch self {
            case .general: "Général"
            case .appearance: "Apparence"
            case .activities: "Activités en direct"
            case .tabs: "Onglets"
            case .apps: "Applications"
            case .widgets: "Agenda, météo & outils"
            case .about: "À propos"
            }
        }
        var icon: String {
            switch self {
            case .general: "gearshape.fill"
            case .appearance: "paintbrush.fill"
            case .activities: "waveform"
            case .tabs: "square.grid.2x2.fill"
            case .apps: "app.badge.fill"
            case .widgets: "calendar"
            case .about: "info.circle.fill"
            }
        }
        var color: Color {
            switch self {
            case .general: .gray
            case .appearance: .purple
            case .activities: .pink
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
                case .appearance: AppearanceSettings()
                case .activities: ActivitiesSettings()
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
            } header: {
                Text("Ouverture et fermeture")
            } footer: {
                Text("Vous pouvez aussi cliquer sur le notch, ou y glisser un fichier pour ouvrir l'étagère.")
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
            } header: {
                Text("Forme")
            } footer: {
                Text("« Dynamic Island » flotte sous le bord de l'écran sur les Mac sans notch.")
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
                row("Volume", "HUD lors d'un changement de volume", "speaker.wave.2.fill", .blue, $settings.showVolumeHUD)
            } header: {
                Text("Quand le notch est fermé")
            } footer: {
                Text("Le minuteur s'affiche toujours dans le notch quand il est lancé.")
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
            } header: {
                Text("Onglets du notch ouvert")
            } footer: {
                Text("Les onglets sont répartis de chaque côté du notch. Au moins un onglet doit rester actif.")
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
            } header: {
                Text("Météo")
            } footer: {
                Text("Données Open-Meteo, sans compte ni clé API.")
            }

            Section("Presse-papiers") {
                Toggle("Garder l'historique du presse-papiers", isOn: $settings.clipboardEnabled)
                Button("Effacer l'historique", role: .destructive) { ClipboardService.shared.clear() }
            }

            Section("Étagère & notes") {
                Button("Vider l'étagère") { ShelfStore.shared.clear() }
                Button("Effacer les notes rapides", role: .destructive) { NotesStore.shared.clear() }
            }
        }
        .formStyle(.grouped)
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
            } header: {
                Text("Mises à jour")
            } footer: {
                Text("La mise à jour est téléchargée depuis GitHub, installée, puis NotchFlow redémarre tout seul. macOS peut redemander certaines autorisations ensuite.")
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
