import Darwin
import Foundation
import QuartzCore
import os

/// Measures launch speed and prints it as "[Launch] …".
///
/// Times start when iOS created the app's process (read from the kernel), so they include
/// everything before our code runs. Lines go to the Xcode console and to the system log
/// (subsystem com.dhruv.Declutter, category Launch), so a launch from the Home Screen,
/// without Xcode attached, can be read in the Mac's Console app.
enum LaunchTimer {
    enum Stage: String, CaseIterable {
        case appInit = "App init"
        case firstFrame = "First intro frame"
        case animationStart = "Intro animation start"
        case animationEnd = "Intro finished"
    }

    /// Targets for the summary line.
    static let firstFrameTarget: TimeInterval = 400
    static let finishedTarget: TimeInterval = 1600

    nonisolated static let processStart: TimeInterval = {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
        guard sysctl(&mib, u_int(mib.count), &info, &size, nil, 0) == 0 else {
            return Date().timeIntervalSince1970
        }
        let start = info.kp_proc.p_starttime
        return TimeInterval(start.tv_sec) + TimeInterval(start.tv_usec) / 1_000_000
    }()

    private static let logger = Logger(subsystem: "com.dhruv.Declutter", category: "Launch")
    /// Milliseconds after process start for each stage reached so far.
    private static var reached: [Stage: TimeInterval] = [:]

    private static var sinceLaunch: TimeInterval {
        (Date().timeIntervalSince1970 - processStart) * 1000
    }

    /// Records a launch stage. When the intro finishes, prints the per-stage summary.
    static func mark(_ stage: Stage) {
        guard reached[stage] == nil else { return }
        let time = sinceLaunch
        reached[stage] = time
        output(String(format: "%@: %.0f ms after launch", stage.rawValue, time))
        if stage == .animationEnd { printSummary() }
    }

    /// Records any other launch event, such as data finishing loading.
    static func note(_ event: String) {
        output(String(format: "%@: %.0f ms after launch", event, sinceLaunch))
    }

    private static func printSummary() {
        guard let appInit = reached[.appInit], let firstFrame = reached[.firstFrame],
              let start = reached[.animationStart], let end = reached[.animationEnd] else { return }
        let lines = [
            "── Launch stages ──",
            String(format: "process start → App init:           %5.0f ms", appInit),
            String(format: "App init → first intro frame:       %5.0f ms", firstFrame - appInit),
            String(format: "first frame → animation start:      %5.0f ms", start - firstFrame),
            String(format: "animation start → animation end:    %5.0f ms", end - start),
            String(format: "first frame at %.0f ms (target ≤ %.0f) %@", firstFrame, firstFrameTarget,
                   firstFrame <= firstFrameTarget ? "✓" : "✗"),
            String(format: "intro finished at %.0f ms (target ≤ %.0f) %@", end, finishedTarget,
                   end <= finishedTarget ? "✓" : "✗"),
        ]
        for line in lines { output(line) }
    }

    private static func output(_ line: String) {
        print("[Launch] \(line)")
        logger.notice("[Launch] \(line, privacy: .public)")
    }
}

/// Calls back on the first screen refresh after it starts, which is when the frame drawn
/// before it has reached the display.
final class FirstFrameSignal: NSObject {
    private var link: CADisplayLink?
    private var callback: (() -> Void)?

    func wait(_ callback: @escaping () -> Void) {
        self.callback = callback
        let link = CADisplayLink(target: self, selector: #selector(tick))
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    @objc private func tick(_ link: CADisplayLink) {
        link.invalidate()
        self.link = nil
        callback?()
        callback = nil
    }
}
