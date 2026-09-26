# Draws the world straight to the 1280x720 screen. World pixels (the original phone pixels)
# are scaled by ZOOM; lines are thin rotated quads, sprites keep their pixel-art look.
# Two modes like the original settings: original sprites, or pure line art.
class Renderer
  ZOOM = 4
  W = 1280
  H = 720
  VIEW_W = F16.idiv(W, ZOOM)
  VIEW_H = F16.idiv(H, ZOOM)
  LINE = 2.0

  # Pure (0, 0, 0) lines and borders do not show up in DragonRuby 7.18, so "black" is (1, 1, 1).
  BLACK = [1, 1, 1].freeze
  FAR_GROUND = [0, 170, 0].freeze
  NEAR_GROUND = [0, 255, 0].freeze
  FRAME = [50, 50, 50].freeze
  FENDER = [170, 0, 0].freeze
  FORK = [128, 128, 128].freeze
  RIDER_BODY = [0, 0, 128].freeze
  HELMET = [156, 0, 0].freeze

  # sprites.png atlas rects [x, y, w, h] from the top left; flags cycle through 4 frames.
  ATLAS = {
    thin_wheel: [0, 10, 15, 15], thick_wheel: [0, 25, 15, 15], joint: [15, 10, 3, 3],
    start_flag: [[25, 12, 12, 6], [25, 0, 12, 6], [25, 6, 12, 6], [25, 0, 12, 6]],
    finish_flag: [[37, 6, 12, 6], [37, 0, 12, 6], [37, 12, 12, 6], [37, 0, 12, 6]],
  }.freeze

  # Sheets of pre-rotated frames: path, width, height, columns, rows.
  SHEETS = {
    engine: ["sprites/engine.png", 120, 120, 6, 6], fender: ["sprites/fender.png", 108, 108, 6, 6],
    helmet: ["sprites/helmet.png", 48, 48, 6, 6], arm: ["sprites/bluearm.png", 48, 24, 6, 3],
    leg: ["sprites/blueleg.png", 72, 36, 6, 3], body: ["sprites/bluebody.png", 60, 30, 6, 3],
  }.freeze

  # Rider joints (along the bike, up from it) for lean back / neutral / lean forward.
  SPRITE_POSES = [
    [[190054, -111411], [308019, -235929], [334233, -114688], [393216, -58982],
     [262144, 98304], [65536, -124518], [13107, -78643], [288358, 81920]],
    [[183500, -52428], [262144, -163840], [406323, -65536], [445644, -39321],
     [235929, 39321], [16384, -144179], [13107, -78643], [288358, 81920]],
    [[157286, 13107], [294912, -13107], [367001, 91750], [406323, 190054],
     [347340, 72089], [39321, -98304], [13107, -52428], [294912, 81920]],
  ].freeze
  LINE_POSES = [Physics::POSE_BACK, Physics::POSE_NEUTRAL, Physics::POSE_FORWARD].freeze
  TORSO_BLEND = [45875, 32768, 52428].freeze
  # The player's face instead of the helmet, bobblehead-sized, in world pixels.
  FACE = "sprites/head.png"
  FACE_SIZE = 13

  def initialize(out, sprites: true, face: false)
    @out = out
    @sprites = sprites
    @face = face
  end

  def draw(physics, track)
    parts = physics.render_states
    @cam_x, @cam_y = physics.camera
    track.set_view_range(@cam_x - VIEW_W / 2, @cam_x + VIEW_W / 2)
    @flag_frame = physics.flag_frame

    @out << { x: 0, y: 0, w: W, h: H, r: 255, g: 255, b: 255, path: :solid }

    front_joint = parts[Physics::FRONT_JOINT]
    rear_joint = parts[Physics::REAR_JOINT]
    ax = front_joint.x - rear_joint.x
    ay = front_joint.y - rear_joint.y
    len = F16.max_abs(ax, ay)
    if len != 0
      ax = F16.div(ax, len)
      ay = F16.div(ay, len)
    end

    if physics.crashed
      from, to = [rear_joint.x, front_joint.x].minmax
      track.set_shadow_range(from, to)
    end

    track.each_3d_primitive(parts[Physics::BODY].x, parts[Physics::BODY].y) { |p| track_primitive(p, FAR_GROUND) }
    draw_engine(parts, ax, ay) if @sprites
    draw_wheels(physics, parts)
    front = parts[Physics::FRONT_WHEEL]
    arc(wx(front.x), wx(front.y), wx(Physics::RADII[0]) + 1, F16.atan2(ax, ay), @sprites ? FENDER : FRAME)
    line(wx(front_joint.x), wx(front_joint.y), wx(front.x), wx(front.y), FORK) unless physics.crashed
    draw_rider(physics, parts, ax, ay)
    draw_frame(physics, parts, ax, ay) unless @sprites
    track.each_near_primitive { |p| track_primitive(p, NEAR_GROUND) }
  end

  private

  # Physics F16 units to fractional world pixels.
  def wx(v)
    v / 16384.0
  end

  def screen_x(x) = (x - @cam_x) * ZOOM + W / 2
  def screen_y(y) = (y - @cam_y) * ZOOM + H / 2

  def line(x1, y1, x2, y2, color, width = LINE)
    sx1 = screen_x(x1)
    sy1 = screen_y(y1)
    dx = screen_x(x2) - sx1
    dy = screen_y(y2) - sy1
    length = Math.sqrt(dx * dx + dy * dy)
    @out << { x: sx1 + dx / 2, y: sy1 + dy / 2, w: length + width, h: width,
              anchor_x: 0.5, anchor_y: 0.5, angle: Math.atan2(dy, dx) * 180 / Math::PI,
              r: color[0], g: color[1], b: color[2], path: :solid }
  end

  def line_f16(x1, y1, x2, y2, color)
    line(wx(x1), wx(y1), wx(x2), wx(y2), color)
  end

  def circle(cx, cy, radius, color, segments = 24)
    polyline(arc_points(cx, cy, radius, 0, 360, segments), color)
  end

  # J2ME drawArc: fender over the front wheel, 90 degrees starting at the bike angle + 170.
  def arc(cx, cy, radius, angle_f16, color)
    start = (-angle_f16 * 180.0 / F16::PI).floor + 170
    polyline(arc_points(cx, cy, radius, start, 90, 8), color)
  end

  def polyline(points, color)
    points.each_cons(2) { |(x1, y1), (x2, y2)| line(x1, y1, x2, y2, color) }
  end

  def arc_points(cx, cy, radius, start_deg, sweep_deg, segments)
    (0..segments).map do |i|
      a = (start_deg + sweep_deg * i / segments.to_f) * Math::PI / 180
      [cx + radius * Math.cos(a), cy + radius * Math.sin(a)]
    end
  end

  # Atlas sprite; (x, y) is where its anchor point lands, in world pixels.
  def atlas(rect, x, y, anchor_x: 0.5, anchor_y: 0.5)
    tx, ty, tw, th = rect
    @out << { x: screen_x(x), y: screen_y(y), w: tw * ZOOM, h: th * ZOOM, path: "sprites/sprites.png",
              tile_x: tx, tile_y: ty, tile_w: tw, tile_h: th, anchor_x: anchor_x, anchor_y: anchor_y }
  end

  # Frame `index` of a pre-rotated sheet, centered at (x, y).
  def sheet(name, index, x, y)
    path, sheet_w, sheet_h, cols, rows = SHEETS[name]
    cw = F16.idiv(sheet_w, cols)
    ch = F16.idiv(sheet_h, rows)
    @out << { x: screen_x(x), y: screen_y(y), w: cw * ZOOM, h: ch * ZOOM, path: path,
              tile_x: (index % cols) * cw, tile_y: F16.idiv(index, cols) * ch, tile_w: cw, tile_h: ch,
              anchor_x: 0.5, anchor_y: 0.5 }
  end

  # Original calcSpriteNo: picks one of `count` pre-rotated frames for an angle.
  def frame_for(angle, offset, period, count, reverse)
    angle += offset
    angle += period while angle < 0
    angle -= period while angle >= period
    angle = period - angle if reverse
    frame = F16.mul(F16.div(angle, period), count << 16) >> 16
    frame < count - 1 ? frame : count - 1
  end

  def track_primitive(p, ground)
    if p[0] == :line
      line(p[1], p[2], p[3], p[4], p[5].is_a?(Array) ? p[5] : ground)
    else
      draw_flag(p[1], p[2], p[3])
    end
  end

  def draw_flag(kind, x, y)
    line(x, y, x, y + 32, BLACK)
    frames = kind == :start ? ATLAS[:start_flag] : ATLAS[:finish_flag]
    atlas(frames[@flag_frame], x, y + 32, anchor_x: 0, anchor_y: 1)
  end

  def draw_engine(parts, ax, ay)
    body = parts[Physics::BODY]
    fj = parts[Physics::FRONT_JOINT]
    rj = parts[Physics::REAR_JOINT]
    engine_angle = F16.atan2(body.x - fj.x, body.y - fj.y)
    fender_angle = F16.atan2(body.x - rj.x, body.y - rj.y)
    engine_x = (body.x >> 1) + (fj.x >> 1) + F16.mul(-ay, 65536) - F16.mul(ax, 32768)
    engine_y = (body.y >> 1) + (fj.y >> 1) + F16.mul(ax, 65536) - F16.mul(ay, 32768)
    fender_x = (body.x >> 1) + (rj.x >> 1) + F16.mul(-ay, 65536) - F16.mul(ax, 117964)
    fender_y = (body.y >> 1) + (rj.y >> 1) + F16.mul(ax, 65536) - F16.mul(ay, 131072)
    sheet(:fender, frame_for(fender_angle, -185297, 411774, 32, true), wx(fender_x), wx(fender_y))
    sheet(:engine, frame_for(engine_angle, -247063, 411774, 32, true), wx(engine_x), wx(engine_y))
  end

  def draw_wheels(physics, parts)
    radius = physics.parts[Physics::FRONT_WHEEL].radius
    spoke_len = F16.mul(radius, 58982)
    step_cos = F16.cos(82354)
    step_sin = F16.sin(82354)
    thick = { Physics::FRONT_WHEEL => physics.bike >= 2, Physics::REAR_WHEEL => physics.bike >= 1 }
    rims = { Physics::FRONT_WHEEL => spoke_len, Physics::REAR_WHEEL => F16.mul(radius, 45875) }

    [Physics::REAR_WHEEL, Physics::FRONT_WHEEL].each do |i|
      wheel = parts[i]
      cx = wx(wheel.x)
      cy = wx(wheel.y)
      if @sprites
        atlas(thick[i] ? ATLAS[:thick_wheel] : ATLAS[:thin_wheel], cx, cy)
      else
        circle(cx, cy, wx(radius), BLACK)
        circle(cx, cy, wx(rims[i]), BLACK, 18)
      end

      sx = F16.mul(F16.cos(wheel.angle), spoke_len)
      sy = F16.mul(F16.sin(wheel.angle), spoke_len)
      5.times do
        line_f16(wheel.x, wheel.y, wheel.x + sx, wheel.y + sy, BLACK)
        sx, sy = F16.mul(step_cos, sx) + F16.mul(-step_sin, sy), F16.mul(step_sin, sx) + F16.mul(step_cos, sy)
      end

      next unless physics.bike > 0

      circle(cx, cy, 2, physics.bike > 2 ? [100, 100, 255] : [255, 0, 0], 10)
    end
  end

  def draw_rider(physics, parts, ax, ay)
    blend = physics.pose_blend
    poses = @sprites ? SPRITE_POSES : LINE_POSES
    torso_from = 0
    if blend < 32768
      from = poses[0]
      to = poses[1]
      t = F16.mul(blend, 131072)
    elsif blend > 32768
      from = poses[1]
      to = poses[2]
      t = F16.mul(blend - 32768, 131072)
      torso_from = 1
    else
      from = to = poses[1]
      t = 65536
    end

    body = parts[Physics::BODY]
    j = from.each_index.map do |i|
      along = F16.mul(from[i][0], 65536 - t) + F16.mul(to[i][0], t)
      up = F16.mul(from[i][1], 65536 - t) + F16.mul(to[i][1], t)
      [body.x + F16.mul(-ay, along) + F16.mul(ax, up), body.y + F16.mul(ax, along) + F16.mul(ay, up)]
    end
    # Joint indices follow the original pose tables: 3 is the head, 6 and 7 hands/feet.

    if @sprites
      torso_t = F16.mul(TORSO_BLEND[torso_from], 65536 - t) + F16.mul(TORSO_BLEND[torso_from + 1], t)
      body_part(:leg, j[5], j[0])
      body_part(:leg, j[0], j[1])
      body_part(:body, j[1], j[2], torso_t)
      body_part(:arm, j[2], j[4])
      unless @face
        helmet_angle = F16.atan2(ax, ay)
        helmet_angle += 20588 if blend > 32768
        sheet(:helmet, frame_for(helmet_angle, -102943, 411774, 32, true), wx(j[3][0]), wx(j[3][1]))
      end
    else
      line_f16(*j[5], *j[0], BLACK)
      line_f16(*j[0], *j[1], BLACK)
      line_f16(*j[1], *j[2], RIDER_BODY)
      line_f16(*j[2], *j[4], RIDER_BODY)
      line_f16(*j[4], *j[7], RIDER_BODY)
      circle(wx(j[3][0]), wx(j[3][1]), 4, HELMET, 16) unless @face
    end
    draw_face(j[3], ax, ay) if @face

    atlas(ATLAS[:joint], wx(j[7][0]), wx(j[7][1]))
    atlas(ATLAS[:joint], wx(j[6][0]), wx(j[6][1]))
  end

  # Photo head, tilted with the bike.
  def draw_face(head, ax, ay)
    @out << { x: screen_x(wx(head[0])), y: screen_y(wx(head[1])), w: FACE_SIZE * ZOOM, h: FACE_SIZE * ZOOM,
              path: FACE, anchor_x: 0.5, anchor_y: 0.5, angle: Math.atan2(ay, ax) * 180 / Math::PI,
              scale_quality_enum: 1 }
  end

  # Limb sprite between two joints; the rotated frame is picked from their angle.
  def body_part(name, a, b, t = 32768)
    x = F16.mul(b[0], t) + F16.mul(a[0], 65536 - t)
    y = F16.mul(b[1], t) + F16.mul(a[1], 65536 - t)
    angle = F16.atan2(b[0] - a[0], b[1] - a[1])
    sheet(name, frame_for(angle, 0, 205887, 16, false), wx(x), wx(y))
  end

  # Port of renderMotoAsLines; (ax, ay) is the bike axis, (-ay, ax) its normal.
  def draw_frame(physics, parts, ax, ay)
    nx = -ay
    ny = ax
    m = ->(a, b) { F16.mul(a, b) }
    rear = parts[Physics::REAR_WHEEL]
    body = parts[Physics::BODY]
    front = parts[Physics::FRONT_WHEEL]
    rj = parts[Physics::REAR_JOINT]
    fj = parts[Physics::FRONT_JOINT]

    r1x = rear.x + m[nx, 32768]; r1y = rear.y + m[ny, 32768]
    r2x = rear.x - m[nx, 32768]; r2y = rear.y - m[ny, 32768]
    b1x = body.x + m[ax, 32768]; b1y = body.y + m[ay, 32768]
    b2x = b1x - m[ax, 131072]; b2y = b1y - m[ay, 131072]
    b3x = b2x + m[nx, 65536]; b3y = b2y + m[ny, 65536]
    b4x = b2x + m[ax, 49152] + m[nx, 49152]; b4y = b2y + m[ay, 49152] + m[ny, 49152]
    engine_x = b2x + m[nx, 32768]; engine_y = b2y + m[ny, 32768]
    s1x = rj.x - m[ax, 49152]; s1y = rj.y - m[ay, 49152]
    s2x = s1x - m[nx, 32768]; s2y = s1y - m[ny, 32768]
    s3x = s1x - m[ax, 131072] + m[nx, 16384]; s3y = s1y - m[ay, 131072] + m[ny, 16384]
    f1x = fj.x + m[nx, 32768]; f1y = fj.y + m[ny, 32768]
    f2x = fj.x + m[nx, 114688] - m[ax, 32768]; f2y = fj.y + m[ny, 114688] - m[ay, 32768]

    circle(wx(engine_x), wx(engine_y), 2, FRAME, 12)
    unless physics.crashed
      line_f16(r1x, r1y, b3x, b3y, FRAME)
      line_f16(r2x, r2y, b2x, b2y, FRAME)
    end
    line_f16(b1x, b1y, b2x, b2y, FRAME)
    line_f16(b1x, b1y, fj.x, fj.y, FRAME)
    line_f16(b4x, b4y, f1x, f1y, FRAME)
    line_f16(f1x, f1y, f2x, f2y, FRAME)
    unless physics.crashed
      line_f16(fj.x, fj.y, front.x, front.y, FRAME)
      line_f16(f2x, f2y, front.x, front.y, FRAME)
    end
    line_f16(b3x, b3y, s2x, s2y, FRAME)
    line_f16(b4x, b4y, s1x, s1y, FRAME)
    line_f16(s1x, s1y, s3x, s3y, FRAME)
    line_f16(s2x, s2y, s3x, s3y, FRAME)
  end
end
