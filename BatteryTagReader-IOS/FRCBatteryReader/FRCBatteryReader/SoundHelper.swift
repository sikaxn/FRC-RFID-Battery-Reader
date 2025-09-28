//
//  SoundHelper.swift
//  FRCBatteryReader
//
//  Created by Nathan on 2025-09-28.
//


import Foundation
import AVFAudio
import QuartzCore

/// Maps each battery NoteType to the mp3 filename (WITHOUT extension).
/// Drop your 4 mp3 files into the target and ensure these names exist,
/// or change the mapping below to your actual filenames.
private let kChimeMap: [NoteType: String] = [
    .normal:   "chime-normal",
    .practice: "chime-practice",
    .scrap:    "chime-scrap",
    .other:    "chime-other",
]

/// Tiny, centralized audio helper. Keeps ContentView changes minimal.
final class SoundHelper {
    static let shared = SoundHelper()
    private var player: AVAudioPlayer?
    private var lastPlayAt: TimeInterval = 0
    /// Throttle multiple back-to-back plays (e.g., double reads) [seconds].
    private let minInterval: TimeInterval = 0.15

    private init() {
        // Use ambient so we respect the Silent switch and mix with other audio.
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.ambient, mode: .default, options: [.mixWithOthers])
        try? session.setActive(true)
    }

    /// Convenience to play based on a raw `n` value (0...3).
    @discardableResult
    func playForRawNote(_ raw: Int) -> Bool {
        let note = NoteType(rawValue: raw) ?? .normal
        return play(note: note)
    }

    /// Primary entry point used by ContentView. Returns true if a sound started.
    @discardableResult
    func play(note: NoteType) -> Bool {
        // Throttle rapid repeats
        let now = CACurrentMediaTime()
        guard now - lastPlayAt >= minInterval else { return false }
        lastPlayAt = now

        let name = kChimeMap[note] ?? "chime-normal"
        return play(resource: name, ext: "mp3")
    }

    /// If you prefer to pass the whole payload.
    @discardableResult
    func play(for payload: BatteryPayload) -> Bool {
        playForRawNote(payload.n)
    }

    // MARK: - Internals

    @discardableResult
    private func play(resource: String, ext: String) -> Bool {
        guard let url = Bundle.main.url(forResource: resource, withExtension: ext) else {
            #if DEBUG
            print("[SoundHelper] Missing resource: \(resource).\(ext)")
            #endif
            return false
        }
        do {
            // Recreate the player to avoid cutting off a previous long tail.
            player = try AVAudioPlayer(contentsOf: url)
            player?.prepareToPlay()
            player?.play()
            return true
        } catch {
            #if DEBUG
            print("[SoundHelper] AVAudioPlayer error: \(error)")
            #endif
            return false
        }
    }
}
