# Small drawing helpers shared by the HUD and the menu.
module UI
  # See Renderer::BLACK: pure black primitives do not show up.
  INK = 1
  MUTED = 90

  def self.label(out, x, y, text, size, anchor_x: 0, shade: INK, color: nil)
    r, g, b = color || [shade, shade, shade]
    out << { x: x, y: y, text: text, size_px: size, anchor_x: anchor_x, anchor_y: 0.5, r: r, g: g, b: b }
  end

  def self.panel(out, x, y, w, h, alpha: 235)
    out << { x: x, y: y, w: w, h: h, r: 255, g: 255, b: 255, a: alpha, path: :solid }
    out << { x: x, y: y, w: w, h: h, r: INK, g: INK, b: INK, primitive_marker: :border }
  end

  def self.bar(out, x, y, w, h, fraction, color)
    out << { x: x, y: y, w: w * fraction, h: h, r: color[0], g: color[1], b: color[2], path: :solid }
    out << { x: x, y: y, w: w, h: h, r: INK, g: INK, b: INK, primitive_marker: :border }
  end

  # The original lock icon from sprites.png, centered at (x, y).
  def self.lock(out, x, y)
    out << { x: x, y: y, w: 7 * 4, h: 8 * 4, path: "sprites/sprites.png", tile_x: 18, tile_y: 8, tile_w: 7, tile_h: 8,
             anchor_x: 0.5, anchor_y: 0.5 }
  end

  # 1/100 s to "m:ss.cc".
  def self.format_time(t10)
    seconds = F16.idiv(t10, 100)
    "#{F16.idiv(seconds, 60)}:#{(seconds % 60).to_s.rjust(2, '0')}.#{(t10 % 100).to_s.rjust(2, '0')}"
  end
end
