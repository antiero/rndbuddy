import Foundation

/// Places a page's controls on a layout class's grid. Valid stored placements are kept;
/// everything else flows into thumb-friendly zones: faders leading, triggers trailing,
/// track strip and patch bar along the bottom, fields and keys in the centre.
struct PerformanceLayout: Equatable, Sendable {
    var placements: [Placement]
    /// Controls that did not fit even at 1×1; the UI should offer them on another page.
    var overflow: [UUID]

    static func flow(_ page: PerformancePage, in layout: LayoutClass) -> PerformanceLayout {
        let grid = layout.grid
        var placed: [Placement] = []
        let ids = Set(page.controls.map(\.id))
        for stored in page.placements[layout] ?? [] where ids.contains(stored.controlID)
            && !placed.contains(where: { $0.controlID == stored.controlID || $0.overlaps(stored) })
            && fits(stored, grid) {
            placed.append(stored)
        }
        var overflow: [UUID] = []
        let pending = page.controls.filter { control in !placed.contains { $0.controlID == control.id } }
        // Larger controls first so small ones fill the gaps.
        for control in pending.sorted(by: { priority($0.kind) < priority($1.kind) }) {
            if let placement = place(control, grid: grid, taken: placed) { placed.append(placement) }
            else { overflow.append(control.id) }
        }
        let order = Dictionary(uniqueKeysWithValues: page.controls.enumerated().map { ($1.id, $0) })
        return PerformanceLayout(placements: placed.sorted { order[$0.controlID, default: 0] < order[$1.controlID, default: 0] }, overflow: overflow)
    }

    private static func fits(_ p: Placement, _ grid: (columns: Int, rows: Int)) -> Bool {
        p.width >= 1 && p.height >= 1 && p.column >= 0 && p.row >= 0 && p.column + p.width <= grid.columns && p.row + p.height <= grid.rows
    }
    private static func priority(_ kind: ControlKind) -> Int {
        switch kind { case .tracks: 0; case .patchBar: 1; case .xy: 2; case .keys: 3; case .fader: 4; case .camera: 5; case .trigger: 6; case .toggle: 7 }
    }
    static func preferredSize(_ kind: ControlKind, grid: (columns: Int, rows: Int)) -> (width: Int, height: Int) {
        let (c, r) = grid
        switch kind {
        case .xy: return (max(4, c * 2 / 5), max(3, r / 2))
        case .keys: return (max(4, c * 3 / 5), max(2, r / 3))
        case .fader: return (2, max(3, r / 2))
        case .trigger: return (2, 2)
        case .toggle: return (2, 1)
        case .camera: return (3, 2)
        case .tracks: return (min(c, 8), 1)
        case .patchBar: return (min(c, 8), 1)
        }
    }
    private static func place(_ control: ControlSpec, grid: (columns: Int, rows: Int), taken: [Placement]) -> Placement? {
        let preferred = preferredSize(control.kind, grid: grid)
        // Shrink height first, then width, before giving up.
        var sizes: [(Int, Int)] = []
        for w in stride(from: min(preferred.width, grid.columns), through: 1, by: -1) {
            for h in stride(from: min(preferred.height, grid.rows), through: 1, by: -1) { sizes.append((w, h)) }
        }
        for (w, h) in sizes {
            var candidates: [Placement] = []
            for row in 0...(grid.rows - h) {
                for column in 0...(grid.columns - w) {
                    let p = Placement(controlID: control.id, column: column, row: row, width: w, height: h)
                    if !taken.contains(where: { $0.overlaps(p) }) { candidates.append(p) }
                }
            }
            if let best = candidates.min(by: { score($0, control.kind, grid) < score($1, control.kind, grid) }) { return best }
        }
        return nil
    }
    /// Lower is better. Ties break by row then column so results are deterministic.
    private static func score(_ p: Placement, _ kind: ControlKind, _ grid: (columns: Int, rows: Int)) -> Double {
        let tie = Double(p.row) * 0.001 + Double(p.column) * 0.000_01
        let centreX = Double(p.column) + Double(p.width) / 2 - Double(grid.columns) / 2
        switch kind {
        case .fader, .toggle: return Double(p.column) * 10 + Double(p.row) + tie
        case .trigger, .camera: return Double(grid.columns - p.column - p.width) * 10 + Double(p.row) + tie
        case .tracks: return Double(grid.rows - p.row - p.height) * 10 + Double(p.column) + tie
        case .patchBar: return Double(grid.rows - p.row - p.height) * 10 + Double(grid.columns - p.column - p.width) + tie
        case .xy, .keys: return abs(centreX) + Double(p.row) * 0.5 + tie
        }
    }
}
