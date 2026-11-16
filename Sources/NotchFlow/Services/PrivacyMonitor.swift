import AppKit
import CoreAudio
import CoreMediaIO
import Combine

/// Détecte quand le micro ou la caméra sont utilisés par une app (visio, enregistrement…).
@MainActor
final class PrivacyMonitor: ObservableObject {
    static let shared = PrivacyMonitor()

    struct Start {
        let mic: Bool        // true = micro, false = caméra
        let app: String?
    }

    @Published private(set) var micInUse = false
    @Published private(set) var cameraInUse = false
    @Published private(set) var micApp: String?
    /// Toutes les apps qui utilisent le micro en ce moment.
    @Published private(set) var micApps: [String] = []

    /// Émis quand le micro ou la caméra viennent de s'activer.
    let started = PassthroughSubject<Start, Never>()

    private var timer: Timer?
    private var cancellables = Set<AnyCancellable>()

    private init() {}

    func start() {
        AppSettings.shared.$showPrivacyActivity
            .removeDuplicates()
            .sink { [weak self] enabled in enabled ? self?.startPolling() : self?.stopPolling() }
            .store(in: &cancellables)
    }

    private func startPolling() {
        guard timer == nil else { return }
        sample()
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.sample() }
        }
    }

    private func stopPolling() {
        timer?.invalidate()
        timer = nil
        micInUse = false
        cameraInUse = false
        micApp = nil
        micApps = []
    }

    private func sample() {
        let mic = Self.microphoneUsers()
        let camera = Self.cameraRunning()

        let micNow = mic.inUse
        if micNow != micInUse {
            micInUse = micNow
            if micNow { started.send(Start(mic: true, app: mic.app)) }
        }
        if micApp != mic.app { micApp = mic.app }
        if micApps != mic.apps { micApps = mic.apps }
        if camera != cameraInUse {
            cameraInUse = camera
            if camera { started.send(Start(mic: false, app: nil)) }
        }
    }

    // MARK: - Micro

    /// Processus système qui écoutent en permanence (« Dis Siri »…) : ignorés.
    private static let ignoredProcesses: Set<String> = [
        "corespeechd", "assistantd", "siriactionsd", "Siri", "SiriNCService", "heard", "com.apple.siri",
    ]

    /// Utilisation du micro et noms des apps qui l'utilisent (macOS 14.2+), sinon état du micro par défaut.
    private static func microphoneUsers() -> (inUse: Bool, app: String?, apps: [String]) {
        if #available(macOS 14.2, *) {
            let processes: [AudioObjectID] = arrayProperty(AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyProcessObjectList)
            let ownPID = ProcessInfo.processInfo.processIdentifier
            var names: [String] = []
            for process in processes {
                guard let running: UInt32 = scalarProperty(process, kAudioProcessPropertyIsRunningInput), running != 0 else { continue }
                let pid: pid_t = scalarProperty(process, kAudioProcessPropertyPID) ?? 0
                if pid == ownPID { continue }
                let name = processName(pid)
                if ignoredProcesses.contains(name) || ignoredProcesses.contains(where: { name.hasPrefix($0) && $0.contains(".") }) { continue }
                if !names.contains(name) { names.append(name) }
            }
            return (!names.isEmpty, names.first, names)
        }
        guard let device: AudioObjectID = scalarProperty(AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyDefaultInputDevice),
              let running: UInt32 = scalarProperty(device, kAudioDevicePropertyDeviceIsRunningSomewhere) else { return (false, nil, []) }
        return (running != 0, nil, [])
    }

    /// Nom lisible d'un processus : app (ou app parente d'un processus d'aide), sinon nom de l'exécutable.
    private static func processName(_ pid: pid_t) -> String {
        if let app = NSRunningApplication(processIdentifier: pid), let name = app.localizedName {
            return name
        }
        var buffer = [CChar](repeating: 0, count: 4096)
        guard proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 else { return "Processus \(pid)" }
        let path = String(cString: buffer)
        // « …/Google Chrome.app/Contents/Frameworks/…/Helper » → « Google Chrome »
        if let range = path.range(of: ".app/") {
            let appPath = String(path[..<range.lowerBound])
            return (appPath as NSString).lastPathComponent
        }
        return (path as NSString).lastPathComponent
    }

    private static func scalarProperty<T>(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> T? {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectHasProperty(object, &address) else { return nil }
        let pointer = UnsafeMutableRawPointer.allocate(byteCount: MemoryLayout<T>.size, alignment: MemoryLayout<T>.alignment)
        defer { pointer.deallocate() }
        var size = UInt32(MemoryLayout<T>.size)
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, pointer) == noErr else { return nil }
        return pointer.load(as: T.self)
    }

    private static func arrayProperty(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> [AudioObjectID] {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(object, &address, 0, nil, &size) == noErr, size > 0 else { return [] }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &ids) == noErr else { return [] }
        return ids
    }

    // MARK: - Caméra

    private static func cameraRunning() -> Bool {
        var address = CMIOObjectPropertyAddress(
            mSelector: CMIOObjectPropertySelector(kCMIOHardwarePropertyDevices),
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain)
        )
        let system = CMIOObjectID(kCMIOObjectSystemObject)
        var size: UInt32 = 0
        guard CMIOObjectGetPropertyDataSize(system, &address, 0, nil, &size) == 0, size > 0 else { return false }
        var devices = [CMIOObjectID](repeating: 0, count: Int(size) / MemoryLayout<CMIOObjectID>.size)
        var used: UInt32 = 0
        guard CMIOObjectGetPropertyData(system, &address, 0, nil, size, &used, &devices) == 0 else { return false }

        for device in devices {
            var runningAddress = CMIOObjectPropertyAddress(
                mSelector: CMIOObjectPropertySelector(kCMIODevicePropertyDeviceIsRunningSomewhere),
                mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
                mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain)
            )
            var running: UInt32 = 0
            var dataUsed: UInt32 = 0
            let status = CMIOObjectGetPropertyData(device, &runningAddress, 0, nil,
                                                   UInt32(MemoryLayout<UInt32>.size), &dataUsed, &running)
            if status == 0, running != 0 { return true }
        }
        return false
    }
}
