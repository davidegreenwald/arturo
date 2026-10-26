import SwiftUI

// Arturo — a full-screen reader for a folder of photographs.
//
// One window, one model. The window is the show: it enters full screen when a
// folder is opened (ViewerActions) and leaves on escape, the system's own
// behaviour for a full-screen window.

@main
struct ArturoApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model = SlideshowModel()

    var body: some Scene {
        Window("Arturo", id: "viewer") {
            SlideshowView(model: model)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1440, height: 900)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Open Folder…") {
                    ViewerActions.openFolder(into: model)
                }
                .keyboardShortcut("o", modifiers: .command)
            }
            CommandMenu("Playback") {
                Button(model.isPlaying ? "Pause" : "Play") {
                    model.togglePlayback()
                }
                .keyboardShortcut("p", modifiers: .command)

                Divider()

                Button("Next Page") { model.nextPage() }
                    .keyboardShortcut(.rightArrow, modifiers: .command)
                Button("Previous Page") { model.previousPage() }
                    .keyboardShortcut(.leftArrow, modifiers: .command)

                Divider()

                Button("Toggle Full Screen") { FullScreenBridge.toggle() }
                    .keyboardShortcut("f", modifiers: [.command, .control])

                Divider()

                Toggle("Fill Frame", isOn: $model.fillsFrames)
                    .keyboardShortcut("f", modifiers: [.command, .shift])
            }
        }
    }
}
