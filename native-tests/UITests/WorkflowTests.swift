import XCTest

final class WorkflowTests: XCTestCase {
  @MainActor func testNativeActivityCycle() throws {
    let app = XCUIApplication()
    app.launchEnvironment["ADE_UI_TEST_RUN"] = UUID().uuidString
    app.launchArguments = ["-ade-locale", "es", "-ade-author", "Prueba nativa"]
    app.launch()
    app.activate()
    continueAfterFailure = false
    func button(_ name: String) -> XCUIElement {
      app.buttons.matching(NSPredicate(format: "identifier == %@ OR label ==[c] %@", name, name))
        .firstMatch
    }
    func click(_ name: String) {
      let b = button(name)
      XCTAssertTrue(
        b.waitForExistence(timeout: 10), "Missing button \(name)\n\(app.debugDescription)")
      b.click()
      app.activate()
    }
    func field(_ label: String, _ value: String) {
      let f = app.textFields[label == "Nombre" ? "field-name" : "field-email"].firstMatch
      XCTAssertTrue(
        f.waitForExistence(timeout: 5), "Missing field \(label)\n\(app.debugDescription)")
      f.click()
      f.typeKey("a", modifierFlags: .command)
      f.typeText(value)
    }
    func nav(_ title: String) {
      let ids = [
        "Clasificación": "classification", "Personas": "people", "Eventos": "events",
        "Resultados": "results", "Documentos": "documents", "Historial": "history",
      ]
      click("nav-" + ids[title]!)
    }
    func save() {
      click("sheet-save")
      XCTAssertTrue(app.sheets.firstMatch.waitForNonExistence(timeout: 10), app.debugDescription)
    }
    click("new-space")
    field("Nombre", "Prueba nativa")
    save()
    nav("Clasificación")
    click("add-component")
    field("Nombre", "Servicio")
    save()
    nav("Personas")
    click("add-person")
    field("Nombre", "Persona A")
    field("Correo", "ana@example.org")
    save()
    click("add-person")
    field("Nombre", "Persona B")
    save()
    nav("Eventos")
    click("event-new")
    field("Nombre", "Ciclo nativo")
    save()
    app.descendants(matching: .any)["event-actions"].firstMatch.click()
    app.buttons["Cambiar a: Programado"].click()
    app.descendants(matching: .any)["event-actions"].firstMatch.click()
    app.buttons["Voluntariado"].click()
    let candidate = app.buttons["volunteer-candidate"]
    XCTAssertTrue(candidate.waitForExistence(timeout: 5))
    candidate.click()
    app.buttons["Persona A"].click()
    click("Registrar interés")
    click("Seleccionar")
    app.descendants(matching: .any)["event-actions"].firstMatch.click()
    app.buttons["Asistencia"].click()
    let present = app.buttons["Presente · Persona A"].firstMatch
    XCTAssertTrue(present.waitForExistence(timeout: 5), app.debugDescription)
    present.click()
    nav("Resultados")
    XCTAssertTrue(
      app.staticTexts["100.0%"].firstMatch.waitForExistence(timeout: 5), app.debugDescription)
    nav("Documentos")
    click("document-new-template")
    save()
    let event = app.buttons["document-event"].firstMatch
    XCTAssertTrue(event.waitForExistence(timeout: 5))
    event.click()
    app.buttons["Ciclo nativo"].click()
    click("Generar vista previa")
    XCTAssertTrue(button("Guardar PDF…").waitForExistence(timeout: 10))
    let ready = NSPredicate(format: "enabled == true")
    expectation(for: ready, evaluatedWith: button("Guardar PDF…"))
    waitForExpectations(timeout: 15)
    let screenshot = XCTAttachment(screenshot: app.screenshot())
    screenshot.name = "Native document preview"
    screenshot.lifetime = .keepAlways
    add(screenshot)
    nav("Historial")
    let revision = app.buttons.matching(
      NSPredicate(format: "label BEGINSWITH %@", "Guardar plantilla")
    ).firstMatch
    XCTAssertTrue(revision.waitForExistence(timeout: 5), app.debugDescription)
    revision.click()
    XCTAssertTrue(app.staticTexts["Guardar plantilla"].firstMatch.waitForExistence(timeout: 5))
    let historyCapture = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
    historyCapture.name = "Paper - History selected"
    historyCapture.lifetime = .keepAlways
    add(historyCapture)
    app.terminate()
    app.launch()
    app.activate()
    let open = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "open-space-"))
      .firstMatch
    XCTAssertTrue(open.waitForExistence(timeout: 10))
    open.click()
    nav("Personas")
    XCTAssertTrue(
      app.staticTexts["Persona A"].firstMatch.waitForExistence(timeout: 10),
      "Native data must persist across launch")
    XCTAssertEqual(app.webViews.count, 0, "No web renderer")
  }

  @MainActor func testReferenceScreensAndUndo() throws {
    let app = XCUIApplication()
    app.launchEnvironment["ADE_UI_TEST_RUN"] = UUID().uuidString
    app.launchArguments = ["-ade-locale", "es", "-ade-author", "Prueba UX"]
    app.launch()
    app.activate()
    continueAfterFailure = false
    func click(_ id: String) {
      let b = app.buttons.matching(
        NSPredicate(format: "identifier == %@ OR label ==[c] %@", id, id)
      ).firstMatch
      XCTAssertTrue(b.waitForExistence(timeout: 10), app.debugDescription)
      b.click()
      app.activate()
    }
    func capture(_ name: String) {
      let attachment = XCTAttachment(screenshot: app.screenshot())
      attachment.name = name
      attachment.lifetime = .keepAlways
      add(attachment)
    }
    click("load-demo")
    XCTAssertTrue(app.buttons["nav-summary"].waitForExistence(timeout: 10))
    capture("Reference 4 - Overview")
    click("nav-events")
    XCTAssertTrue(app.buttons["event-row-event-0"].waitForExistence(timeout: 10))
    capture("Reference 2 - Events")
    click("event-row-event-0")
    XCTAssertTrue(app.staticTexts["86%"].waitForExistence(timeout: 10), app.debugDescription)
    capture("Reference 1 - Attendance")
    click("attendance-person-2-present")
    XCTAssertTrue(app.staticTexts["100%"].waitForExistence(timeout: 10))
    click("history-undo")
    XCTAssertTrue(app.staticTexts["86%"].waitForExistence(timeout: 10))
    click("history-redo")
    XCTAssertTrue(app.staticTexts["100%"].waitForExistence(timeout: 10))
    click("spaces-home")
    XCTAssertTrue(app.textFields["space-name"].waitForExistence(timeout: 10))
    capture("Reference 3 - Spaces")
    XCTAssertEqual(app.webViews.count, 0)
  }
  @MainActor func testPaperControlsAndEmptyCatalogLayout() throws {
    let app = XCUIApplication()
    app.launchEnvironment["ADE_UI_TEST_RUN"] = UUID().uuidString
    app.launchArguments = ["-ade-locale", "es", "-ade-author", "Prueba controles"]
    app.launch()
    app.activate()
    continueAfterFailure = false
    func click(_ id: String) {
      let button = app.buttons.matching(
        NSPredicate(format: "identifier == %@ OR label ==[c] %@", id, id)
      ).firstMatch
      XCTAssertTrue(button.waitForExistence(timeout: 10), app.debugDescription)
      button.click()
      app.activate()
    }
    func capture(_ name: String) {
      let attachment = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
      attachment.name = name
      attachment.lifetime = .keepAlways
      add(attachment)
    }
    click("new-space")
    let name = app.textFields["field-name"].firstMatch
    XCTAssertTrue(name.waitForExistence(timeout: 5))
    name.click()
    name.typeText("Catálogo vacío")
    click("sheet-save")
    XCTAssertTrue(app.sheets.firstMatch.waitForNonExistence(timeout: 10))
    for tab in ["classification", "periods"] {
      click("nav-" + tab)
      let title = app.staticTexts["SIN REGISTROS"].firstMatch
      XCTAssertTrue(title.waitForExistence(timeout: 5))
      XCTAssertGreaterThan(title.frame.width, 140, "Empty state must use the available width")
      XCTAssertLessThan(title.frame.height, 70, "Empty state must not wrap into a vertical strip")
      capture("Paper - Empty " + tab)
    }
    click("add-period")
    click("calendar-Desde")
    XCTAssertTrue(
      app.buttons["calendar-next-month"].waitForExistence(timeout: 5), app.debugDescription)
    click("calendar-next-month")
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone(secondsFromGMT: 0)!
    let next = cal.date(byAdding: .month, value: 1, to: Date())!
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "es")
    formatter.timeZone = cal.timeZone
    formatter.dateFormat = "LLLL yyyy"
    XCTAssertTrue(
      app.staticTexts[formatter.string(from: next).uppercased()].waitForExistence(timeout: 5))
    capture("Paper - Calendar")
    let firstNext = cal.date(from: cal.dateComponents([.year, .month], from: next))!
    formatter.dateFormat = "yyyy-MM-dd"
    let selectedDay = formatter.string(from: firstNext)
    click("calendar-day-" + selectedDay)
    XCTAssertEqual(app.textFields["Desde"].value as? String, selectedDay)
    click("calendar-Desde")
    XCTAssertTrue(app.buttons["calendar-next-month"].waitForExistence(timeout: 5))
    app.typeKey(.escape, modifierFlags: [])
    click("Cancelar")
    click("spaces-home")
    click("load-demo")
    for tab in [
      "people", "groups", "periods", "classification", "results", "documents", "history", "data",
      "conflicts", "rules",
    ] {
      click("nav-" + tab)
      XCTAssertEqual(app.popUpButtons.count, 0, "App pickers must use the paper controls")
      capture("Paper - " + tab)
    }
    click("nav-documents")
    let template = app.buttons.matching(
      NSPredicate(format: "identifier BEGINSWITH %@", "template-")
    ).firstMatch
    XCTAssertTrue(template.waitForExistence(timeout: 5))
    template.click()
    click("document-event")
    click("option-event-0")
    click("Resultados")
    XCTAssertTrue(app.buttons["option-period-demo"].waitForExistence(timeout: 5))
    capture("Paper - Result selector")
    click("option-period-demo")
    click("Generar vista previa")
    let save = app.buttons["GUARDAR PDF…"].firstMatch
    expectation(for: NSPredicate(format: "enabled == true"), evaluatedWith: save)
    waitForExpectations(timeout: 15)
    capture("Paper - Documents with PDF")
    click("Editar plantilla")
    capture("Paper - Template editor")
    click("Cancelar")
    click("Preferencias")
    click("Idioma")
    click("option-en")
    XCTAssertTrue(app.buttons["Language"].waitForExistence(timeout: 5))
    capture("Paper - Settings English")
    click("Language")
    click("option-es")
    XCTAssertEqual(app.webViews.count, 0)
  }

  @MainActor func testReducedMotionNavigationAndAttendance() throws {
    let app = XCUIApplication()
    app.launchEnvironment["ADE_UI_TEST_RUN"] = UUID().uuidString
    app.launchEnvironment["ADE_REDUCE_MOTION"] = "1"
    app.launchArguments = ["-ade-locale", "es", "-ade-author", "Prueba movimiento reducido"]
    app.launch()
    app.activate()
    continueAfterFailure = false
    func click(_ id: String) {
      let b = app.buttons[id].firstMatch
      XCTAssertTrue(b.waitForExistence(timeout: 10), app.debugDescription)
      b.click()
      app.activate()
    }
    click("load-demo")
    for tab in ["people", "classification", "groups", "periods", "events"] { click("nav-" + tab) }
    click("event-row-event-0")
    XCTAssertTrue(app.staticTexts["86%"].waitForExistence(timeout: 5))
    click("attendance-person-2-present")
    XCTAssertTrue(app.staticTexts["100%"].waitForExistence(timeout: 5))
    click("history-undo")
    XCTAssertTrue(app.staticTexts["86%"].waitForExistence(timeout: 5))
    let screenshot = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
    screenshot.name = "Reduced motion - stable attendance"
    screenshot.lifetime = .keepAlways
    add(screenshot)
    XCTAssertEqual(app.webViews.count, 0)
  }

}
