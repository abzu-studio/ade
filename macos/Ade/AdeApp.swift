import SwiftUI

@main struct AdeApp: App {
  @NSApplicationDelegateAdaptor(AdeAppDelegate.self) private var appDelegate
  @State private var model: AppModel
  init() {
    Enki.registerFonts()
    var testDirectory: URL?
    #if DEBUG
      if let run = ProcessInfo.processInfo.environment["ADE_UI_TEST_RUN"] {
        testDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(
          "AdeUITests-" + run, isDirectory: true)
      }
    #endif
    _model = State(initialValue: AppModel(directory: testDirectory))
  }
  var body: some Scene {
    Window("Adê", id: "workspace") {
      LaunchExperience().modifier(MotionAccessibility()).buttonStyle(ActionLink()).textFieldStyle(
        PaperFieldStyle()
      ).toggleStyle(
        PaperToggleStyle()
      ).preferredColorScheme(DayAppearance.shared.theme.isNight ? .dark : .light).environment(model).environment(
        \.locale, Locale(identifier: model.locale)
      )
      .defaultAppStorage(DayAppearance.shared.preferenceStore)
      .onAppear {
        appDelegate.model = model
        DayAppearance.shared.applyDockIcon()
        #if DEBUG
          if ProcessInfo.processInfo.environment["ADE_UI_TEST_RUN"] != nil,
            ProcessInfo.processInfo.environment["ADE_TEST_COMPACT"] == "1" {
            DispatchQueue.main.async {
              NSApplication.shared.windows.first { $0.identifier?.rawValue == "workspace" }?
                .setContentSize(NSSize(width: 1160, height: 720))
            }
          }
        #endif
      }
      .onChange(of: DayAppearance.shared.theme) { DayAppearance.shared.applyDockIcon() }.tint(
        Enki.accent
      ).font(
        .custom("Inter-Regular", size: 13)
      ).frame(minWidth: 1160, minHeight: 720)
    }.defaultSize(width: 1280, height: 720)
      .commands {
        CommandGroup(replacing: .newItem) {
          Button(model.t("Importar archivo…", "Import workspace…")) {
            Task { await model.importWorkspace() }
          }.keyboardShortcut("i", modifiers: [.command, .shift]).disabled(
            model.busy || model.pending != nil)
          Button(model.t("Exportar archivo…", "Export workspace…")) { model.exportWorkspace() }
            .keyboardShortcut("e", modifiers: [.command, .shift])
        }
        CommandGroup(after: .appInfo) {
          Button(model.t("Configuración de Adê", "Adê Settings")) { model.navigate(.settings) }
            .keyboardShortcut(",")
        }
      }
  }
}
struct WorkspaceView: View {
  @Environment(AppModel.self) private var model
  @State private var newSpace = false
  @State private var repair = false
  @Environment(\.paperReduceMotion) private var reducedMotion
  @Namespace private var navigationInk
  private var atmosphere: PaperScene {
    if model.showSpaces || model.space == nil { return .spaces }
    if model.section == .events, model.selectedEvent != nil {
      return model.eventTab == 0 ? .attendance : model.eventTab == 1 ? .volunteers : .context
    }
    return PaperScene(rawValue: model.section.rawValue) ?? .summary
  }
  var body: some View {
    VStack(spacing: 0) {
      if let pending = model.pending, !model.busy {
        HStack {
          Text(model.t("Cambios pendientes de guardar.", "Unsaved changes."))
          Button(model.t("Reintentar", "Retry")) { Task { _ = await model.commit(pending) } }
          Button(model.t("Exportar copia…", "Export copy…")) { model.exportWorkspace() }
        }.padding(12)
      }
      if model.unreadable {
        HStack {
          Text(model.t("No se pudo leer el archivo local.", "The local file could not be read."))
          Button(model.t("Restaurar copia anterior…", "Restore previous backup…")) { repair = true }
          Button(model.t("Reintentar", "Retry")) { Task { await model.load() } }
        }.padding(12)
      }
      if model.loading {
        ProgressView(model.t("Abriendo archivo local…", "Opening local workspace…")).frame(
          maxWidth: .infinity, maxHeight: .infinity)
      } else if model.showSpaces || model.space == nil {
        SpacesHomeView(advanced: { newSpace = true })
      } else {
        HStack(spacing: 0) {
          sidebar.frame(width: 190)
          Rectangle().fill(Enki.rule).frame(width: 0.5)
          VStack(spacing: 0) {
            breadcrumb
            PaperRule()
            if model.branch?.conflicted == true {
              HStack {
                MicroLabel(
                  text: model.t("Versiones divergentes conservadas", "Divergent versions preserved")
                )
                Spacer()
                Button(model.t("Resolver →", "Resolve →")) { model.navigate(.conflicts) }
                  .buttonStyle(ActionLink())
              }.padding(14).background(Enki.side)
            }
            content.frame(maxWidth: .infinity, maxHeight: .infinity)
              .modifier(PaperArrival(trigger: model.section.rawValue))
          }
        }
      }
    }.modifier(PaperAmbientLayout(scene: atmosphere))
      .background(Enki.paper).foregroundStyle(Enki.ink)
      .overlay(alignment: .top) { PaperBusyIndicator(busy: model.busy) }
      .overlay { Rectangle().strokeBorder(Enki.rule, lineWidth: 0.5) }
      .modifier(PaperElevation())
      .padding(18).background(Enki.outer)
      .environment(\.paperScene, atmosphere)
      .sheet(isPresented: $newSpace) { SpaceEditor() }
      .confirmationDialog(
        model.t("¿Restaurar la copia anterior?", "Restore previous backup?"), isPresented: $repair,
        titleVisibility: .visible
      ) {
        Button(model.t("Restaurar y conservar archivo dañado", "Restore and retain damaged file")) {
          Task { await model.repairFromBackup() }
        }
      } message: {
        Text(
          model.t(
            "El archivo actual se conservará con otro nombre. Se restaurará la copia anterior validada.",
            "The current file will be kept under a recovery filename. The validated previous backup will be restored."
          ))
      }
      .alert(
        model.t("No se pudo completar la acción", "Unable to complete action"),
        isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })
      ) {
        Button("OK") { model.error = nil }
      } message: {
        Text(model.error ?? "")
      }
  }
  private var sidebar: some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack {
        Text("Adê").font(.custom(Enki.display, size: 24)).foregroundStyle(Enki.brand)
        Spacer()
        Text("LOCAL").font(.custom(Enki.mono, size: 8)).foregroundStyle(.secondary)
      }.padding(.horizontal, 18).padding(.top, 24).padding(.bottom, 16)
      Button {
        model.showSpaces = true
      } label: {
        VStack(alignment: .leading, spacing: 5) {
          Text(model.t("ESPACIO", "SPACE")).font(.custom(Enki.mono, size: 8)).tracking(1)
            .foregroundStyle(Enki.accent)
          Text((model.space?.name ?? "ADÊ").uppercased()).font(.custom(Enki.condensed, size: 17))
            .lineLimit(2)
        }.frame(maxWidth: .infinity, alignment: .leading).padding(10)
          .background(Enki.paper).overlay { Rectangle().stroke(Enki.rule, lineWidth: 0.5) }
      }.buttonStyle(.plain).padding(.horizontal, 12)
      ScrollView {
        VStack(spacing: 0) {
          ForEach(AppSection.navigation) { section in
            Button {
              model.navigate(section)
            } label: {
              HStack(spacing: 11) {
                Text(section.number).font(.custom(Enki.mono, size: 8)).foregroundStyle(
                  model.section == section ? Enki.onDark.opacity(0.8) : Enki.ink.opacity(0.55)
                )
                .frame(width: 12)
                Text(section.title(model).uppercased()).font(.custom(Enki.condensed, size: 16))
                  .lineLimit(1)
                Spacer(minLength: 0)
              }.padding(.leading, 10).padding(.trailing, 8).frame(height: 30)
                .foregroundStyle(model.section == section ? Enki.onDark : Enki.ink)
                .background {
                  if model.section == section {
                    RoundedRectangle(cornerRadius: 2).fill(Enki.selection)
                      .matchedGeometryEffect(id: "navigation", in: navigationInk)
                  }
                }
                .contentShape(Rectangle())
            }.buttonStyle(PaperButtonStyle()).accessibilityIdentifier("nav-" + section.rawValue)
              .accessibilityLabel(section.title(model)).accessibilityAddTraits(
                model.section == section ? .isSelected : [])
          }
        }.animation(reducedMotion ? nil : PaperMotion.navigation, value: model.section).padding(
          .top, 14
        ).padding(.horizontal, 8)
      }
      VStack(alignment: .leading, spacing: 12) {
        Button(model.t("← Espacios", "← Spaces")) { model.showSpaces = true }
          .accessibilityIdentifier("spaces-home").buttonStyle(ActionLink())
        Button(model.t("Nuevo espacio…", "New space…")) { newSpace = true }.buttonStyle(
          ActionLink()
        ).accessibilityIdentifier("new-space").disabled(model.busy || model.pending != nil)
        Button(model.t("Preferencias", "Preferences")) { model.navigate(.settings) }.buttonStyle(
          ActionLink())
        Text(model.author.uppercased() + model.t(" · ESTA MAC", " · THIS MAC"))
          .font(.custom(Enki.mono, size: 7)).foregroundStyle(.secondary).lineLimit(1)
      }.padding(16)
    }.background { PaperGlassSurface(tint: Enki.side) }
  }
  private var breadcrumb: some View {
    HStack(spacing: 10) {
      Button {
        model.showSpaces = true
      } label: {
        MicroLabel(text: model.space?.name ?? "ADÊ")
      }.buttonStyle(.plain).help(model.t("Cambiar de espacio", "Switch space"))
      MicroLabel(text: "/")
      Button {
        if model.section == .events { model.selectedEvent = nil }
      } label: {
        MicroLabel(text: model.section.title(model)).foregroundStyle(Enki.accent)
      }.buttonStyle(.plain)
      if model.section == .events, let id = model.selectedEvent, let e = model.space?.event(id) {
        MicroLabel(text: "/ " + e.name).lineLimit(1).truncationMode(.middle)
      }
      Spacer(minLength: 12)
      Button(model.t("↶ Deshacer", "↶ Undo")) { Task { await model.undo() } }.buttonStyle(
        ActionLink()
      ).disabled(!model.canUndo).accessibilityIdentifier("history-undo").help(
        model.t(
          "Deshacer el último cambio guardado de esta sesión",
          "Undo the last saved change in this session"))
      Button(model.t("↷ Rehacer", "↷ Redo")) { Task { await model.redo() } }.buttonStyle(
        ActionLink()
      ).disabled(!model.canRedo).accessibilityIdentifier("history-redo")
      HStack(spacing: 6) {
        language("es")
        Text("·").font(.custom(Enki.mono, size: 9))
        language("en")
      }.padding(.leading, 8)
    }.padding(.horizontal, 32).frame(height: 42)
      .background { PaperGlassSurface() }
  }
  private func language(_ value: String) -> some View {
    Button(value.uppercased()) { model.locale = value }.buttonStyle(.plain).font(
      .custom(Enki.mono, size: 9)
    ).tracking(1).foregroundStyle(model.locale == value ? Enki.accent : Enki.ink).underline(
      model.locale == value
    ).accessibilityLabel(value == "es" ? "Español" : "English")
  }
  @ViewBuilder private var content: some View {
    switch model.section {
    case .summary: OverviewView()
    case .events: EventsView()
    case .people, .groups, .periods, .classification: CatalogView(section: model.section)
    case .results: ResultsView()
    case .documents: DocumentsView()
    case .history: HistoryView()
    case .data: DataView()
    case .conflicts: ConflictsView()
    case .rules: RulesView()
    case .settings: SettingsView()
    }
  }
}
struct SpaceEditor: View {
  @Environment(AppModel.self) private var m
  @State private var name = ""
  @State private var zone = "America/Puerto_Rico"
  var body: some View {
    SheetFrame(
      title: m.t("Nuevo espacio", "New space"),
      save: { await m.createSpace(name: name, zone: zone) }
    ) {
      PaperForm {
        PaperInput(m.t("Nombre", "Name")) { TextField(m.t("Nombre", "Name"), text: $name) }
          .accessibilityIdentifier("field-name")
        PaperInput(m.t("Zona horaria IANA", "IANA time zone")) {
          TextField(m.t("Zona horaria IANA", "IANA time zone"), text: $zone)
        }
        Text(
          m.t(
            "Cada espacio conserva sus personas, eventos y revisiones de forma independiente.",
            "Each space keeps independent people, events and revisions.")
        ).foregroundStyle(.secondary)
      }
    }
  }
}

@MainActor final class AdeAppDelegate: NSObject, NSApplicationDelegate {
  weak var model: AppModel?
  func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    guard let model, model.busy || model.pending != nil else { return .terminateNow }
    model.error = model.t(
      "Hay cambios sin guardar. Espera a que termine el guardado, reintenta o exporta una copia antes de salir.",
      "There are unsaved changes. Wait for saving to finish, retry or export a copy before quitting."
    )
    return .terminateCancel
  }
}
