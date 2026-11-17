import Foundation
import Testing
@testable import MoonCore

struct VoiceAndPressureTests {
    @Test func englishAndSpanishCommandsNeedNoModeSelection() throws {
        #expect(NebulaRequest.resolve("Hola Nebula, puedes abrir YouTube.") == .command(.open(try #require(URL(string: "https://www.youtube.com")))))
        #expect(NebulaRequest.resolve("abre ejemplo punto com") == .command(.open(try #require(URL(string: "https://ejemplo.com")))))
        #expect(NebulaRequest.resolve("resume esta página") == .command(.summarize))
        #expect(NebulaRequest.resolve("cambia al espacio Trabajo") == .command(.switchSpace("Trabajo")))
        #expect(NebulaRequest.resolve("cierra todas las pestañas de YouTube") == .command(.closeMatching("youtube")))
        #expect(NebulaRequest.resolve("busca en Google conciertos en Madrid") == .command(.search("conciertos en Madrid")))
        #expect(NebulaRequest.resolve("abre javascript:alert(1)") == .unsupportedAddress)
    }

    @Test func focusedFieldsDictateOrdinarySpeechButNotBrowserCommands() {
        for words in ["Hello, see you tomorrow", "Hola, nos vemos mañana", "escribe hola", "type hello"] {
            #expect(NebulaIntent.shouldDictate(words))
        }
        for words in ["open YouTube", "abre YouTube", "nueva pestaña", "puedes abrir YouTube", "resume esta página", "busca hoteles"] {
            #expect(!NebulaIntent.shouldDictate(words))
        }
        #expect(NebulaIntent.dictationText("escribe Hola mundo.") == "Hola mundo")
        #expect(NebulaIntent.dictationText("type Hello world.") == "Hello world")
        #expect(NebulaRequest.resolve("no cierres mis pestañas") == .googleSearch("no cierres mis pestañas"))
    }

    @Test func shortPressureReadsAndHeldPressurePreviewsExactlyOnce() {
        var gesture = LinkPressureGesture()
        gesture.begin(at: 1)
        #expect(gesture.end(at: 1.2) == .insight)
        #expect(gesture.end(at: 1.3) == nil)
        gesture.begin(at: 2)
        #expect(gesture.hold(at: 2.5) == .preview)
        #expect(gesture.hold(at: 2.6) == nil)
        #expect(gesture.end(at: 2.8) == nil)
        gesture.begin(at: 3)
        #expect(gesture.end(at: 3.6) == .preview)
        gesture.begin(at: 4)
        gesture.cancel()
        #expect(gesture.end(at: 4.2) == nil)
    }
}
