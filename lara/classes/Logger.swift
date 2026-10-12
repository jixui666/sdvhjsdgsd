//
//  Logger.swift
//  mowiwewgewawt
//  bacon why would you do that
//  teehee :3
//  yeah yeah teehee all you want 
//
//  I love that you just straight skidded this from jessi lmfao
//  skidding is my specialty.
//
//  Created by roooot on 15.11.25.
//

import Foundation
import Darwin
import Combine
import SwiftUI

let globallogger = Logger()

class Logger: ObservableObject {
    @Published var logs: [String] = []

    private var lastmessage: String?
    private var repeatCount = 0
    private var lastwasdivider = false
    private var pendingdivider = false
    private var stdoutpipe: Pipe?
    private var panding = ""
    private var ogstdout: Int32 = -1
    private var ogstderr: Int32 = -1
    private var logfileurl: URL?
    // Raw O_APPEND fd (not a FileHandle). The exploit's own C loggers
    // (utils.m / darksword.m) append to the same file with O_APPEND; a
    // FileHandle with a cached offset would overwrite their writes, so we
    // must append atomically here too.
    private var logfd: Int32 = -1
    private let nobullshitkey = "loggernobullshit"
    private let ignoredlogsubstrings = [
        "Faulty glyph",
        "outline detected - replacing with a space/null glyph",
        "Gesture:",
        "tcp_output [",
        "Error Domain=",
        "com.apple.UIKit.dragInitiation",
        "OSLOG",
        "_UISystemGestureGateGestureRecognizer",
        "NSError",
        "UITouch",
        "com.apple",
        "gestureRecognizers",
        "graph: {(",
        "UILongPressGestureRecognizer",
        "UIScrollViewPanGestureRecognizer",
        "UIScrollViewDelayedTouchesBeganGestureRecognizer",
        "_UISwipeActionPanGestureRecognizer",
        "_UISecondaryClickDriverGestureRecognizer",
        "SwiftUI.UIHostingViewDebugLayer",
        "ValueType:",
        "EventType:",
        "AttributeDataLength:",
        "AttributeData:",
        "SenderID:",
        "Timestamp:",
        "TransducerType:",
        "TransducerIndex:",
        "GenerationCount:",
        "WillUpdateMask:",
        "DidUpdateMask:",
        "Pressure:",
        "AuxiliaryPressure:",
        "TiltX:",
        "TiltY:",
        "MajorRadius:",
        "MinorRadius:",
        "Accuracy:",
        "Quality:",
        "Density:",
        "Irregularity:",
        "Range:",
        "Touch:",
        "Events:",
        "ChildEvents:",
        "DisplayIntegrated:",
        "BuiltIn:",
        "EventMask:",
        "ButtonMask:",
        "Flags:",
        "Identity:",
        "Twist:",
        "X:",
        "Y:",
        "Z:",
        "Total Latency:",
        "Timestamp type:",
        "lara[",
        "};",
        "NSLayoutConstraint",
        "   \"",
    ]

    init() {
        setuplogfile()
    }

    func log(_ message: String) {
        DispatchQueue.main.async {
            let dividersEnabled = !UserDefaults.standard.bool(forKey: self.nobullshitkey)
            if dividersEnabled && self.pendingdivider {
                self.divider()
                self.pendingdivider = false
            } else if !dividersEnabled {
                self.pendingdivider = false
                self.lastwasdivider = false
            }

            if message == self.lastmessage {
                self.repeatCount += 1
                if let lastIndex = self.logs.indices.last {
                    self.logs[lastIndex] = "\(message) (\(self.repeatCount + 1)x)"
                }
            } else {
                self.repeatCount = 0
                if dividersEnabled {
                    if self.lastwasdivider || self.logs.isEmpty {
                        self.logs.append(message)
                    } else {
                        self.logs[self.logs.count - 1] += "\n" + message
                    }
                } else {
                    self.logs.append(message)
                }
                self.lastmessage = message
            }

            self.lastwasdivider = false
        }

        appendtofile([message])
        emit(message)
    }

    func divider() {
        if UserDefaults.standard.bool(forKey: nobullshitkey) { return }
        DispatchQueue.main.async {
            self.lastwasdivider = true
            self.lastmessage = nil
            self.repeatCount = 0
        }
    }
    
    func enclosedlog(_ message: String) {
        if UserDefaults.standard.bool(forKey: nobullshitkey) {
            log(message)
            return
        }
        DispatchQueue.main.async {
            if !self.lastwasdivider && !self.logs.isEmpty {
                self.divider()
            }
            
            if self.lastwasdivider || self.logs.isEmpty {
                self.logs.append(message)
            } else {
                self.logs[self.logs.count - 1] += "\n" + message
            }
            
            self.lastwasdivider = false
            self.pendingdivider = true
        }
    }
    
    func flushdivider() {
        if UserDefaults.standard.bool(forKey: nobullshitkey) { return }
        DispatchQueue.main.async {
            if self.pendingdivider {
                self.divider()
                self.pendingdivider = false
            }
        }
    }

    func clear() {
        DispatchQueue.main.async {
            self.logs.removeAll()
            self.lastwasdivider = false
            self.pendingdivider = false
            self.lastmessage = nil
            self.repeatCount = 0
        }
        if let url = logfileurl {
            if logfd >= 0 { close(logfd) }
            // O_TRUNC keeps the same inode; an atomic write would swap the
            // inode and orphan the C-side O_APPEND fds.
            logfd = open(url.path, O_WRONLY | O_CREAT | O_TRUNC, 0o644)
        }
    }

    func capture() {
        if stdoutpipe != nil { return }
        reopenlogfileondemand()

        let pipe = Pipe()
        stdoutpipe = pipe

        ogstdout = dup(STDOUT_FILENO)
        ogstderr = dup(STDERR_FILENO)

        setvbuf(stdout, nil, _IOLBF, 0)
        setvbuf(stderr, nil, _IOLBF, 0)

        dup2(pipe.fileHandleForWriting.fileDescriptor, STDOUT_FILENO)
        dup2(pipe.fileHandleForWriting.fileDescriptor, STDERR_FILENO)

        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if data.isEmpty { return }
            guard let chunk = String(data: data, encoding: .utf8), !chunk.isEmpty else { return }
            self?.appendraw(chunk)
        }
    }

    func stopcapture() {
        guard let pipe = stdoutpipe else { return }
        pipe.fileHandleForReading.readabilityHandler = nil

        if ogstdout != -1 {
            dup2(ogstdout, STDOUT_FILENO)
            close(ogstdout)
            ogstdout = -1
        }
        if ogstderr != -1 {
            dup2(ogstderr, STDERR_FILENO)
            close(ogstderr)
            ogstderr = -1
        }

        try? pipe.fileHandleForWriting.close()
        try? pipe.fileHandleForReading.close()
        stdoutpipe = nil

        // Keep logfd open: the exploit's own C loggers keep appending to the
        // same file, and log()/direct writes must still reach the container
        // even while stdout capture is paused (e.g. app背景).
        if logfd >= 0 { fsync(logfd) }
    }

    private func appendraw(_ chunk: String) {
        var text = panding + chunk
        var lines = text.components(separatedBy: "\n")
        panding = lines.removeLast()
        if !lines.isEmpty {
            let filtered = lines.filter { !shouldignore($0) }
            DispatchQueue.main.async {
                self.logs.append(contentsOf: filtered)
            }
            // Write the container log with verbose remote-call chatter removed
            // ((pac)/signState/return-exception lines flood the file with ~10
            // lines per remote call and carry no actionable info).
            appendtofile(lines.filter { !fileShouldDrop($0) })
            for line in filtered {
                emit(line)
            }
        }
    }

    private func fileShouldDrop(_ message: String) -> Bool {
        let t = message.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.hasPrefix("(pac) ") { return true }
        if t.hasPrefix("(rc) signState") || t.hasPrefix("(rc) Replying remote call") ||
           t.hasPrefix("(rc) Return exception") || t.hasPrefix("(rc) Waiting for exception") ||
           t.hasPrefix("(rc) Exception received") || t.hasPrefix("(rc) pcAddr") {
            return true
        }
        return false
    }

    private func emit(_ message: String) {
        if shouldignore(message) { return }
        guard ogstdout != -1 else { return }
        let line = message + "\n"
        line.withCString { ptr in
            _ = Darwin.write(ogstdout, ptr, strlen(ptr))
        }
    }

    private func shouldignore(_ message: String) -> Bool {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return true
        }
        if isgarbageline(trimmed) {
            return true
        }
        for fragment in ignoredlogsubstrings {
            if message.contains(fragment) {
                return true
            }
        }
        return false
    }

    private func isgarbageline(_ line: String) -> Bool {
        let allowed = CharacterSet(charactersIn: "0123456789-+|*.:(){}[]/\\_ \t")
        if line.unicodeScalars.allSatisfy({ allowed.contains($0) }) {
            return true
        }
        if line == ")}" || line == ")}," || line == ")}))" {
            return true
        }
        return false
    }

    private func setuplogfile() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let url = docs.appendingPathComponent("lara.log")
        logfileurl = url

        // Fresh file per launch, then keep an O_APPEND fd so we never clobber
        // the C-side (utils.m / darksword.m) O_APPEND writers.
        if logfd >= 0 { close(logfd) }
        logfd = open(url.path, O_WRONLY | O_CREAT | O_TRUNC, 0o644)

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        let separator = "lara started: \(formatter.string(from: Date()))\nlog file: \(url.path)"
        self.logs = [separator]
        self.lastwasdivider = true

        appendtofile([separator])
        if logfd >= 0 { fsync(logfd) }
    }

    private func reopenlogfileondemand() {
        if logfd >= 0 { return }
        guard let url = logfileurl else { return }
        logfd = open(url.path, O_WRONLY | O_CREAT | O_APPEND, 0o644)
    }

    private func appendtofile(_ lines: [String]) {
        guard logfd >= 0 else { return }
        let trimmed = lines.filter { !$0.isEmpty }
        guard !trimmed.isEmpty else { return }
        let text = trimmed.joined(separator: "\n") + "\n"
        text.withCString { ptr in
            var remaining = strlen(ptr)
            var offset = 0
            while remaining > 0 {
                let written = Darwin.write(logfd, ptr + offset, remaining)
                if written <= 0 { break }
                offset += written
                remaining -= written
            }
        }
        fsync(logfd)
    }
}
