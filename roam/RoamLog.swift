//
//  RoamLog.swift
//  roam
//
//  Mirrors all stdout/stderr (every print()) to a file so logs can be inspected
//  outside Xcode. Enabled at launch. The file is truncated each run so it only
//  holds the current session.
//
//  Read it with:  tail -f /tmp/roam.log
//

import Foundation

enum RoamLog {
    static let logPath = "/tmp/roam.log"

    /// Redirects stdout + stderr to `logPath`. Call once, first thing at launch.
    static func start() {
        // Start each run with a fresh file.
        FileManager.default.createFile(atPath: logPath, contents: Data())

        // Redirect the C stdio streams that Swift's print()/NSLog write to.
        freopen(logPath, "a+", stdout)
        freopen(logPath, "a+", stderr)

        // Flush promptly so logs appear immediately (line-buffered stdout,
        // unbuffered stderr) instead of getting stuck in a block buffer.
        setvbuf(stdout, nil, _IOLBF, 0)
        setvbuf(stderr, nil, _IONBF, 0)

        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        print("—— roam log start (v\(version)) ——")
    }
}
