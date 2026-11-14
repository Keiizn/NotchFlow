import SwiftUI

@MainActor
struct HomeView: View {
    let ns: Namespace.ID
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        HStack(spacing: 14) {
            MediaPlayerView(ns: ns)
                .frame(width: 262)
            if settings.showCalendar {
                VerticalDivider()
                CalendarWidget()
                    .frame(maxWidth: .infinity)
            } else {
                Spacer(minLength: 0)
            }
            if settings.showWeather {
                VerticalDivider()
                WeatherWidget()
                    .frame(width: 100)
            }
        }
    }
}

// MARK: - Lecteur

@MainActor
struct MediaPlayerView: View {
    let ns: Namespace.ID
    @EnvironmentObject private var media: MediaController

    var body: some View {
        if let track = media.track {
            HStack(spacing: 12) {
                ArtworkView(image: media.artwork, cornerRadius: 14)
                    .frame(width: 86, height: 86)
                    .shadow(color: media.accentColor.opacity(0.45), radius: 14)
                    .scaleEffect(media.isPlaying ? 1 : 0.92)
                    .animation(.spring(response: 0.4, dampingFraction: 0.7), value: media.isPlaying)
                    .onTapGesture { media.openSourceApp() }
                    .help("Ouvrir \(media.source?.displayName ?? "le lecteur")")

                VStack(alignment: .leading, spacing: 2) {
                    Text(track.title)
                        .font(.system(size: 14, weight: .semibold))
                        .lineLimit(1)
                    Text(track.artist)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    Spacer(minLength: 4)

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

                    HStack(spacing: 22) {
                        control("backward.fill", size: 14) { media.previous() }
                        control(media.isPlaying ? "pause.fill" : "play.fill", size: 20) { media.playPause() }
                        control("forward.fill", size: 14) { media.next() }
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
