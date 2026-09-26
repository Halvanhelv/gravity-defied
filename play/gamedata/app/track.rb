# One track: the ground polyline, collision against it, and its render geometry.
# Merges the original GameLevel and LevelLoader. Track units are half of physics units.
class Track
  COLLIDE_NONE = 2
  COLLIDE_TOUCH = 1
  COLLIDE_DEEP = 0

  attr_reader :name, :points, :start_flag_point, :finish_flag_point
  attr_reader :collision_normal_x, :collision_normal_y

  def initialize(level)
    @name = level[:name]
    @start_pos_x, @start_pos_y = level[:start]
    @finish_pos_x, @finish_pos_y = level[:finish]
    @points = []
    load_points(level[:points])
    prepare_geometry

    @outer_radius_sq = []
    @inner_radius_sq = []
    Physics::RADII.each do |r|
      outer = (r + 19660) >> 1
      inner = (r - 19660) >> 1
      @outer_radius_sq << F16.mul(outer, outer)
      @inner_radius_sq << F16.mul(inner, inner)
    end

    @visible_start = 0
    @visible_end = 0
    @visible_start_x = 0
    @visible_end_x = 0
    @min_x = 0
    @max_x = 0
    @shadow_start_x = 0
    @shadow_end_x = 0
    @shadow_y = 0
    @shadow_blend = 0
  end

  def start_x = F16.i32(@start_pos_x << 1)
  def start_y = F16.i32(@start_pos_y << 1)
  def start_line_x = F16.i32(@points[@start_flag_point][0] << 1)
  def finish_line_x = F16.i32(@points[@finish_flag_point][0] << 1)

  def progress(x)
    x >>= 1
    done = x - @points[@start_flag_point][0]
    total = @points[@finish_flag_point][0] - @points[@start_flag_point][0]
    total.abs >= 3 && done <= total ? F16.div(done, total) : F16::ONE
  end

  # --- collision ------------------------------------------------------------

  def update_visible_range(min_x, max_x, rider_y)
    set_shadow_state((min_x + 98304) >> 1, (max_x - 98304) >> 1, rider_y >> 1)
    max_x >>= 1
    min_x >>= 1
    n = @points.size

    @visible_end = [@visible_end, n - 1].min
    @visible_start = [@visible_start, 0].max

    if max_x > @visible_end_x
      while @visible_end < n - 1
        @visible_end += 1
        break unless max_x > @points[@visible_end][0]
      end
    elsif min_x < @visible_start_x
      while @visible_start > 0
        @visible_start -= 1
        break unless min_x < @points[@visible_start][0]
      end
    else
      while @visible_start < n
        @visible_start += 1
        break unless @points[@visible_start] && min_x > @points[@visible_start][0]
      end
      @visible_start -= 1 if @visible_start > 0

      while @visible_end > 0
        @visible_end -= 1
        break unless max_x < @points[@visible_end][0]
      end
      @visible_end = [@visible_end + 1, n - 1].min
    end

    @visible_start_x = @points[@visible_start][0]
    @visible_end_x = @points[@visible_end][0]
  end

  # Returns COLLIDE_NONE / COLLIDE_TOUCH / COLLIDE_DEEP and sets the collision normal.
  def detect_collision(state, shape)
    touches = 0
    result = COLLIDE_NONE
    x = state.x >> 1
    y = (state.y >> 1) - 65536
    sum_nx = 0
    sum_ny = 0
    outer = @outer_radius_sq[shape]

    (@visible_start...@visible_end).each do |i|
      x1, y1 = @points[i]
      x2, y2 = @points[i + 1]
      next unless x - outer <= x2 && x + outer >= x1

      ex = x1 - x2
      ey = y1 - y2
      len_sq = F16.mul(ex, ex) + F16.mul(ey, ey)
      dot = F16.mul(x - x1, -ex) + F16.mul(y - y1, -ey)
      t = if len_sq.abs >= 3
            F16.div(dot, len_sq)
          else
            (dot > 0 ? 1 : -1) * (len_sq > 0 ? 1 : -1) * 0x7FFFFFFF
          end
      t = t.clamp(0, 65536)

      dx = x - (x1 + F16.mul(t, -ex))
      dy = y - (y1 + F16.mul(t, -ey))
      dist_sq = F16.mul(dx, dx) + F16.mul(dy, dy)
      depth = if dist_sq >= outer then COLLIDE_NONE
              elsif dist_sq >= @inner_radius_sq[shape] then COLLIDE_TOUCH
              else COLLIDE_DEEP
              end

      nx, ny = @normals[i]
      approaching = F16.mul(nx, state.vx) + F16.mul(ny, state.vy) < 0

      if depth == COLLIDE_DEEP && approaching
        @collision_normal_x = nx
        @collision_normal_y = ny
        return COLLIDE_DEEP
      end

      next unless depth == COLLIDE_TOUCH && approaching

      touches += 1
      result = COLLIDE_TOUCH
      if touches == 1
        sum_nx = nx
        sum_ny = ny
      else
        sum_nx += nx
        sum_ny += ny
      end
    end

    if result == COLLIDE_TOUCH
      return COLLIDE_NONE if F16.mul(sum_nx, state.vx) + F16.mul(sum_ny, state.vy) >= 0

      @collision_normal_x = sum_nx
      @collision_normal_y = sum_ny
    end
    result
  end

  # --- render state -----------------------------------------------------------

  # Visible x range in pixels (may be fractional).
  def set_view_range(min_px, max_px)
    @min_x = F16.i32(min_px.floor << 16) >> 3
    @max_x = F16.i32(max_px.ceil << 16) >> 3
  end

  def set_shadow_range(from_x, to_x)
    @shadow_start_x = from_x >> 1
    @shadow_end_x = to_x >> 1
  end

  def set_shadow_state(from_x, to_x, y)
    @shadow_start_x = from_x
    @shadow_end_x = to_x
    @shadow_y = y
  end

  # Pseudo-3D ground: a far copy of the track pulled toward the rider, joined by depth lines.
  # Yields [:line, x1, y1, x2, y2, color] and [:flag, kind, x, y] in track pixels.
  def each_3d_primitive(rider_x, rider_y)
    rider_x >>= 1
    rider_y >>= 1
    shadow_from = 0
    shadow_to = 0
    i = first_visible_point
    far_x, far_y = depth_offset(rider_x, rider_y, i)

    while i < @points.size - 1
      prev_x = far_x
      prev_y = far_y
      far_x, far_y = depth_offset(rider_x, rider_y, i + 1)
      px, py = @points[i]
      nx, ny = @points[i + 1]
      yield [:line, px2(px + prev_x), px2(py + prev_y), px2(nx + far_x), px2(ny + far_y), :far]
      yield [:line, px2(px), px2(py), px2(px + prev_x), px2(py + prev_y), :far]

      if i > 1
        shadow_from = i - 1 if px > @shadow_start_x && shadow_from == 0
        shadow_to = i - 1 if px > @shadow_end_x && shadow_to == 0
      end
      yield [:flag, :start, px2(px + prev_x), px2(py + prev_y)] if i == @start_flag_point
      yield [:flag, :finish, px2(px + prev_x), px2(py + prev_y)] if i == @finish_flag_point
      break if px > @max_x

      i += 1
    end

    lx, ly = @points[-1]
    yield [:line, px2(lx), px2(ly), px2(lx + far_x), px2(ly + far_y), :far]
    each_shadow_line(shadow_from, shadow_to) { |l| yield l }
  end

  # The near (collidable) track line with its flags.
  def each_near_primitive
    i = first_visible_point
    while i < @points.size - 1
      px, py = @points[i]
      nx, ny = @points[i + 1]
      yield [:line, px2(px), px2(py), px2(nx), px2(ny), :near]
      yield [:flag, :start, px2(px), px2(py)] if i == @start_flag_point
      yield [:flag, :finish, px2(px), px2(py)] if i == @finish_flag_point
      break if px > @max_x

      i += 1
    end
  end

  private

  def load_points(raw)
    first_x, first_y = raw[0]
    add_point(first_x, first_y)
    off_x = first_x
    off_y = first_y
    raw.drop(1).each do |p|
      if p[0] == :abs
        off_x = p[1]
        off_y = p[2]
      else
        off_x += p[0]
        off_y += p[1]
      end
      add_point(off_x, off_y)
    end
  end

  def add_point(px, py)
    x = F16.i32(px << 16) >> 3
    y = F16.i32(py << 16) >> 3
    @points << [x, y] if @points.empty? || @points[-1][0] < x
  end

  def prepare_geometry
    n = @points.size
    @start_flag_point = 0
    @finish_flag_point = 0
    @normals = Array.new(n) do |i|
      ex = @points[(i + 1) % n][0] - @points[i][0]
      ey = @points[(i + 1) % n][1] - @points[i][1]
      len = F16.max_abs(-ey, ex)
      @start_flag_point = i + 1 if @start_flag_point == 0 && @points[i][0] > @start_pos_x
      @finish_flag_point = i if @finish_flag_point == 0 && @points[i][0] > @finish_pos_x
      [F16.div(-ey, len), F16.div(ex, len)]
    end
  end

  def first_visible_point
    i = 0
    i += 1 while i < @points.size - 1 && @points[i][0] <= @min_x
    i > 0 ? i - 1 : i
  end

  def depth_offset(rider_x, rider_y, i)
    dx = rider_x - @points[i][0]
    dy = rider_y + 3276800 - @points[i][1]
    len = F16.max_abs(dx, dy) >> 2
    [F16.div(dx, len), F16.div(dy, len)]
  end

  # Track units (F16, 1/8 px) to fractional pixels.
  def px2(v)
    v / 8192.0
  end

  def each_shadow_line(from, to)
    return unless to < @points.size - 1

    a = @points[from]
    b = @points[to + 1]
    height = [@shadow_y - ((a[1] + b[1]) >> 1), 0].max
    height = [height, 327680].min if @shadow_y <= a[1] || @shadow_y <= b[1]
    @shadow_blend = F16.mul(@shadow_blend, 49152) + F16.mul(height, 16384)
    return unless @shadow_blend <= 557056

    shade = F16.mul(1638400, @shadow_blend) >> 16
    color = [shade, shade, shade]
    y_from = line_y_at(from, @shadow_start_x)
    y_to = line_y_at(to, @shadow_end_x)

    if from == to
      yield [:line, px2(@shadow_start_x), px2(y_from + 65536), px2(@shadow_end_x), px2(y_to + 65536), color]
      return
    end

    yield [:line, px2(@shadow_start_x), px2(y_from + 65536), px2(@points[from + 1][0]), px2(@points[from + 1][1] + 65536), color]
    (from + 1...to).each do |i|
      yield [:line, px2(@points[i][0]), px2(@points[i][1] + 65536), px2(@points[i + 1][0]), px2(@points[i + 1][1] + 65536), color]
    end
    yield [:line, px2(@points[to][0]), px2(@points[to][1] + 65536), px2(@shadow_end_x), px2(y_to + 65536), color]
  end

  def line_y_at(i, x)
    slope = F16.div(@points[i][1] - @points[i + 1][1], @points[i][0] - @points[i + 1][0])
    @points[i][1] - F16.mul(@points[i][0], slope) + F16.mul(x, slope)
  end
end
