import CoreGraphics

/// 0 at `from`, 1 at `to`, clamped — the shared building block every responsive lerp in the
/// Customize tab uses so the diagram, its padding, and its labels all scale off the same two
/// window-size anchors (the enforced minimum and a "comfortable" size) instead of drifting apart.
func unitLerp(_ value: CGFloat, from: CGFloat, to: CGFloat) -> CGFloat {
    guard to != from else { return 0 }
    return min(max((value - from) / (to - from), 0), 1)
}

func lerp(_ min: CGFloat, _ max: CGFloat, t: CGFloat) -> CGFloat {
    min + (max - min) * t
}

/// Fixed height of the Top View / Side View thumbnail strip under the diagram — used both to size
/// it and to subtract it from the area handed to MouseDiagramView, so the two never fight over the
/// same vertical space at the window's minimum height.
let viewAngleStripHeight: CGFloat = 100
