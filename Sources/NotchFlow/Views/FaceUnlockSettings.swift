import AVFoundation
import SwiftUI

/// Réglages du déverrouillage facial.
@MainActor
struct FaceUnlockSettings: View {
    @ObservedObject private var face = FaceUnlockService.shared
    @State private var axTrusted = AXIsProcessTrusted()
    @State private var axResetDone = false
    @State private var password = ""
    @State private var passwordMessage: String?
    @State private var savingPassword = false
    @State private var editingPassword = false
    @State private var showEnroll = false
    @State private var confirmErase = false
    @State private var cameraStatus = AVCaptureDevice.authorizationStatus(for: .video)

    private let sessionOptions = [1, 4, 8, 24, 72, 168]

    var body: some View {
        Form {
            Section {
                Toggle(isOn: $face.enabled) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Déverrouiller le Mac avec mon visage")
                        Text("La webcam reconnaît ton visage sur l'écran verrouillé, comme Face ID.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                if face.enabled {
                    LabeledContent("Session") {
                        if face.isArmed, let until = face.armedUntil {
                            Label("Active jusqu'à \(until.formatted(date: .omitted, time: .shortened))", systemImage: "checkmark.shield.fill")
                                .foregroundStyle(.green)
                        } else {
                            Button("Activer avec Touch ID") { Task { await face.arm() } }
                                .disabled(!face.hasPassword)
                        }
                    }
                }
                if let error = face.lastError {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption).foregroundStyle(.orange)
                }
            } footer: {
                FooterText("Tout reste sur ce Mac : les visages sont convertis en empreintes chiffrées (AES-GCM), les images ne sont jamais enregistrées. Une webcam n'a pas de capteur de profondeur : c'est plus pratique mais moins sûr que Touch ID. Après chaque mise à jour, macOS peut redemander les autorisations Caméra et Accessibilité.")
            }

            Section("Préparation") {
                checkRow("Caméra", ok: cameraStatus == .authorized) {
                    if cameraStatus == .notDetermined {
                        Button("Autoriser") {
                            AVCaptureDevice.requestAccess(for: .video) { _ in
                                Task { @MainActor in cameraStatus = AVCaptureDevice.authorizationStatus(for: .video) }
                            }
                        }
                    } else {
                        Button("Ouvrir les réglages") {
                            open("x-apple.systempreferences:com.apple.preference.security?Privacy_Camera")
                        }
                    }
                }
                checkRow("Accessibilité (pour taper le mot de passe)", ok: axTrusted) {
                    HStack {
                        Button("Réparer") { repairAccessibility() }
                            .help("Retire l'ancienne autorisation (devenue invalide après une mise à jour) et la redemande")
                        Button("Autoriser") { MediaKeyService.shared.requestTrust() }
                    }
                }
                if !axTrusted {
                    Text(axResetDone
                         ? "Ancienne autorisation retirée. Coche maintenant NotchFlow dans la fenêtre Accessibilité qui vient de s'ouvrir."
                         : "NotchFlow est déjà coché dans Accessibilité mais refusé ? Après une mise à jour, macOS garde l'ancienne case : clique sur « Réparer ».")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                checkRow("Mot de passe de session", ok: face.hasPassword) { EmptyView() }
                checkRow("Au moins un visage", ok: !face.identities.isEmpty) {
                    Button("Ajouter") { showEnroll = true }
                        .disabled(cameraStatus != .authorized)
                }
            }

            Section {
                if face.hasPassword && !editingPassword {
                    LabeledContent("Mot de passe") {
                        HStack {
                            Label("Dans le trousseau", systemImage: "key.fill").foregroundStyle(.green)
                            Button("Modifier") { editingPassword = true }
                            Button("Supprimer", role: .destructive) { face.deletePassword() }
                        }
                    }
                } else {
                    SecureField("Mot de passe de ta session macOS", text: $password)
                        .onSubmit(savePassword)
                    HStack {
                        if savingPassword { ProgressView().controlSize(.small) }
                        if let passwordMessage {
                            Text(passwordMessage).font(.caption).foregroundStyle(.orange)
                        }
                        Spacer()
                        if editingPassword {
                            Button("Annuler") { editingPassword = false; password = "" }
                        }
                        Button("Vérifier et enregistrer", action: savePassword)
                            .disabled(password.isEmpty || savingPassword)
                    }
                }
            } header: {
                Text("Mot de passe")
            } footer: {
                FooterText("macOS ne permet pas à une app d'ouvrir la session : quand ton visage est reconnu, NotchFlow tape ce mot de passe à ta place. Il est vérifié, rangé dans le trousseau et n'est chargé en mémoire qu'après Touch ID, pour la durée de session choisie.")
            }

            Section {
                ForEach(face.identities) { identity in
                    HStack {
                        Toggle("", isOn: Binding(
                            get: { identity.enabled },
                            set: { face.setEnabled(identity, $0) }
                        ))
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                        TextField("", text: Binding(
                            get: { identity.name },
                            set: { face.rename(identity, to: $0) }
                        ), prompt: Text("Nom"))
                        .labelsHidden()
                        .textFieldStyle(.plain)
                        .font(.body.weight(.medium))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        Spacer()
                        Text("\(identity.samples.count) prises")
                            .font(.caption)
                            .foregroundStyle(identity.samples.count < FaceUnlockService.enrollTarget ? .orange : .secondary)
                            .help(identity.samples.count < FaceUnlockService.enrollTarget
                                  ? "Profil incomplet : ajoute un nouveau visage (\(FaceUnlockService.enrollTarget) prises) puis supprime celui-ci."
                                  : "")
                        if let score = face.liveScores[identity.id] {
                            Text(String(format: "%.3f", score))
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(Double(score) >= face.threshold ? .green : .secondary)
                        }
                        Button(role: .destructive) { face.delete(identity) } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                    }
                }
                Button {
                    showEnroll = true
                } label: {
                    Label("Ajouter un visage…", systemImage: "plus.circle.fill")
                }
                .disabled(cameraStatus != .authorized)
            } header: {
                Text("Visages")
            } footer: {
                FooterText("Ajoute plusieurs profils pour toi (avec lunettes, le soir, avec un bonnet…) ou pour une autre personne. Désactive un profil sans le supprimer avec l'interrupteur.")
            }

            Section {
                LabeledContent("Seuil de ressemblance") {
                    HStack {
                        Slider(value: $face.threshold, in: 0.80...0.99, step: 0.005)
                            .frame(width: 200)
                        Text(String(format: "%.3f", face.threshold)).monospacedDigit().frame(width: 44)
                    }
                }
                if let suggested = face.suggestedThreshold {
                    LabeledContent("Seuil conseillé pour tes visages") {
                        Button(String(format: "Appliquer %.3f", suggested)) { face.threshold = suggested }
                    }
                }
                Picker("Détection du vivant", selection: $face.liveness) {
                    ForEach(FaceUnlockService.Liveness.allCases) { Text($0.title).tag($0) }
                }
                Stepper("Images concordantes requises : \(face.requiredFrames)", value: $face.requiredFrames, in: 1...8)
                Picker("Durée de session après Touch ID", selection: $face.sessionHours) {
                    ForEach(sessionOptions, id: \.self) { hours in
                        Text(hours < 24 ? "\(hours) h" : (hours == 24 ? "1 jour" : "\(hours / 24) jours")).tag(hours)
                    }
                }
                Toggle("Redemander Touch ID automatiquement à l'expiration", isOn: $face.autoRearm)
            } header: {
                Text("Sécurité")
            } footer: {
                FooterText("Plus le seuil est haut, plus la reconnaissance est stricte. Utilise le test ci-dessous, avec toi puis avec une autre personne ou une photo : règle le seuil entre ton score et le sien. La détection du vivant refuse les photos immobiles (léger) ou exige un clignement des yeux (strict) ; une vidéo peut toutefois la tromper.")
            }

            Section {
                HStack {
                    Button(face.testRunning ? "Arrêter" : "Tester la reconnaissance (10 s)") {
                        face.testRunning ? face.stopTest() : face.startTest()
                    }
                    .disabled(face.identities.isEmpty || cameraStatus != .authorized)
                    Spacer()
                    if face.testRunning || face.phase != .idle {
                        testStatus
                    }
                }
                if face.testRunning {
                    HStack(alignment: .top, spacing: 14) {
                        CameraPreview()
                            .frame(width: 200, height: 150)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(face.identities.filter(\.enabled)) { identity in
                                scoreBar(identity.name, score: face.liveScores[identity.id] ?? 0)
                            }
                            Label(face.livenessPassed ? "Vivant détecté" : "Vivant : en attente",
                                  systemImage: face.livenessPassed ? "checkmark.circle.fill" : "hourglass")
                                .font(.caption)
                                .foregroundStyle(face.livenessPassed ? .green : .secondary)
                        }
                    }
                }
            } header: {
                Text("Test")
            } footer: {
                FooterText("Le test n'ouvre rien : il affiche le score en direct de chaque visage enregistré.")
            }

            Section {
                Toggle("Afficher l'île sur l'écran verrouillé", isOn: $face.showOnLockScreen)
                if let diagnostic = face.lockDiagnostic {
                    Label(diagnostic, systemImage: "stethoscope")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                Toggle("Analyser quand la souris bouge", isOn: $face.scanOnMouse)
                LabeledContent("Durée d'une analyse") {
                    HStack {
                        Slider(value: $face.scanSeconds, in: 3...12, step: 1).frame(width: 160)
                        Text("\(Int(face.scanSeconds)) s").monospacedDigit().frame(width: 34)
                    }
                }
            } header: {
                Text("Écran verrouillé")
            } footer: {
                FooterText("L'analyse démarre au réveil de l'écran, quand la souris bouge ou quand tu touches l'île. Pendant les 4 secondes qui suivent le verrouillage, rien ne se déclenche, pour te laisser le temps de partir.")
            }

            Section {
                Button("Tout effacer (visages, mot de passe, clé)…", role: .destructive) { confirmErase = true }
                    .confirmationDialog("Effacer toutes les données du déverrouillage facial ?", isPresented: $confirmErase) {
                        Button("Tout effacer", role: .destructive) { face.eraseEverything() }
                    }
            }
        }
        .formStyle(.grouped)
        .sheet(isPresented: $showEnroll) {
            EnrollSheet().environmentObject(face)
        }
        .onAppear {
            cameraStatus = AVCaptureDevice.authorizationStatus(for: .video)
            axTrusted = AXIsProcessTrusted()
        }
        .onReceive(Timer.publish(every: 1.5, on: .main, in: .common).autoconnect()) { _ in
            axTrusted = AXIsProcessTrusted()
            cameraStatus = AVCaptureDevice.authorizationStatus(for: .video)
        }
        .onDisappear { face.stopTest() }
    }

    private func savePassword() {
        let value = password
        savingPassword = true
        passwordMessage = nil
        Task {
            let error = await face.savePassword(value)
            savingPassword = false
            if let error {
                passwordMessage = error
            } else {
                password = ""
                editingPassword = false
            }
        }
    }

    @ViewBuilder
    private var testStatus: some View {
        switch face.phase {
        case .recognized(let name):
            Label("Reconnu : \(name)", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
        case .failed(let reason):
            Label(reason, systemImage: "xmark.circle.fill").foregroundStyle(.red)
        case .scanning:
            Label(face.faceVisible ? "Analyse…" : "Aucun visage", systemImage: "faceid").foregroundStyle(.secondary)
        default:
            EmptyView()
        }
    }

    private func scoreBar(_ name: String, score: Float) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(name).font(.caption)
                Spacer()
                Text(String(format: "%.3f", score)).font(.caption.monospacedDigit())
            }
            GeometryReader { proxy in
                let lower = 0.6
                let fraction = max(0, min(1, (Double(score) - lower) / (1 - lower)))
                let mark = (face.threshold - lower) / (1 - lower)
                ZStack(alignment: .leading) {
                    Capsule().fill(.quaternary)
                    Capsule().fill(Double(score) >= face.threshold ? Color.green : Color.orange)
                        .frame(width: proxy.size.width * fraction)
                    Rectangle().fill(.primary).frame(width: 2, height: 10)
                        .offset(x: proxy.size.width * mark - 1)
                }
            }
            .frame(height: 6)
        }
        .frame(width: 220)
    }

    private func checkRow<Accessory: View>(_ title: String, ok: Bool, @ViewBuilder accessory: () -> Accessory) -> some View {
        LabeledContent {
            if ok {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            } else {
                accessory()
            }
        } label: {
            Label(title, systemImage: ok ? "checkmark.seal" : "circle.dashed")
        }
    }

    /// Supprime l'entrée Accessibilité périmée (signature d'une ancienne version) puis redemande.
    private func repairAccessibility() {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
        task.arguments = ["reset", "Accessibility", Bundle.main.bundleIdentifier ?? "app.notchflow.NotchFlow"]
        try? task.run()
        task.waitUntilExit()
        axResetDone = true
        MediaKeyService.shared.requestTrust()
        open("x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
    }

    private func open(_ string: String) {
        if let url = URL(string: string) { NSWorkspace.shared.open(url) }
    }
}

/// Fenêtre d'enregistrement d'un visage.
@MainActor
private struct EnrollSheet: View {
    @EnvironmentObject private var face: FaceUnlockService
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""

    var body: some View {
        VStack(spacing: 16) {
            Text("Ajouter un visage").font(.title2.bold())

            ZStack {
                CameraPreview()
                    .frame(width: 240, height: 240)
                    .clipShape(Circle())
                Circle()
                    .stroke(.quaternary, lineWidth: 6)
                    .frame(width: 256, height: 256)
                Circle()
                    .trim(from: 0, to: face.enrollProgress)
                    .stroke(Color.green, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .frame(width: 256, height: 256)
                    .animation(.easeOut(duration: 0.25), value: face.enrollProgress)
            }

            Text(face.enrollHint)
                .font(.headline)
                .foregroundStyle(face.enrollComplete ? .green : .primary)

            TextField("Nom (ex. « Moi », « Avec lunettes »)", text: $name)
                .textFieldStyle(.roundedBorder)
                .frame(width: 280)

            HStack {
                Button("Annuler") {
                    face.cancelEnroll()
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                Button("Recommencer") { face.cancelEnroll(); face.startEnroll() }
                Button("Enregistrer") {
                    face.finishEnroll(name: name)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!face.enrollComplete)
            }
        }
        .padding(28)
        .frame(width: 400)
        .onAppear { face.startEnroll() }
        .onDisappear { face.cancelEnroll() }
    }
}
