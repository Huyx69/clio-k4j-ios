import Foundation
import MediaPlayer
import UIKit

/// Pousse les données live dans MPNowPlayingInfoCenter.
/// CarPlay affiche automatiquement ces infos (titre, artiste, album, pochette)
/// sur l'écran "Lecture en cours" dès que l'app est source audio active.
/// Zéro entitlement CarPlay requis.
final class NowPlayingBridge {
    static let shared = NowPlayingBridge()
    private init() { configureRemoteCommands() }

    private var lastRenderAt: TimeInterval = 0

    func update(live: LiveData, trip: (km: Double, litres: Double, seconds: Int), fuelName: String) {
        let v = live.vit ?? 0
        let l100 = v > 5 ? live.lh / v * 100 : nil
        let heroL100 = l100.map { String(format: "%.1f L/100", min($0, 99.9)) }
            ?? String(format: "%.2f L/h", live.lh)

        let title: String = "\(heroL100)  ·  \(Int(v)) km/h"
        let moy = trip.km > 0.3 ? String(format: "%.1f", trip.litres / trip.km * 100) : "--.-"
        let artist: String = "Moy \(moy) L/100  ·  \(Int(live.rpm ?? 0)) tr/min  ·  Eau \(fmt(live.eau,0)) °C"
        let album: String  = "Batterie \(fmt(live.bat,1)) V  ·  Admission \(fmt(live.map,0)) kPa  ·  LTFT \(fmt(live.ltft,1))%"

        var info: [String: Any] = [
            MPMediaItemPropertyTitle: title,
            MPMediaItemPropertyArtist: artist,
            MPMediaItemPropertyAlbumTitle: album,
            MPMediaItemPropertyAlbumArtist: "Clio K4J",
            MPNowPlayingInfoPropertyIsLiveStream: true,
            MPNowPlayingInfoPropertyPlaybackRate: 1.0,
            MPMediaItemPropertyPlaybackDuration: 0.0,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: Double(trip.seconds),
        ]

        // Pochette dynamique : rendue au max 2×/s pour pas tuer la CPU.
        let now = CACurrentMediaTime()
        if now - lastRenderAt > 0.5 {
            lastRenderAt = now
            let image = DashboardRenderer.render(live: live, trip: trip, fuelName: fuelName)
            let art = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
            info[MPMediaItemPropertyArtwork] = art
        }

        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        MPNowPlayingInfoCenter.default().playbackState = .playing
    }

    func clear() {
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        MPNowPlayingInfoCenter.default().playbackState = .stopped
    }

    private func configureRemoteCommands() {
        let c = MPRemoteCommandCenter.shared()
        // On gère play/pause pour que CarPlay ne pense pas qu'on est muet.
        c.playCommand.isEnabled = true
        c.pauseCommand.isEnabled = true
        c.playCommand.addTarget { _ in .success }
        c.pauseCommand.addTarget { _ in .success }
        c.nextTrackCommand.isEnabled = true
        c.previousTrackCommand.isEnabled = true
        // Les boutons suivant/précédent font tourner le choix d'infos affichées
        // dans title/artist (vitesse+conso, température+papillon, O2+charge…).
        c.nextTrackCommand.addTarget { [weak self] _ in self?.cycleView(1); return .success }
        c.previousTrackCommand.addTarget { [weak self] _ in self?.cycleView(-1); return .success }
    }

    private(set) var view: Int = 0
    private func cycleView(_ delta: Int) {
        view = (view + delta + 3) % 3
    }

    private func fmt(_ v: Double?, _ d: Int) -> String {
        guard let v = v else { return "--" }
        return String(format: "%.\(d)f", v)
    }
}
