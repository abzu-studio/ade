import XCTest

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
  @MainActor private func capture(_ app: XCUIApplication, _ name: String) {
    // Wait for the intentional 650 ms art dissolve, not for the continuous Canvas to become idle.
    RunLoop.current.run(until: Date().addingTimeInterval(0.85))
    let image = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
    image.name = name
    image.lifetime = .keepAlways
    add(image)
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
      click(app, "nav-events")
      let row = app.buttons["event-row-event-0"]
      XCTAssertTrue(row.waitForExistence(timeout: 5))
      let before = row.frame
      capture(app, "Tide " + theme + " events A")
      RunLoop.current.run(until: Date().addingTimeInterval(2))
      capture(app, "Tide " + theme + " events B")
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
    capture(app, "Tide static A")
    RunLoop.current.run(until: Date().addingTimeInterval(2))
    capture(app, "Tide static B")
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
}
