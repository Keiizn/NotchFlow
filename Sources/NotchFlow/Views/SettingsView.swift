import SwiftUI
import ServiceManagement

@MainActor
struct SettingsView: View {
    @EnvironmentObject private var settings: AppSettings
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?

    var body: some View {
        TabView {
            general
                .tabItem { Label("Général", systemImage: "gearshape") }
            modules
                .tabItem { Label("Modules", systemImage: "square.grid.2x2") }
            about
                .tabItem { Label("À propos", systemImage: "info.circle") }
        }
        .frame(width: 480, height: 460)
    }

    // MARK: - Général

    private var general: some View {
        Form {
            Section("Apparence") {
                Picker("Style", selection: $settings.style) {
                    Text("Notch").tag(AppSettings.Style.notch)
                    Text("Dynamic Island").tag(AppSettings.Style.island)
                }
                .pickerStyle(.segmented)

                LabeledContent("Largeur ouverte") {
                    Slider(value: $settings.openWidth, in: 560...820, step: 10)
                    Text("\(Int(settings.openWidth)) pt").monospacedDigit().frame(width: 52, alignment: .trailing)
                }
                LabeledContent("Hauteur ouverte") {
                    Slider(value: $settings.openHeight, in: 140...240, step: 10)
                    Text("\(Int(settings.openHeight)) pt").monospacedDigit().frame(width: 52, alignment: .trailing)
                }
            }

            Section("Comportement") {
                Toggle("Ouvrir au survol", isOn: $settings.openOnHover)
                if settings.openOnHover {
                    LabeledContent("Délai d'ouverture") {
                        Slider(value: $settings.hoverDelay, in: 0...1, step: 0.05)
                        Text(String(format: "%.2f s", settings.hoverDelay)).monospacedDigit().frame(width: 52, alignment: .trailing)
                    }
                }
                Toggle("Retour haptique (trackpad)", isOn: $settings.haptics)
                Toggle("Lancer NotchFlow à l'ouverture de session", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in
                        do {
                            if enabled { try SMAppService.mainApp.register() }
                            else { try SMAppService.mainApp.unregister() }
                            loginError = nil
                        } catch {
                            loginError = "Impossible de modifier le lancement automatique (\(error.localizedDescription))."
                        }
                    }
                if let loginError {
                    Text(loginError).font(.caption).foregroundStyle(.red)
                }
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Modules

    private var modules: some View {
        Form {
            Section("Activités en direct (notch fermé)") {
                Toggle("Musique en cours", isOn: $settings.showMusicActivity)
                Toggle("Branchement du chargeur", isOn: $settings.showBatteryActivity)
                Toggle("HUD du volume", isOn: $settings.showVolumeHUD)
                Toggle("Réunion imminente (10 min)", isOn: $settings.showEventActivity)
            }

            Section("Widgets") {
                Toggle("Agenda", isOn: $settings.showCalendar)
                Toggle("Météo", isOn: $settings.showWeather)
                    .onChange(of: settings.showWeather) { _, on in if on { WeatherService.shared.refresh() } }
                if settings.showWeather {
                    TextField("Ville", text: $settings.weatherCity, prompt: Text("Vide = position actuelle"))
                        .onSubmit { WeatherService.shared.refresh() }
                    Toggle("Degrés Fahrenheit", isOn: $settings.useFahrenheit)
                        .onChange(of: settings.useFahrenheit) { _, _ in WeatherService.shared.refresh() }
                    Button("Actualiser la météo") { WeatherService.shared.refresh() }
                }
            }

            Section("Presse-papiers") {
                Toggle("Historique du presse-papiers", isOn: $settings.clipboardEnabled)
                Button("Effacer l'historique", role: .destructive) { ClipboardService.shared.clear() }
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - À propos

    private var about: some View {
        VStack(spacing: 12) {
            Image(systemName: "sparkles")
                .font(.system(size: 44))
                .foregroundStyle(.linearGradient(colors: [.purple, .blue], startPoint: .topLeading, endPoint: .bottomTrailing))
            Text("NotchFlow").font(.title.bold())
            Text("Version \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")")
                .foregroundStyle(.secondary)
            Text("Transformez le notch de votre Mac en centre de contrôle animé : musique, agenda, météo, fichiers, minuteur, presse-papiers et plus.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 360)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
