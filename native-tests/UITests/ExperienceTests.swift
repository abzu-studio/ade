import XCTest
import AppKit

final class ExperienceTests: XCTestCase {
  @MainActor private func launch(welcome: Bool = false) -> XCUIApplication {
    let app = XCUIApplication()
    app.launchEnvironment["ADE_UI_TEST_RUN"] = UUID().uuidString
    if welcome { app.launchEnvironment["ADE_TEST_WELCOME"] = "1" }
    app.launchArguments = ["-ade-locale", "es", "-ade-author", "Prueba de experiencia"]
    app.launch()
    app.activate()
    continueAfterFailure = false
    return app
  }
  @MainActor private func click(_ app: XCUIApplication, _ id: String) {
    let button = app.buttons.matching(
      NSPredicate(format: "identifier == %@ OR label ==[c] %@", id, id)
    ).firstMatch
    XCTAssertTrue(button.waitForExistence(timeout: 10), app.debugDescription)
    // macOS may report off-screen custom buttons as hittable. Reveal the row
    // inside its scroll view before clicking, including after sheet dismissal.
    for scroll in app.scrollViews.allElementsBoundByIndex {
      guard scroll.buttons.matching(identifier: button.identifier).count > 0 else { continue }
      for _ in 0..<4 {
        let visible = scroll.frame.insetBy(dx: 0, dy: 8)
        if visible.contains(button.frame) { break }
        scroll.scroll(byDeltaX: 0, deltaY: visible.midY - button.frame.midY)
      }
    }
    button.click()
    app.activate()
  }
  @MainActor private func text(_ app: XCUIApplication, _ id: String) -> String {
    let element = app.staticTexts[id]
    XCTAssertTrue(element.waitForExistence(timeout: 5), app.debugDescription)
    return (element.value as? String) ?? element.label
  }
  @discardableResult
  @MainActor private func capture(_ app: XCUIApplication, _ name: String) -> XCUIScreenshot {
    // Wait for the intentional 650 ms art dissolve, not for the continuous Canvas to become idle.
    RunLoop.current.run(until: Date().addingTimeInterval(0.85))
    let screenshot = app.windows.firstMatch.screenshot()
    let image = XCTAttachment(screenshot: screenshot)
    image.name = name
    image.lifetime = .keepAlways
    add(image)
    return screenshot
  }

  @MainActor private func assertTide(_ first: XCUIScreenshot, _ second: XCUIScreenshot, moving: Bool,
                                      region: CGRect = CGRect(x: 0.35, y: 0.66, width: 0.55, height: 0.24)) {
    guard let a = NSBitmapImageRep(data: first.pngRepresentation),
          let b = NSBitmapImageRep(data: second.pngRepresentation) else {
      XCTFail("Unable to read rendered frames"); return
    }
    XCTAssertEqual(a.pixelsWide, b.pixelsWide)
    XCTAssertEqual(a.pixelsHigh, b.pixelsHigh)
    var difference = 0.0
    var samples = 0
    // Sample the central background: live reflections must not be confined to the margins.
    for y in stride(from: Int(Double(a.pixelsHigh) * region.minY), to: Int(Double(a.pixelsHigh) * region.maxY), by: 4) {
      for x in stride(from: Int(Double(a.pixelsWide) * region.minX), to: Int(Double(a.pixelsWide) * region.maxX), by: 4) {
        guard let c = a.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB),
              let d = b.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
        difference += abs(c.redComponent - d.redComponent) + abs(c.greenComponent - d.greenComponent)
          + abs(c.blueComponent - d.blueComponent)
        samples += 3
      }
    }
    XCTAssertGreaterThan(samples, 0)
    let average = difference / Double(max(1, samples))
    if moving {
      XCTAssertGreaterThan(average, 0.0005, "The live layer must visibly evolve between frames (delta: \(average))")
    } else {
      XCTAssertLessThan(average, 0.0002, "Motion disabled must render a stable field (delta: \(average))")
    }
  }

  @MainActor func testDocumentPreviewInvalidatesAfterUndo() {
    let app = launch()
    click(app, "load-demo")
    click(app, "nav-documents")
    let template = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "template-")).firstMatch
    XCTAssertTrue(template.waitForExistence(timeout: 5))
    template.click()
    click(app, "Editar plantilla")
    click(app, "sheet-save")
    XCTAssertTrue(app.sheets.firstMatch.waitForNonExistence(timeout: 10))
    click(app, "document-event")
    click(app, "Lab 4 · PCR")
    click(app, "Generar vista previa")
    let save = app.buttons.matching(NSPredicate(format: "label ==[c] %@", "Guardar PDF…")).firstMatch
    XCTAssertTrue(save.waitForExistence(timeout: 10))
    let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: save)
    XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 15), .completed)
    click(app, "history-undo")
    let invalidated = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == false"), object: save)
    XCTAssertEqual(XCTWaiter.wait(for: [invalidated], timeout: 10), .completed,
                   "A PDF from an obsolete revision must not remain exportable")
  }

  @MainActor func testAudiovisualOpeningReplayAndPersistence() {
    let app = launch(welcome: true)
    XCTAssertTrue(app.buttons["welcome-skip"].waitForExistence(timeout: 5), app.debugDescription)
    XCTAssertFalse(app.textFields["welcome-space-name"].exists, "Opening must not be a setup menu")
    XCTAssertFalse(app.buttons["load-demo"].exists, "Workspace hidden during ident")
    capture(app, "Opening - Gathering")
    click(app, "opening-sound")
    XCTAssertTrue(
      app.buttons["load-demo"].waitForExistence(timeout: 15), "Sequence enters app automatically")
    XCTAssertEqual(
      app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "open-space-")).count, 0)
    click(app, "load-demo")
    click(app, "Preferencias")
    let draft = app.textFields["settings-space-name"]
    draft.click()
    draft.typeKey("a", modifierFlags: .command)
    draft.typeText("Borrador sin guardar")
    click(app, "replay-welcome")
    XCTAssertTrue(app.buttons["welcome-skip"].waitForExistence(timeout: 5), app.debugDescription)
    XCTAssertTrue(
      app.buttons["opening-sound"].label.localizedCaseInsensitiveContains("desactivado"),
      "Mute persists across replays")
    click(app, "welcome-skip")
    XCTAssertEqual(draft.value as? String, "Borrador sin guardar", "Replay must preserve draft")
    app.terminate()
    app.launch()
    app.activate()
    XCTAssertTrue(app.buttons["new-space"].waitForExistence(timeout: 10))
    XCTAssertFalse(app.buttons["welcome-skip"].exists, "Opening is shown once")
    XCTAssertEqual(app.webViews.count, 0)
  }

  @MainActor func testSkipWelcomeAndReducedMotion() {
    let app = XCUIApplication()
    app.launchEnvironment["ADE_UI_TEST_RUN"] = UUID().uuidString
    app.launchEnvironment["ADE_TEST_WELCOME"] = "1"
    app.launchEnvironment["ADE_REDUCE_MOTION"] = "1"
    app.launchArguments = ["-ade-locale", "es"]
    app.launch()
    app.activate()
    continueAfterFailure = false
    XCTAssertTrue(app.buttons["welcome-skip"].waitForExistence(timeout: 5), app.debugDescription)
    capture(app, "Opening - Reduced motion")
    click(app, "welcome-skip")
    XCTAssertTrue(app.buttons["new-space"].waitForExistence(timeout: 5))
    XCTAssertEqual(
      app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "open-space-")).count, 0)
    app.terminate()
    app.launch()
    app.activate()
    XCTAssertTrue(app.buttons["new-space"].waitForExistence(timeout: 10))
    XCTAssertFalse(app.buttons["welcome-skip"].exists)
  }

  @MainActor func testIndividualAttendanceBreakdown() {
    let app = launch()
    click(app, "load-demo")
    click(app, "nav-people")
    click(app, "person-attendance-person-0")
    XCTAssertEqual(text(app, "person-report-total"), "100.0%")
    XCTAssertEqual(text(app, "person-report-component-laboratory"), "100.0%")
    XCTAssertEqual(text(app, "person-report-category-practice"), "100.0%")
    XCTAssertEqual(text(app, "person-report-uncategorized-laboratory"), "—")
    capture(app, "Individual attendance - components and categories")
    click(app, "person-report-component")
    click(app, "Seminario")
    XCTAssertEqual(text(app, "person-report-component-seminar"), "—")
    XCTAssertEqual(
      text(app, "person-report-total"), "100.0%",
      "Component focus does not silently redefine overall")
    click(app, "person-report-period")
    click(app, "Período ago–dic 2026")
    XCTAssertEqual(text(app, "person-report-total"), "100.0%")
    click(app, "person-report-close")
    click(app, "nav-results")
    click(app, "result-person-person-2")
    XCTAssertEqual(text(app, "person-report-total"), "0.0%")
    click(app, "person-report-close")
    click(app, "result-person-person-4")
    XCTAssertEqual(text(app, "person-report-total"), "—", "Excused never becomes zero percent")
    click(app, "person-report-close")
  }

  @MainActor func testDayThemesPreserveDraftAndPersist() {
    let app = launch()
    XCTAssertEqual(app.buttons["theme-indigo"].value as? String, "Seleccionado")
    capture(app, "Indigo - spaces")
    click(app, "load-demo")
    capture(app, "Indigo - overview")
    click(app, "nav-events")
    capture(app, "Indigo - events")
    click(app, "event-row-event-0")
    capture(app, "Indigo - attendance")
    XCTAssertTrue(app.buttons["attendance-person-0-pending"].exists)
    click(app, "Preferencias")
    let draft = app.textFields["settings-space-name"]
    draft.click()
    draft.typeKey("a", modifierFlags: .command)
    draft.typeText("Tema con borrador")
    click(app, "theme-graphite")
    XCTAssertEqual(
      draft.value as? String, "Tema con borrador", "Switching appearance must not recreate a form")
    XCTAssertEqual(app.buttons["theme-graphite"].value as? String, "Seleccionado")
    capture(app, "Graphite - preferences")
    click(app, "nav-summary")
    capture(app, "Graphite - overview")
    click(app, "nav-events")
    capture(app, "Graphite - events")
    click(app, "event-row-event-0")
    capture(app, "Graphite - attendance")
    click(app, "attendance-person-0-pending")
    click(app, "history-undo")
    XCTAssertTrue(app.staticTexts["86%"].waitForExistence(timeout: 5))
    click(app, "spaces-home")
    capture(app, "Graphite - spaces")
    app.terminate()
    app.launch()
    app.activate()
    XCTAssertTrue(app.buttons["theme-graphite"].waitForExistence(timeout: 10))
    XCTAssertEqual(
      app.buttons["theme-graphite"].value as? String, "Seleccionado",
      "Day theme persists across launch")
    XCTAssertEqual(
      app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "theme-")).count, 4)
    XCTAssertEqual(app.webViews.count, 0)
  }

  @MainActor func testNightThemesAndControls() {
    let app = launch()
    click(app, "theme-night-indigo")
    capture(app, "Night Indigo - spaces")
    click(app, "load-demo")
    for section in ["summary", "people", "groups", "periods", "classification", "events",
                    "results", "documents", "history", "data", "conflicts", "rules"] {
      click(app, "nav-" + section)
      capture(app, "Night Indigo - " + section)
    }
    click(app, "nav-events")
    click(app, "event-new")
    XCTAssertTrue(app.sheets.firstMatch.waitForExistence(timeout: 5))
    capture(app, "Night Indigo - event editor")
    click(app, "Cancelar")
    click(app, "event-row-event-0")
    capture(app, "Night Indigo - attendance")
    click(app, "attendance-person-0-absent")
    XCTAssertTrue(app.staticTexts["71%"].waitForExistence(timeout: 5))
    click(app, "history-undo")
    XCTAssertTrue(app.staticTexts["86%"].waitForExistence(timeout: 5))
    click(app, "Preferencias")
    let draft = app.textFields["settings-space-name"]
    draft.click()
    draft.typeKey("a", modifierFlags: .command)
    draft.typeText("Borrador nocturno")
    click(app, "theme-night-graphite")
    XCTAssertEqual(draft.value as? String, "Borrador nocturno")
    capture(app, "Night Graphite - preferences")
    click(app, "replay-welcome")
    XCTAssertTrue(app.buttons["welcome-skip"].waitForExistence(timeout: 5))
    capture(app, "Night Graphite - opening")
    click(app, "welcome-skip")
    XCTAssertEqual(draft.value as? String, "Borrador nocturno")
    click(app, "nav-summary")
    capture(app, "Night Graphite - overview")
    click(app, "nav-events")
    capture(app, "Night Graphite - events")
    click(app, "event-row-event-0")
    capture(app, "Night Graphite - attendance")
    click(app, "spaces-home")
    capture(app, "Night Graphite - spaces")
    app.terminate()
    app.launchEnvironment["ADE_REDUCE_MOTION"] = "1"
    app.launch()
    app.activate()
    XCTAssertTrue(app.buttons["theme-night-graphite"].waitForExistence(timeout: 10))
    XCTAssertEqual(app.buttons["theme-night-graphite"].value as? String, "Seleccionado")
    capture(app, "Night Graphite - reduced motion and persistence")
    click(app, "theme-indigo")
    XCTAssertEqual(app.buttons["theme-indigo"].value as? String, "Seleccionado")
    XCTAssertEqual(app.webViews.count, 0)
  }

  @MainActor func testTidalLayerThemesAndLayout() {
    let app = launch()
    click(app, "load-demo")
    click(app, "spaces-home")
    for theme in ["indigo", "graphite", "night-indigo", "night-graphite"] {
      click(app, "theme-" + theme)
      capture(app, "Tide " + theme + " spaces")
      app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "open-space-")).firstMatch.click()
      app.activate()
      capture(app, "Tide " + theme + " summary")
      let preferences = app.buttons.matching(NSPredicate(format: "label ==[c] %@", "Preferencias")).firstMatch
      XCTAssertLessThan(app.windows.firstMatch.frame.maxY - preferences.frame.maxY, 80,
                        "Sidebar must reach the bottom without a reserved decorative footer")
      click(app, "nav-events")
      let row = app.buttons["event-row-event-0"]
      XCTAssertTrue(row.waitForExistence(timeout: 5))
      let before = row.frame
      let first = capture(app, "Tide " + theme + " events A")
      let accentBefore = app.buttons["event-new"].screenshot()
      RunLoop.current.run(until: Date().addingTimeInterval(2))
      let second = capture(app, "Tide " + theme + " events B")
      assertTide(first, second, moving: true)
      assertTide(first, second, moving: true, region: CGRect(x: 0.025, y: 0.15, width: 0.12, height: 0.62))
      assertTide(accentBefore, app.buttons["event-new"].screenshot(), moving: true,
                 region: CGRect(x: 0.05, y: 0.05, width: 0.9, height: 0.9))
      XCTAssertEqual(row.frame, before, "Ambient animation must never move a control")
      click(app, "event-row-event-0")
      capture(app, "Tide " + theme + " attendance")
      XCTAssertTrue(app.staticTexts["86%"].exists)
      click(app, "spaces-home")
    }
  }

  @MainActor func testTidalCompactAndStatic() {
    let app = launch()
    click(app, "theme-night-graphite")
    click(app, "load-demo")
    click(app, "spaces-home")
    app.terminate()
    app.launchEnvironment["ADE_TEST_COMPACT"] = "1"
    app.launch()
    app.activate()
    XCTAssertTrue(app.buttons["load-demo"].waitForExistence(timeout: 10))
    XCTAssertLessThanOrEqual(app.windows.firstMatch.frame.width, 1162)
    XCTAssertLessThanOrEqual(app.windows.firstMatch.frame.height, 754)
    capture(app, "Tide compact spaces")
    XCTAssertTrue(app.buttons["load-demo"].isHittable)
    XCTAssertTrue(app.textFields["space-name"].isHittable)
    app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "open-space-")).firstMatch.click()
    app.activate()
    click(app, "nav-events")
    click(app, "event-row-event-0")
    capture(app, "Tide compact attendance")
    click(app, "attendance-person-0-pending")
    click(app, "history-undo")
    XCTAssertTrue(app.staticTexts["86%"].waitForExistence(timeout: 5))
    click(app, "Preferencias")
    let motion = app.checkBoxes["ambient-motion"]
    XCTAssertTrue(motion.waitForExistence(timeout: 5))
    motion.click()
    app.activate()
    click(app, "nav-events")
    let first = capture(app, "Tide static A")
    let accentBefore = app.buttons["event-new"].screenshot()
    RunLoop.current.run(until: Date().addingTimeInterval(2))
    let second = capture(app, "Tide static B")
    assertTide(first, second, moving: false)
    assertTide(first, second, moving: false, region: CGRect(x: 0.025, y: 0.15, width: 0.12, height: 0.62))
    assertTide(accentBefore, app.buttons["event-new"].screenshot(), moving: false,
               region: CGRect(x: 0.05, y: 0.05, width: 0.9, height: 0.9))
  }

  @MainActor func testSectionAtmospheres() {
    let app = launch()
    click(app, "load-demo")
    for section in [
      "summary", "people", "groups", "periods", "classification", "events", "results", "documents",
      "history", "data", "conflicts", "rules",
    ] {
      click(app, "nav-" + section)
      capture(app, "Scene - " + section)
    }
    click(app, "Preferencias")
    capture(app, "Scene - settings")
    click(app, "nav-events")
    click(app, "event-row-event-0")
    capture(app, "Scene - attendance")
    click(app, "event-actions")
    click(app, "Voluntariado")
    capture(app, "Scene - volunteers")
    click(app, "event-actions")
    click(app, "Contexto e historial")
    capture(app, "Scene - context")
    click(app, "spaces-home")
    capture(app, "Scene - spaces")
    XCTAssertEqual(app.webViews.count, 0)
  }
  @MainActor func testQuickOpenAndKeyboardAttendance() {
    let app = launch()
    click(app, "load-demo")
    app.typeKey("k", modifierFlags: .command)
    let search = app.textFields["quick-open-search"]
    XCTAssertTrue(search.waitForExistence(timeout: 5), app.debugDescription)
    search.typeText("lab 4")
    XCTAssertTrue(app.buttons["quick-open-event-event-0"].waitForExistence(timeout: 5))
    capture(app, "Rewrite - Quick Open")
    search.typeKey(.return, modifierFlags: [])
    XCTAssertTrue(app.buttons["attendance-row-person-2"].waitForExistence(timeout: 5))
    click(app, "attendance-row-person-2")
    app.typeKey("p", modifierFlags: [])
    XCTAssertTrue(app.staticTexts["100%"].waitForExistence(timeout: 8), app.debugDescription)
    app.typeKey("a", modifierFlags: [])
    XCTAssertTrue(app.staticTexts["86%"].waitForExistence(timeout: 8), app.debugDescription)
    XCTAssertEqual(app.buttons["attendance-person-3-absent"].value as? String, "Seleccionado")
    capture(app, "Rewrite - Keyboard attendance")
    app.typeKey("k", modifierFlags: .command)
    XCTAssertTrue(search.waitForExistence(timeout: 5))
    search.typeText("Persona 01")
    search.typeKey(.return, modifierFlags: [])
    XCTAssertTrue(app.staticTexts["person-report-total"].waitForExistence(timeout: 5))
    XCTAssertEqual(text(app, "person-report-total"), "100.0%")
    click(app, "person-report-close")
    app.typeKey(.escape, modifierFlags: [])
    XCTAssertTrue(search.waitForNonExistence(timeout: 5))
    app.typeKey("7", modifierFlags: .command)
    XCTAssertTrue(app.buttons["result-person-person-0"].waitForExistence(timeout: 8))
    XCTAssertEqual(app.webViews.count, 0)
  }

}
