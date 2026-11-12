import XCTest

final class LayoutTests: XCTestCase {
    private var app: XCUIApplication!
    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        addUIInterruptionMonitor(withDescription: "Bluetooth permission") { alert in
            if alert.buttons["Allow"].exists { alert.buttons["Allow"].tap(); return true }
            if alert.buttons["Permitir"].exists { alert.buttons["Permitir"].tap(); return true }
            return false
        }
    }
    private func screenshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
    private func reveal(_ element: XCUIElement) {
        for _ in 0..<6 {
            if element.isHittable { return }
            app.swipeUp()
        }
        XCTAssertTrue(element.isHittable)
    }
    func testLayoutMatrix() throws {
        for theme in ["Claro", "Escuro"] {
            for largeText in [false, true] {
                app.launchArguments = ["--ui-testing", "-sets", "2", "-repetitions", "2", "-restSeconds", "30", "-demoMode", "YES", "-theme", theme]
                if largeText { app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXL"] }
                app.launch()
                let prefix = "\(theme)-\(largeText ? "acessibilidade" : "padrao")"
                let bar = app.tabBars.firstMatch
                XCTAssertTrue(bar.waitForExistence(timeout: 10))
                XCTAssertEqual(bar.buttons.count, 4)
                for title in ["Treino", "Histórico", "Dispositivo", "Ajustes"] { XCTAssertTrue(bar.buttons[title].exists) }
                // A compatibility-mode app is rendered at legacy dimensions, not the device's logical width.
                XCTAssertGreaterThan(app.frame.width, 350)
                screenshot(prefix + "-treino-inativo")
                let primary = app.buttons["workout.primary"]
                reveal(primary)
                if !largeText {
                    let ring = app.otherElements["workout.progress"]
                    if ring.exists { XCTAssertLessThanOrEqual(ring.frame.maxY, bar.frame.minY) }
                    XCTAssertLessThanOrEqual(primary.frame.maxY, bar.frame.minY)
                }
                primary.tap()
                screenshot(prefix + "-treino-ativo")
                reveal(primary); primary.tap()
                screenshot(prefix + "-treino-pausado")
                primary.tap()
                let add = app.buttons["workout.addRepetition"]
                reveal(add); add.tap(); add.tap()
                let countdown = app.staticTexts["rest.countdown"]
                XCTAssertTrue(countdown.waitForExistence(timeout: 5))
                screenshot(prefix + "-descanso-ativo")
                let skip = app.buttons["rest.skip"]; reveal(skip); skip.tap()
                XCTAssertTrue(primary.waitForExistence(timeout: 5))
                let finish = app.buttons["workout.finish"]; reveal(finish); finish.tap()
                bar.buttons["Histórico"].tap()
                XCTAssertTrue(app.staticTexts["Treino interrompido"].waitForExistence(timeout: 5))
                screenshot(prefix + "-historico-parcial")
                bar.buttons["Dispositivo"].tap(); screenshot(prefix + "-dispositivo-demo")
                bar.buttons["Ajustes"].tap(); screenshot(prefix + "-ajustes")
                let toggle = app.switches["Modo demonstração"]
                reveal(toggle); toggle.tap()
                bar.buttons["Dispositivo"].tap(); screenshot(prefix + "-dispositivo-sem-conexao")
                app.terminate()
            }
        }
    }
}
