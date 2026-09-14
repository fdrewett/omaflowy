pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Shapes
import qs.Commons

// The Workflowy mark: three bullets, the middle one indented, each with a bar
// running off to the right. Drawn rather than shipped as an SVG, which is how
// omarchy draws Dropbox's and Tailscale's marks -- it keeps the stroke on the
// theme's foreground colour instead of baking one in, and stays crisp in a
// 22px slot where a rasterised SVG goes muddy.
//
// Geometry is the official outline verbatim, in its own 48x48 viewBox, scaled
// at the end. The bars are open on their left edge in the original: the path
// draws the top edge, rounds the right cap, and returns along the bottom
// without closing, so the bullet sits over the gap. Closing them would put a
// stroke through the middle of each bullet.
Item {
  id: root

  property real iconSize: Style.font.icon
  property color color: Color.foreground
  // In viewBox units, so it scales with the mark rather than needing a second
  // rule per call site. The source SVG leaves this at 1, which disappears
  // below about 40px.
  property real weight: 4.4

  // Filled rather than stroked. The official mark is an outline, and an
  // outline of six elements with ~2-unit gaps stops resolving below roughly
  // 24px: at bar size the bullets and bars merge into a blob, and thickening
  // the stroke closes the gaps faster than it adds contrast. Filling keeps the
  // silhouette and survives the size, which is the usual favicon treatment.
  property bool solid: false

  // Pixels, not viewBox units -- see the note on the solid item below.
  property real barThickness: 1
  property real bulletSize: 5

  width: iconSize
  height: iconSize
  implicitWidth: iconSize
  implicitHeight: iconSize

  // Solid variant, laid out in WHOLE PIXELS rather than by scaling the 48-unit
  // viewBox. Scaling puts a hairline bar on a fractional boundary, where
  // antialiasing smears one pixel of ink across two and the result reads as a
  // soft grey smudge -- which is what made the first pass look thick and muddy
  // no matter what weight it was given. Rounding every edge to an integer is
  // what makes a 1px line actually one pixel.
  //
  // Proportions are the official mark's, normalised out of its viewBox:
  // row centres at .231/.506/.769, bullets at .223 with the middle row
  // indented to .424, bars running out to .833.
  Item {
    id: solidMark
    visible: root.solid
    anchors.fill: parent

    readonly property int thickness: Math.max(1, Math.round(root.barThickness))
    readonly property int dot: Math.max(2, Math.round(root.bulletSize))
    readonly property int leftX: Math.round(root.iconSize * 0.223)
    readonly property int midX: Math.round(root.iconSize * 0.424)
    readonly property int rightX: Math.round(root.iconSize * 0.833)

    Row3 { cx: solidMark.leftX; cy: Math.round(root.iconSize * 0.231) }
    Row3 { cx: solidMark.midX;  cy: Math.round(root.iconSize * 0.506) }
    Row3 { cx: solidMark.leftX; cy: Math.round(root.iconSize * 0.769) }
  }

  // One bullet and the bar running off it. The bar starts at the bullet's
  // centre so the two read as joined, the way they are in the original.
  component Row3: Item {
    property int cx: 0
    property int cy: 0

    Rectangle {
      x: parent.cx
      y: parent.cy - Math.floor(solidMark.thickness / 2)
      width: Math.max(1, solidMark.rightX - x)
      height: solidMark.thickness
      color: root.color
      antialiasing: false          // a hairline wants hard edges, not blending
    }

    Rectangle {
      x: parent.cx - Math.floor(solidMark.dot / 2)
      y: parent.cy - Math.floor(solidMark.dot / 2)
      width: solidMark.dot
      height: solidMark.dot
      radius: width / 2
      color: root.color
      antialiasing: true           // the only curve here, so it keeps AA
    }
  }

  Shape {
    visible: !root.solid
    // Sized to the viewBox, not to the item, then scaled down. Anchoring this
    // to the item instead makes `layer.enabled` rasterise at the item's size
    // FIRST -- clipping 48 units of drawing into ~17px -- and only then apply
    // the scale, which leaves a sliver of the top-left corner and nothing else.
    width: 48
    height: 48
    antialiasing: true
    layer.enabled: true
    layer.samples: 4
    transform: Scale { xScale: root.iconSize / 48; yScale: root.iconSize / 48 }

    // Bullets. Written as arc pairs because a full circle cannot be one arc.
    Stroke { PathSvg { path: "M5.4996,11.1064 a5.1937,5.1937 0 1,0 10.3874,0 a5.1937,5.1937 0 1,0 -10.3874,0" } }
    Stroke { PathSvg { path: "M15.3693,24.3059 a4.9853,4.9853 0 1,0 9.9706,0 a4.9853,4.9853 0 1,0 -9.9706,0" } }
    Stroke { PathSvg { path: "M5.9328,36.8936 a5.1937,5.1937 0 1,0 10.3874,0 a5.1937,5.1937 0 1,0 -10.3874,0" } }

    // Bars.
    Stroke { PathSvg { path: "M15.2414,8.5071 h24.37 c3.0317,0 3.3855,5.7447 0.3335,5.7447 H14.9719" } }
    Stroke { PathSvg { path: "M24.6107,21.28 H40.1721 c3.0244,0 3.0369,6.0916 -0.0008,6.0916 H24.6128" } }
    Stroke { PathSvg { path: "M15.6746,34.2943 h24.37 c3.0317,0 3.3855,5.7448 0.3335,5.7448 H15.4051" } }
  }

  component Stroke: ShapePath {
    strokeColor: root.color
    strokeWidth: root.weight
    fillColor: "transparent"
    capStyle: ShapePath.RoundCap
    joinStyle: ShapePath.RoundJoin
  }
}
