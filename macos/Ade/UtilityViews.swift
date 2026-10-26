import SwiftUI

struct DataView: View {
  @Environment(AppModel.self) private var m
  var body: some View {
    VStack(spacing: 0) {
      PageHeading(title: m.t("Datos", "Data"), subtitle: m.space?.name ?? "") { EmptyView() }
      ScrollView {
        VStack(alignment: .leading, spacing: 0) {
          dataRow(
            "01", m.t("Archivo completo", "Complete workspace"),
            m.t(
              "Exporta todos los espacios, plantillas e historial en un archivo JSON.",
              "Export all spaces, templates and history in a JSON file."),
            m.t("Exportar →", "Export →")
          ) { m.exportWorkspace() }
          dataRow(
            "02", m.t("Combinar versiones", "Merge versions"),
            m.t(
              "Importa un archivo de Adê. Las revisiones divergentes se conservan para resolverlas manualmente.",
              "Import an Adê file. Divergent revisions are preserved for manual resolution."),
            m.t("Importar →", "Import →")
          ) { Task { await m.importWorkspace() } }
          dataRow(
            "03", m.t("Copia anterior", "Previous backup"),
            m.t(
              "Extrae el archivo anterior al último guardado; no sustituye el actual.",
              "Extract the file from before the last save without replacing the current file."),
            m.t("Recuperar →", "Recover →")
          ) { Task { await m.recoverBackup() } }
          dataRow(
            "04", m.t("Archivo de este Mac", "This Mac’s workspace"),
            m.t(
              "Relee el almacenamiento local para incorporar cambios de otra instancia.",
              "Reload local storage to read changes from another instance."),
            m.t("Recargar →", "Reload →")
          ) { Task { await m.load() } }
          Text(
            m.t(
              "Comparte un espacio exportándolo e importándolo en otro Mac. Los cambios en conflicto se conservan para revisarlos.",
              "Share a space by exporting it and importing it on another Mac. Conflicting changes are preserved for review.")
          ).font(.callout).foregroundStyle(.secondary).padding(.top, 28)
        }.padding(.horizontal, 32)
      }
    }
  }
  private func dataRow(
    _ number: String, _ title: String, _ detail: String, _ action: String, run: @escaping () -> Void
  ) -> some View {
    VStack(spacing: 0) {
      HStack(alignment: .top, spacing: 24) {
        MicroLabel(text: number).frame(width: 32)
        VStack(alignment: .leading, spacing: 8) {
          Text(title.uppercased()).font(.custom(Enki.display, size: 26))
          Text(detail).font(.callout).foregroundStyle(.secondary)
        }
        Spacer()
        Button(action, action: run).buttonStyle(ActionLink()).disabled(m.busy || m.pending != nil)
      }.padding(.vertical, 24)
      PaperRule()
    }
  }
}
struct ConflictsView: View {
  @Environment(AppModel.self) private var m
  @State private var choice: Revision?
  var body: some View {
    VStack(spacing: 0) {
      PageHeading(title: m.t("Conflictos", "Conflicts"), subtitle: m.space?.name ?? "") {
        EmptyView()
      }
      if let branch = m.branch, branch.conflicted {
        ScrollView {
          VStack(alignment: .leading, spacing: 18) {
            Text(
              m.t(
                "Ambas versiones están conservadas. Compara sus datos y elige una como versión actual; las demás seguirán disponibles en Historial.",
                "Both versions are preserved. Compare them and choose the current version; all others remain in History."
              ))
            ForEach(branch.revisions.filter { branch.heads.contains($0.id) }) { r in
              VStack(alignment: .leading, spacing: 12) {
                PaperRule()
                MicroLabel(text: r.timestamp + " · " + r.author)
                Text(r.label.uppercased()).font(.custom(Enki.display, size: 28))
                Text(
                  "\(r.data.people.count) " + m.t("personas", "people")
                    + " · \(r.data.events.count) " + m.t("eventos", "events")
                    + " · \(r.data.attendance.count) " + m.t("asistencias", "attendance records"))
                PaperDisclosure(m.t("Examinar versión completa", "Inspect full version")) {
                  ScrollView([.horizontal, .vertical]) {
                    Text(
                      (try? String(decoding: WorkspaceCodec.encode(r.data), as: UTF8.self)) ?? ""
                    ).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                  }.frame(height: 260)
                }
                Button(m.t("Elegir esta versión →", "Choose this version →")) { choice = r }
                  .buttonStyle(ActionLink()).disabled(m.busy || m.pending != nil)
              }
            }
          }.padding(32)
        }
      } else {
        VStack(alignment: .leading, spacing: 18) {
          StatusStamp(text: m.t("Sin conflictos", "No conflicts"))
          Text(
            m.t(
              "Las versiones de este espacio coinciden. Puedes continuar trabajando.",
              "This space has no divergent versions. You can keep working."))
          Spacer()
        }.frame(maxWidth: .infinity, alignment: .leading).padding(32)
      }
    }.confirmationDialog(
      m.t("¿Usar esta versión?", "Use this version?"),
      isPresented: Binding(get: { choice != nil }, set: { if !$0 { choice = nil } }),
      titleVisibility: .visible
    ) {
      if let r = choice {
        Button(m.t("Elegir y conservar todas las revisiones", "Choose and preserve all revisions"))
        {
          Task { await m.restore(r) }
          choice = nil
        }
      }
    }
  }
}
struct RulesView: View {
  @Environment(AppModel.self) private var m
  var body: some View {
    VStack(spacing: 0) {
      PageHeading(
        title: m.t("Reglas", "Rules"),
        subtitle: m.t("Cálculos transparentes", "Transparent calculations")
      ) { EmptyView() }
      ScrollView {
        VStack(alignment: .leading, spacing: 24) {
          rule(
            "01", m.t("Asistencia", "Attendance"),
            m.t("Presente / (presente + ausente)", "Present / (present + absent)"),
            m.t(
              "Pendiente, excusado, borrador, cancelado y eventos que no cuentan quedan fuera. Una persona fuera de la lista nunca genera una ausencia automática. Sin denominador se muestra —.",
              "Pending, excused, draft, cancelled and non-counting events are excluded. An unlisted person never generates an automatic absence. No denominator is shown as —."
            ))
          rule(
            "02", m.t("Grupos en el tiempo", "Groups over time"),
            m.t("Membresía en la fecha del evento", "Membership on the event date"),
            m.t(
              "Desde y hasta son inclusivos. No se permiten intervalos solapados para la misma persona y grupo. Desactivar una persona conserva sus resultados históricos.",
              "Start and end dates are inclusive. The same person/group cannot have overlapping intervals. Deactivating a person preserves historical results."
            ))
          rule(
            "03", m.t("Voluntariado", "Volunteering"),
            m.t(
              "Completados previos × 3 + presentes previos × 1",
              "Prior completions × 3 + prior presence × 1"),
            m.t(
              "Solo se usa evidencia anterior al evento. La selección siempre es manual y valida el cupo total y el de voluntarios. Completar voluntariado no cambia la asistencia. Declinar libera el cupo y conserva la lista.",
              "Only earlier evidence is used. Selection is always manual and checks both event and volunteer capacity. Completing volunteering does not change attendance. Declining frees the volunteer seat and retains the roster."
            ))
          rule(
            "04", m.t("Historial recuperable", "Recoverable history"),
            m.t("Cada cambio crea una revisión", "Every change creates a revision"),
            m.t(
              "Deshacer, rehacer y restaurar crean nuevas revisiones; no borran el pasado. Deshacer/rehacer se aplica a cambios guardados de esta sesión. Para cambios anteriores, usa Historial. Los conflictos conservan ambas versiones.",
              "Undo, redo and restore create new revisions without erasing the past. Undo/redo covers saved changes in this session. Use History for earlier changes. Conflicts preserve both versions."
            ))
        }.padding(32)
      }
    }
  }
  private func rule(_ number: String, _ title: String, _ formula: String, _ text: String)
    -> some View
  {
    VStack(alignment: .leading, spacing: 12) {
      MicroLabel(text: number + " · " + title)
      Text(formula.uppercased()).font(.custom(Enki.display, size: 28))
      Text(text).font(.callout).lineSpacing(4)
      PaperRule()
    }
  }
}
