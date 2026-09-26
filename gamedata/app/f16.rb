# 16.16 fixed-point math: 65536 == 1.0.
# The original runs on 32-bit ints, so products and quotients wrap like C++ int32.
module F16
  ONE = 65536
  PI_HALF = 102944
  PI = 205887

  def self.i32(v)
    ((v + 0x80000000) & 0xFFFFFFFF) - 0x80000000
  end

  # Floor division of integers. DragonRuby's Integer#/ returns a Float, CRuby lacks #idiv.
  def self.idiv(a, b)
    a.respond_to?(:idiv) ? a.idiv(b) : a.div(b)
  end

  # Integer division truncating toward zero, like C++ and JS BigInt.
  def self.tdiv(a, b)
    q = idiv(a.abs, b.abs)
    (a < 0) == (b < 0) ? q : -q
  end

  def self.mul(a, b)
    i32((a * b) >> 16)
  end

  def self.div(a, b)
    i32(tdiv(a << 32, b) >> 16)
  end

  # Fast length approximation used everywhere instead of sqrt.
  def self.max_abs(x, y)
    ax = x.abs
    ay = y.abs
    ay >= ax ? mul(64448, ay) + mul(28224, ax) : mul(64448, ax) + mul(28224, ay)
  end

  def self.round_to_i(v)
    r = v.abs.round
    v < 0 ? -r : r
  end

  def self.sin(angle)
    round_to_i(Math.sin(angle / 65535.0) * 65536)
  end

  def self.cos(angle)
    sin(PI_HALF - angle)
  end

  def self.atan2(dx, dy)
    return (dx > 0 ? 1 : -1) * PI_HALF if dy.abs < 3

    a = round_to_i(Math.atan(div(dx, dy) / 65535.0) * 65536)
    if dx > 0
      dy > 0 ? a : PI + a
    else
      dy > 0 ? a : a - PI
    end
  end
end
