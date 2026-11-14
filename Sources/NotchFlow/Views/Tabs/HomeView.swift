import SwiftUI

@MainActor
struct HomeView: View {
    let ns: Namespace.ID
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var vm: NotchViewModel
    @EnvironmentObject private var media: MediaController

    private var glass: Bool { settings.theme == .glass }

    var body: some View {
        HStack(spacing: 10) {
            MediaPlayerView(ns: ns)
                .frame(width: 290)
                .modifier(CardIfGlass(enabled: glass))

            if vm.showLyrics && media.track != nil {
                LyricsView()
                    .modifier(CardIfGlass(enabled: glass))
                    .transition(.opacity.combined(with: .scale(scale: 0.97)))
            } else {
                if settings.showCalendar {
                    if !glass { VerticalDivider() }
                    CalendarWidget()
                        .frame(maxWidth: .infinity)
                        .modifier(CardIfGlass(enabled: glass))
                } else {
                    Spacer(minLength: 0)
                }
                if settings.showWeather {
                    if !glass { VerticalDivider() }
                    WeatherWidget()
                        .frame(width: glass ? 92 : 100)
                        .modifier(CardIfGlass(enabled: glass))
                        .frame(width: glass ? 112 : 100)
                }
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: vm.showLyrics)
    }
}

/// Applique une carte en verre seulement en thème Liquid Glass.
struct CardIfGlass: ViewModifier {
    let enabled: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if enabled {
            content.glassCard()
        } else {
            content
        }
    }
}

// MARK: - Lecteur

@MainActor
struct MediaPlayerView: View {
    let ns: Namespace.ID
    @EnvironmentObject private var media: MediaController
    @EnvironmentObject private var vm: NotchViewModel
    @EnvironmentObject private var settings: AppSettings
    @ObservedObject private var lyrics = LyricsService.shared

    var body: some View {
        if let track = media.track {
            HStack(spacing: 12) {
                ArtworkView(image: media.artwork, cornerRadius: 14)
                    .frame(width: 84, height: 84)
                    .shadow(color: media.accentColor.opacity(0.5), radius: 16)
                    .scaleEffect(media.isPlaying ? 1 : 0.92)
                    .animation(.spring(response: 0.4, dampingFraction: 0.7), value: media.isPlaying)
                    .overlay(alignment: .bottomTrailing) { sourceBadge }
                    .onTapGesture { media.openSourceApp() }
                    .help("Ouvrir \(media.source?.displayName ?? "le lecteur")")

                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .top, spacing: 6) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(track.title)
                                .font(.system(size: 14, weight: .semibold))
                                .lineLimit(1)
                            Text(track.artist)
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 0)
                        // Visualiseur
                        AudioBars(color: media.accentColor, isPlaying: media.isPlaying, count: 5, height: 18, barWidth: 3)
                            .padding(.top, 2)
                    }

                    Spacer(minLength: 2)

                    TimelineView(.periodic(from: .now, by: 0.5)) { context in
                        let position = media.currentPosition(at: context.date)
                        VStack(spacing: 2) {
                            SeekBar(
                                progress: track.duration > 0 ? position / track.duration : 0,
                                color: media.accentColor
                            ) { fraction in
                                media.seek(to: fraction * track.duration)
                            }
                            HStack {
                                Text(Format.clock(position))
                                Spacer()
                                Text("-" + Format.clock(max(0, track.duration - position)))
                            }
                            .font(.system(size: 9.5, weight: .medium))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                        }
                    }

                    HStack(spacing: 18) {
                        control("backward.fill", size: 14) { media.previous() }
                        control(media.isPlaying ? "pause.fill" : "play.fill", size: 20) { media.playPause() }
                        control("forward.fill", size: 14) { media.next() }
                        if settings.showLyrics {
                            Button {
                                vm.showLyrics.toggle()
                            } label: {
                                Image(systemName: "quote.bubble.fill")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(vm.showLyrics ? media.accentColor : .white.opacity(lyrics.state == .notFound ? 0.25 : 0.6))
                                    .frame(width: 22, height: 22)
                            }
                            .buttonStyle(PressableButtonStyle())
                            .help("Paroles")
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 2)
                }
            }
        } else {
            VStack(spacing: 8) {
                Image(systemName: "music.note.list")
                    .font(.system(size: 26))
                    .foregroundStyle(.white.opacity(0.35))
                Text("Rien en lecture")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                HStack(spacing: 6) {
                    if media.isInstalled(.spotify) {
                        Button("Spotify") { media.launch(.spotify) }
                            .buttonStyle(PillButtonStyle(tint: .green))
                    }
                    Button("Musique") { media.launch(.music) }
                        .buttonStyle(PillButtonStyle(tint: .pink))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private var sourceBadge: some View {
        if let source = media.source, source.isBrowser {
            Image(systemName: "globe")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.white)
                .padding(4)
                .background(Circle().fill(Color.black.opacity(0.7)))
                .offset(x: 4, y: 4)
                .help("Lecture dans \(source.displayName)")
        }
    }

    private func control(_ symbol: String, size: CGFloat, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(.white)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 26, height: 24)
        }
        .buttonStyle(PressableButtonStyle())
    }
}

// MARK: - Paroles

@MainActor
struct LyricsView: View {
    @EnvironmentObject private var media: MediaController
    @ObservedObject private var lyrics = LyricsService.shared

    var body: some View {
        Group {
            switch lyrics.state {
            case .loading, .idle:
                VStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("Recherche des paroles…").font(.system(size: 11)).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .notFound:
                VStack(spacing: 6) {
                    Image(systemName: "text.badge.xmark").font(.system(size: 20)).foregroundStyle(.white.opacity(0.4))
                    Text("Paroles introuvables pour ce titre").font(.system(size: 11)).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .plain:
                ScrollView(.vertical, showsIndicators: false) {
                    Text(lyrics.plainText)
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.85))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            case .synced:
                synced
                    .overlay(alignment: .topTrailing) { offsetControls }
            }
        }
    }

    /// Réglage manuel si les paroles sont en avance / en retard.
    private var offsetControls: some View {
        HStack(spacing: 2) {
            Button { lyrics.nudge(-0.5) } label: { Image(systemName: "minus") }
                .help("Paroles plus tard")
            Text(lyrics.offset == 0 ? "synchro" : String(format: "%+.1f s", lyrics.offset))
                .font(.system(size: 9, weight: .semibold))
                .monospacedDigit()
                .frame(minWidth: 40)
                .onTapGesture { lyrics.offset = 0 }
                .help("Cliquer pour réinitialiser")
            Button { lyrics.nudge(0.5) } label: { Image(systemName: "plus") }
                .help("Paroles plus tôt")
        }
        .font(.system(size: 9, weight: .bold))
        .buttonStyle(PressableButtonStyle())
        .foregroundStyle(.white.opacity(0.7))
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(Capsule().fill(Color.black.opacity(0.35)))
    }

    private var synced: some View {
        TimelineView(.periodic(from: .now, by: 0.25)) { context in
            let current = lyrics.index(at: media.currentPosition(at: context.date))
            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(lyrics.lines) { line in
                            let isCurrent = line.id == current
                            Text(line.text)
                                .font(.system(size: isCurrent ? 15 : 13, weight: isCurrent ? .bold : .medium))
                                .foregroundStyle(isCurrent ? Color.white : Color.white.opacity(0.35))
                                .blur(radius: isCurrent ? 0 : 0.4)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .id(line.id)
                                .onTapGesture { media.seek(to: line.time) }
                        }
                    }
                    .padding(.vertical, 40)
                    .animation(.spring(response: 0.35, dampingFraction: 0.85), value: current)
                }
                .onChange(of: current) { _, newValue in
                    guard let newValue else { return }
                    withAnimation(.spring(response: 0.45, dampingFraction: 0.9)) {
                        proxy.scrollTo(newValue, anchor: .center)
                    }
                }
                .onAppear {
                    if let current { proxy.scrollTo(current, anchor: .center) }
                }
            }
        }
        .mask(
            LinearGradient(colors: [.clear, .black, .black, .clear], startPoint: .top, endPoint: .bottom)
        )
    }
}

// MARK: - Agenda

@MainActor
struct CalendarWidget: View {
    @EnvironmentObject private var calendar: CalendarService

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(calendar.now, format: .dateTime.weekday(.wide).day().month(.wide))
                    .font(.system(size: 13, weight: .semibold))
                    .textCase(nil)
                Spacer()
                Button { calendar.openCalendarApp() } label: {
                    Image(systemName: "calendar")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.6))
                }
                .buttonStyle(PressableButtonStyle())
                .help("Ouvrir Calendrier")
            }

            if !calendar.isAuthorized {
                Spacer(minLength: 0)
                VStack(alignment: .leading, spacing: 6) {
                    Text(calendar.isDenied ? "Accès au calendrier refusé." : "Affichez vos prochains rendez-vous ici.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Button(calendar.isDenied ? "Ouvrir les réglages" : "Autoriser l'accès") {
                        calendar.isDenied ? calendar.openPrivacySettings() : calendar.requestAccess()
                    }
                    .buttonStyle(PillButtonStyle(tint: .blue))
                }
                Spacer(minLength: 0)
            } else if calendar.events.isEmpty {
                Spacer(minLength: 0)
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.seal.fill").foregroundStyle(.green)
                    Text("Rien de prévu aujourd'hui ni demain")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 7) {
                        ForEach(calendar.events) { EventRow(item: $0) }
                    }
                }
            }
        }
    }
}

@MainActor
struct EventRow: View {
    let item: CalendarItem

    var body: some View {
        HStack(spacing: 8) {
            Capsule()
                .fill(item.color)
                .frame(width: 3, height: 26)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.title)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                Text(item.timeDescription)
                    .font(.system(size: 10.5))
                    .foregroundStyle(item.isOngoing ? item.color : .secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            if let url = item.meetingURL {
                Button {
                    NSWorkspace.shared.open(url)
                } label: {
                    Label("Rejoindre", systemImage: "video.fill")
                        .labelStyle(.titleAndIcon)
                }
                .buttonStyle(PillButtonStyle(tint: .green))
            }
        }
    }
}

// MARK: - Météo

@MainActor
struct WeatherWidget: View {
    @EnvironmentObject private var weather: WeatherService

    var body: some View {
        VStack(spacing: 3) {
            if let w = weather.current {
                Image(systemName: w.symbol)
                    .symbolRenderingMode(.multicolor)
                    .font(.system(size: 28))
                    .frame(height: 32)
                Text("\(Int(w.temperature.rounded()))°")
                    .font(.system(size: 24, weight: .semibold, design: .rounded))
                Text(w.city)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text("↓\(Int(w.min.rounded()))°  ↑\(Int(w.max.rounded()))°")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            } else if let message = weather.errorMessage {
                Image(systemName: "cloud.slash.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(.white.opacity(0.4))
                Text(message)
                    .font(.system(size: 9.5))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                Button("Réessayer") { weather.refresh() }
                    .buttonStyle(PillButtonStyle())
            } else {
                ProgressView().controlSize(.small)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { weather.refresh() }
    }
}
