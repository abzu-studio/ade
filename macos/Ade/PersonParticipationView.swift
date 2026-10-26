import SwiftUI
import UniformTypeIdentifiers

/// A single person's complete record. All figures are supplied by the shared native Rules core.
struct PersonParticipationView: View {
  @Environment(AppModel.self) private var m
  @Environment(\.dismiss) private var dismiss
  let personID: String
  @State private var period = ""
  @State private var group = ""
  @State private var component = ""
  @State private var error: String?

  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      header
      if let space = m.space {
        filters(space)
        if let slices, let total = slices.first {
          summary(total)
          breakdown(slices)
        } else {
          Text(
            m.t(
              "No se puede calcular este informe. Revisa la persona y los filtros.",
              "This report cannot be calculated. Check the person and filters."))
          Spacer()
        }
      }
      Text(
        m.t(
          "P = presente · A = ausente. Se excluyen pendientes, excusados, borradores, cancelados y eventos que no cuentan. Solo cuentan las personas inscritas. — = sin asistencias evaluables, nunca 0%. El total se calcula con registros, no promediando porcentajes.",
          "P = present · A = absent. Pending, excused, draft, cancelled and non-counting events are excluded. Only listed people count. — = no eligible attendance, never 0%. Totals use records, not averaged percentages."
        )
      )
      .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
    }.padding(30).frame(width: 850, height: 640).background { PaperGlassSurface() }
      .foregroundStyle(Enki.ink).buttonStyle(ActionLink())
      .onChange(of: m.branch?.heads) {
        guard let space = m.space else { return }
        if !space.periods.contains(where: { $0.id == period }) { period = "" }
        if !space.groups.contains(where: { $0.id == group }) { group = "" }
        if !space.components.contains(where: { $0.id == component }) { component = "" }
      }
      .alert(
        m.t("No se pudo exportar", "Unable to export"),
        isPresented: Binding(
          get: { error != nil }, set: { if !$0 { error = nil } })
      ) {
        Button("OK") { error = nil }
      } message: {
        Text(error ?? "")
      }
  }

  private var header: some View {
    HStack(alignment: .top) {
      VStack(alignment: .leading, spacing: 5) {
        MicroLabel(text: m.t("ASISTENCIA INDIVIDUAL", "INDIVIDUAL ATTENDANCE"))
        Text(m.space?.person(personID)?.name ?? "—")
          .font(.custom(Enki.display, size: 36)).foregroundStyle(Enki.accent)
        if m.space?.person(personID)?.active == false {
          Text(
            m.t("Persona inactiva · historial conservado", "Inactive person · history preserved")
          )
          .font(.caption)
        }
      }
      Spacer()
      Button(m.t("Exportar CSV…", "Export CSV…")) { export() }
        .disabled(slices == nil).accessibilityIdentifier("person-report-export")
      Button(m.t("Cerrar", "Close")) { dismiss() }
        .keyboardShortcut(.cancelAction).accessibilityIdentifier("person-report-close")
    }
  }

  private func filters(_ space: Space) -> some View {
    HStack(spacing: 22) {
      PaperPicker(
        m.t("Período", "Period"), selection: $period,
        options: [PaperOption("", m.t("Todo el historial", "All history"))]
          + space.periods.map { PaperOption($0.id, $0.name) }
      )
      .accessibilityIdentifier("person-report-period")
      PaperPicker(
        m.t("Grupo en la fecha del evento", "Group on event date"), selection: $group,
        options: [PaperOption("", m.t("Todos", "All"))]
          + space.groups.map { PaperOption($0.id, $0.name) })
      PaperPicker(
        m.t("Desglose", "Breakdown"), selection: $component,
        options: [PaperOption("", m.t("Todos los componentes", "All components"))]
          + space.components.map { PaperOption($0.id, $0.name) }
      )
      .accessibilityIdentifier("person-report-component")
    }
  }

  private func summary(_ total: ParticipationSlice) -> some View {
    HStack(alignment: .firstTextBaseline, spacing: 26) {
      Text(total.result.formatted).font(.custom(Enki.display, size: 64))
        .foregroundStyle(Enki.accent).accessibilityIdentifier("person-report-total")
      VStack(alignment: .leading, spacing: 5) {
        Text(m.t("GENERAL · PERÍODO Y GRUPO ELEGIDOS", "OVERALL · SELECTED PERIOD AND GROUP"))
          .font(.custom(Enki.mono, size: 10))
        Text(formula(total.result)).font(.custom(Enki.mono, size: 12))
        Text(
          m.t(
            "El desglose no cambia este total.", "The breakdown does not change this total.")
        )
        .font(.caption).foregroundStyle(.secondary)
      }
      Spacer()
    }
  }

  private func breakdown(_ slices: [ParticipationSlice]) -> some View {
    ScrollView {
      LazyVStack(alignment: .leading, spacing: 0) {
        HStack {
          MicroLabel(text: m.t("Componente / categoría", "Component / category"))
          Spacer()
          Text(m.t("P / (P + A)", "P / (P + A)")).font(.custom(Enki.mono, size: 10)).frame(
            width: 160)
          Text("%").font(.custom(Enki.mono, size: 10)).frame(width: 90)
        }.padding(.vertical, 10)
        ForEach(
          slices.filter {
            $0.kind != .overall && (component.isEmpty || $0.componentId == component)
          }
        ) { row in
          HStack {
            VStack(alignment: .leading, spacing: 4) {
              Text(label(row)).font(
                .custom(
                  row.kind == .component ? Enki.condensed : "Inter-Regular",
                  size: row.kind == .component ? 23 : 13))
              Text(
                m.t("Excusados", "Excused") + " \(row.result.excused) · "
                  + m.t("Pendientes", "Pending") + " \(row.result.pending) · "
                  + m.t("Excluidos", "Excluded") + " \(row.result.excluded)"
              )
              .font(.custom(Enki.mono, size: 9)).foregroundStyle(.secondary)
            }.padding(.leading, row.kind == .component ? 0 : 24)
            Spacer()
            Text(formula(row.result)).font(.custom(Enki.mono, size: 12)).frame(width: 160)
            Text(row.result.formatted).font(.custom(Enki.condensed, size: 26))
              .foregroundStyle(Enki.accent).frame(width: 90)
              .accessibilityIdentifier("person-report-" + row.id)
          }.padding(.vertical, row.kind == .component ? 16 : 11)
          PaperRule(strong: row.kind == .component)
        }
      }
    }.frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  private var slices: [ParticipationSlice]? {
    guard let space = m.space else { return nil }
    return try? Rules.participationBreakdown(space, person: personID, period: period, group: group)
  }
  private func formula(_ r: Participation) -> String {
    "\(r.present) / (\(r.present) + \(r.absent))"
  }
  private func label(_ row: ParticipationSlice) -> String {
    switch row.kind {
    case .overall: m.t("General", "Overall")
    case .uncategorized: m.t("Sin categoría", "Uncategorized")
    default: row.name
    }
  }
  private func export() {
    guard let slices else { return }
    func cell(_ value: String) -> String {
      let safe = ["=", "+", "-", "@"].contains(String(value.prefix(1))) ? "'" + value : value
      return "\"" + safe.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
    let name = m.space?.person(personID)?.name ?? ""
    let csv =
      "Person,Scope,ComponentID,PeriodID,GroupID,Present,Absent,Excused,Pending,Excluded,Percentage,Revision\n"
      + slices.map { row in
        [
          name, label(row), row.componentId, period, group, String(row.result.present),
          String(row.result.absent), String(row.result.excused), String(row.result.pending),
          String(row.result.excluded), row.result.percentage.map { String($0) } ?? "",
          m.branch?.heads.first ?? "",
        ].map(cell).joined(separator: ",")
      }.joined(separator: "\n")
    do {
      try Panels.save(
        Data(csv.utf8), name: "Ade-asistencia-individual.csv", type: .commaSeparatedText)
    } catch { self.error = error.localizedDescription }
  }
}
