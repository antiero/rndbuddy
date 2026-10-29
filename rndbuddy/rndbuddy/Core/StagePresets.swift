import Foundation

extension PerformancePage {
    /// Reference compositions reserve the centre for Pixels rather than filling a dashboard.
    func withStagePlacements() -> PerformancePage {
        var page = self
        for layout in LayoutClass.allCases {
            let (columns, rows) = layout.grid
            let portrait = layout == .phonePortrait || layout == .padPortrait || layout == .foldOpen
            let faders = controls.filter { $0.kind == .fader }
            let triggers = controls.filter { $0.kind == .trigger || $0.kind == .toggle }
            var list: [Placement] = []
            func add(_ control: ControlSpec, _ x: Int, _ y: Int, _ w: Int, _ h: Int) {
                let p = Placement(controlID: control.id, column: x, row: y, width: w, height: h)
                if x >= 0 && y >= 0 && x + w <= columns && y + h <= rows && !list.contains(where: { $0.overlaps(p) }) { list.append(p) }
            }
            if portrait {
                if let field = controls.first(where: { $0.kind == .xy || $0.kind == .keys }) { add(field, 0, 0, columns, rows / 2) }
                for (i, fader) in faders.enumerated() { add(fader, i * 2, rows / 2, 2, max(2, rows / 3)) }
                for (i, trigger) in triggers.enumerated() { add(trigger, i * 2, rows - 2, 2, 1) }
                if let tracks = controls.first(where: { $0.kind == .tracks }) { add(tracks, 0, rows - 1, columns / 2, 1) }
                if let patch = controls.first(where: { $0.kind == .patchBar }) { add(patch, columns / 2, rows - 1, columns / 2, 1) }
            } else {
                for (i, fader) in faders.enumerated() { add(fader, i * 2, 1, 2, max(3, rows / 2)) }
                let x = columns * 3 / 5
                if let field = controls.first(where: { $0.kind == .xy || $0.kind == .keys }) {
                    if layout == .padLandscape { add(field, 4, 2, columns - 8, rows - 4) }
                    else { add(field, x, 1, columns - x, max(3, rows / 2)) }
                }
                for (i, trigger) in triggers.enumerated() {
                    if layout == .padLandscape { add(trigger, columns - 4 + (i % 2) * 2, 3 + (i / 2) * 2, 2, 2) }
                    else { add(trigger, x + i * 2, min(rows - 2, 1 + max(3, rows / 2)), 2, 1) }
                }
                if let tracks = controls.first(where: { $0.kind == .tracks }) { add(tracks, 0, rows - 1, columns / 2, 1) }
                if let patch = controls.first(where: { $0.kind == .patchBar }) { add(patch, columns * 2 / 3, rows - 1, columns - columns * 2 / 3, 1) }
            }
            page.placements[layout] = list
        }
        return page
    }
}
