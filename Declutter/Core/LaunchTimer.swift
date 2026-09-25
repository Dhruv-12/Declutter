import Darwin
import Foundation
import QuartzCore

/// Measures launch speed and prints it to the Xcode console as "[Launch] …".
///
/// Times are measured from when iOS started the app's process (read from the kernel),
/// so they include everything before `main`, not just our own code.
enum LaunchTimer {
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

    nonisolated static func mark(_ event: String) {
        let milliseconds = (Date().timeIntervalSince1970 - processStart) * 1000
        print(String(format: "[Launch] %@: %.0f ms after launch", event, milliseconds))
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
