# Motorbike physics: six point masses joined by damped springs, integrated in 16.16 fixed point.
# Ported from the Gravity Defied C++/TypeScript ports; integer math kept bit-exact.
class BodyState
  attr_accessor :x, :y, :angle, :vx, :vy, :av, :fx, :fy, :torque

  def initialize
    reset
  end

  def reset
    @x = @y = @angle = @vx = @vy = @av = @fx = @fy = @torque = 0
  end
end

# A mass point. states[0..1] ping-pong between steps, 2..4 are integrator scratch, 5 is render copy.
class BodyPart
  attr_accessor :radius, :shape, :inv_mass, :ang_factor
  attr_reader :states

  def initialize
    @states = Array.new(6) { BodyState.new }
    reset
  end

  def reset
    @radius = 0
    @inv_mass = 0
    @ang_factor = 0
    @states.each(&:reset)
  end
end

# A spring between two parts: stiffness (x), rest length (y), damping (angle).
Spring = Struct.new(:stiffness, :rest, :damping)

class Physics
  # Part indices
  BODY = 0
  FRONT_WHEEL = 1
  REAR_WHEEL = 2
  FRONT_JOINT = 3
  REAR_JOINT = 4
  RIDER = 5

  RADII = [114688, 65536, 32768].freeze
  RENDER = 5

  # updatePhysics results
  RUNNING = 0
  FINISHED_CROSSED = 1
  FINISHED_HALF_STEP = 2
  CRASHED = 3
  BEFORE_START = 4
  RIDER_DOWN = 5

  # Rider skeleton poses (lean back / neutral / lean forward), relative to the bike frame.
  POSE_BACK = [[190054, -91750], [255590, -235929], [334233, -114688], [393216, -42598],
               [301465, 6553], [65536, -78643], [13107, -78643], [288358, 85196]].freeze
  POSE_NEUTRAL = [[183500, -39321], [262144, -131072], [393216, -65536], [458752, -39321],
                  [294912, 6553], [16384, -144179], [13107, -78643], [288358, 85196]].freeze
  POSE_FORWARD = [[157286, 13107], [294912, -13107], [367001, 104857], [406323, 176947],
                  [347340, 72089], [39321, -98304], [13107, -52428], [288358, 85196]].freeze

  STEP = 1310
  GRAVITY = 1638400
  TIRE_GRIP = 45875
  TIRE_DAMPING = 13107
  TIRE_ANGULAR_DAMPING = 39321
  MASS_SCALE = 1310720
  SPRING_DAMPING = 262144
  TORQUE_DAMPING = 6553

  # Per bike class: friction, bounce, max wheel speed, max torque, torque step,
  # brake, brake grip loss, lean force, max lean speed, spring stiffness.
  BIKES = [
    [19660, 19660, 1114112, 52428800, 3276800, 327, 0, 32768, 327680, 19660800],
    [32768, 32768, 1114112, 65536000, 3276800, 6553, 26214, 26214, 327680, 19660800],
    [32768, 32768, 1310720, 75366400, 3473408, 6553, 26214, 39321, 327680, 21626880],
    [32768, 32768, 1441792, 78643200, 3538944, 6553, 26214, 65536, 1310720, 21626880],
  ].freeze

  attr_reader :parts, :bike, :crashed, :rider_down, :pose_blend
  attr_accessor :track, :front_wheel_on_ground

  def initialize(track, bike: 1)
    @track = track
    @parts = Array.new(6) { BodyPart.new }
    @springs = Array.new(10) { Spring.new(0, 0, 0) }
    @render = Array.new(6) { BodyState.new }
    @cam_shift_x = 0
    @cam_shift_y = 0
    @look_ahead_clamp = 655360
    @flag_phase = 0
    @flag_time = 0
    @input = { gas: false, brake: false, back: false, forward: false }
    self.bike = bike
  end

  def bike=(index)
    @bike = index
    @friction, @bounce, @max_wheel_speed, @max_torque, @torque_step,
      @brake, @brake_grip_loss, @lean_force, @max_lean_speed, @stiffness = BIKES[index]
    reset
  end

  def reset
    @cur = 0
    @nxt = 1
    place_bike(@track.start_x, @track.start_y)
    @wheel_torque = 0
    @lean_speed = 0
    @pose_blend = 32768
    @crashed = false
    @rider_down = false
    @finish_latched = false
    @front_wheel_on_ground = false
    @track.set_shadow_range(@parts[REAR_WHEEL].states[RENDER].x + 98304 - RADII[0],
                            @parts[FRONT_WHEEL].states[RENDER].x - 98304 + RADII[0])
  end

  # throttle: +1 gas, -1 brake; lean: -1 back, +1 forward.
  def set_input(throttle, lean)
    @input = { gas: throttle > 0, brake: throttle < 0, back: lean < 0, forward: lean > 0 }
  end

  def update
    advance_flag_animation
    apply_controls
    result = solve_step(STEP)
    return RIDER_DOWN if result == RIDER_DOWN || @rider_down
    return CRASHED if @crashed

    if before_start?
      @front_wheel_on_ground = false
      return BEFORE_START
    end
    result
  end

  def before_start?
    @parts[FRONT_WHEEL].states[@cur].x < @track.start_line_x
  end

  def progress
    front = [@render[FRONT_WHEEL].x, @render[REAR_WHEEL].x].max
    @track.progress(@crashed ? @render[BODY].x : front)
  end

  # Copy the latest simulated state into the render slot.
  def sync_render_state
    @parts.each do |p|
      s = p.states[@cur]
      r = p.states[RENDER]
      r.x = s.x
      r.y = s.y
      r.angle = s.angle
    end
    @parts[BODY].states[RENDER].vx = @parts[BODY].states[@cur].vx
    @parts[BODY].states[RENDER].vy = @parts[BODY].states[@cur].vy
    @parts[REAR_WHEEL].states[RENDER].av = @parts[REAR_WHEEL].states[@cur].av
  end

  # Snapshot for the renderer (render-slot positions).
  def render_states
    6.times do |i|
      src = @parts[i].states[RENDER]
      dst = @render[i]
      dst.x = src.x
      dst.y = src.y
      dst.angle = src.angle
    end
    @render[BODY].vx = @parts[BODY].states[RENDER].vx
    @render[BODY].vy = @parts[BODY].states[RENDER].vy
    @render
  end

  def screen_min_wh=(px)
    @look_ahead_clamp = F16.div(F16.mul(655360, px << 16), 8388608)
  end

  # Camera position in (fractional) pixels, with velocity look-ahead.
  def camera
    body = @render[BODY]
    @cam_shift_x = (F16.div(body.vx, 1572864) + F16.mul(@cam_shift_x, 57344)).clamp(-@look_ahead_clamp, @look_ahead_clamp)
    @cam_shift_y = (F16.div(body.vy, 1572864) + F16.mul(@cam_shift_y, 57344)).clamp(-@look_ahead_clamp, @look_ahead_clamp)
    [(body.x + @cam_shift_x) / 16384.0, (body.y + @cam_shift_y) / 16384.0]
  end

  # Waving flag frame 0..3, advanced by physics steps like the original.
  def flag_frame
    @flag_time = 0 if @flag_time > 229376
    @flag_time >> 16
  end

  private

  def advance_flag_animation
    @flag_phase += 655
    wave = 32768 + (F16.sin(@flag_phase).abs >> 1)
    @flag_time += (6553 * wave) >> 16
  end

  def place_bike(x, y)
    # [radius shape, mass, dx, dy, angular factor]
    layout = [
      [1, 360448, 0, 0, 0],
      [0, 98304, 229376, 0, 0],
      [0, 360448, -229376, 0, 21626],
      [1, 229376, 131072, 196608, 0],
      [1, 229376, -131072, 196608, 0],
      [2, 294912, 0, 327680, 0],
    ]
    layout.each_with_index do |(shape, mass, dx, dy, ang), i|
      part = @parts[i]
      part.reset
      part.radius = RADII[shape]
      part.shape = shape
      part.inv_mass = F16.mul(F16.div(65536, mass), MASS_SCALE)
      part.states[@cur].x = x + dx
      part.states[@cur].y = y + dy
      part.states[RENDER].x = x + dx
      part.states[RENDER].y = y + dy
      part.ang_factor = ang
    end

    rests = [229376, 229376, 236293, 236293, 262144, 219814, 219814, 185363, 185363, 327680]
    @springs.each_with_index do |s, i|
      s.stiffness = @stiffness
      s.rest = rests[i]
      s.damping = SPRING_DAMPING
    end
    @springs[5].damping = F16.mul(SPRING_DAMPING, 45875)
    @springs[5].stiffness = F16.mul(6553, @stiffness)
    @springs[6].stiffness = F16.mul(6553, @stiffness)
    @springs[7].stiffness = F16.mul(72089, @stiffness)
    @springs[8].stiffness = F16.mul(72089, @stiffness)
    @springs[9].stiffness = F16.mul(72089, @stiffness)
  end

  def set_inv_mass(i, v)
    @parts[i].inv_mass = F16.mul(v, MASS_SCALE)
  end

  def apply_controls
    return if @crashed

    front = @parts[FRONT_WHEEL].states[@cur]
    rear = @parts[REAR_WHEEL].states[@cur]
    ax = front.x - rear.x
    ay = front.y - rear.y
    len = F16.max_abs(ax, ay)
    ax = F16.div(ax, len)
    ay = F16.div(ay, len)

    @wheel_torque -= @torque_step if @input[:gas] && @wheel_torque >= -@max_torque

    if @input[:brake]
      @wheel_torque = 0
      front.av = F16.mul(front.av, 65536 - @brake)
      rear.av = F16.mul(rear.av, 65536 - @brake)
      front.av = 0 if front.av < 6553
      rear.av = 0 if rear.av < 6553
    end

    set_inv_mass(BODY, 11915)
    set_inv_mass(REAR_JOINT, 18724)
    set_inv_mass(FRONT_JOINT, 18724)
    set_inv_mass(FRONT_WHEEL, 43690)
    set_inv_mass(REAR_WHEEL, 11915)
    set_inv_mass(RIDER, 14563)

    if @input[:back]
      set_inv_mass(BODY, 18724)
      set_inv_mass(REAR_JOINT, 14563)
      set_inv_mass(FRONT_JOINT, 18724)
      set_inv_mass(FRONT_WHEEL, 43690)
      set_inv_mass(REAR_WHEEL, 10082)
    elsif @input[:forward]
      set_inv_mass(BODY, 18724)
      set_inv_mass(REAR_JOINT, 18724)
      set_inv_mass(FRONT_JOINT, 14563)
      set_inv_mass(FRONT_WHEEL, 26214)
      set_inv_mass(REAR_WHEEL, 11915)
    end

    unless @input[:back] || @input[:forward]
      relax_pose
      return
    end

    lean(ax, ay, -1) if @input[:back] && @lean_speed > -@max_lean_speed
    lean(ax, ay, 1) if @input[:forward] && @lean_speed < @max_lean_speed
  end

  # dir -1 leans back, +1 leans forward.
  def lean(ax, ay, dir)
    scale = 65536
    if dir < 0 && @lean_speed < 0
      scale = F16.div(@max_lean_speed - @lean_speed.abs, @max_lean_speed)
    elsif dir > 0 && @lean_speed > 0
      scale = F16.div(@max_lean_speed - @lean_speed, @max_lean_speed)
    end

    force = F16.mul(@lean_force, scale)
    joint_x = F16.mul(-ay, force)
    joint_y = F16.mul(ax, force)
    rider_x = F16.mul(ax, force)
    rider_y = F16.mul(ay, force)

    step = @pose_blend > 32768 ? 1638 : 3276
    @pose_blend = if dir < 0
                    [@pose_blend - step, 0].max
                  else
                    [@pose_blend + step, 65536].min
                  end

    rear_joint = @parts[REAR_JOINT].states[@cur]
    front_joint = @parts[FRONT_JOINT].states[@cur]
    rider = @parts[RIDER].states[@cur]
    rear_joint.vx += dir * joint_x
    rear_joint.vy += dir * joint_y
    front_joint.vx -= dir * joint_x
    front_joint.vy -= dir * joint_y
    rider.vx += dir * rider_x
    rider.vy += dir * rider_y
  end

  def relax_pose
    if @pose_blend < 26214
      @pose_blend += 3276
    elsif @pose_blend > 39321
      @pose_blend -= 3276
    else
      @pose_blend = 32768
    end
  end

  # Advances by `total` with adaptive sub-steps: halves the step until no deep collision.
  def solve_step(total)
    latched_before = @finish_latched
    done = 0
    target = total

    while done < total
      integrate(target - done)
      hit = !latched_before && passed_finish? ? 3 : detect_collisions(@nxt)

      return hit != 3 ? FINISHED_HALF_STEP : FINISHED_CROSSED if !latched_before && @finish_latched

      if hit == Track::COLLIDE_DEEP
        target = (done + target) >> 1
        # The original loops forever once the sub-step halves to zero; treat it as a crash.
        return RIDER_DOWN if target == done

        next
      end

      if hit == 3
        @finish_latched = true
        target = (done + target) >> 1
        next
      end

      if hit == Track::COLLIDE_TOUCH
        loop do
          resolve_collision(@nxt)
          again = detect_collisions(@nxt)
          return RIDER_DOWN if again == Track::COLLIDE_DEEP
          break if again == Track::COLLIDE_NONE
        end
      end

      done = target
      target = total
      @cur, @nxt = @nxt, @cur
    end

    front = @parts[FRONT_WHEEL].states[@cur]
    rear = @parts[REAR_WHEEL].states[@cur]
    dist = F16.mul(front.x - rear.x, front.x - rear.x) + F16.mul(front.y - rear.y, front.y - rear.y)
    @crashed = true if dist < 983040 || dist > 4587520
    RUNNING
  end

  def passed_finish?
    finish = @track.finish_line_x
    @parts[FRONT_WHEEL].states[@nxt].x > finish || @parts[REAR_WHEEL].states[@nxt].x > finish
  end

  def accumulate_forces(slot)
    @parts.each do |p|
      s = p.states[slot]
      s.fx = 0
      s.fy = -F16.div(GRAVITY, p.inv_mass)
      s.torque = 0
    end

    unless @crashed
      spring(BODY, 1, REAR_WHEEL, slot, 65536)
      spring(BODY, 0, FRONT_WHEEL, slot, 65536)
      spring(REAR_WHEEL, 6, REAR_JOINT, slot, 131072)
      spring(FRONT_WHEEL, 5, FRONT_JOINT, slot, 131072)
    end
    spring(BODY, 2, FRONT_JOINT, slot, 65536)
    spring(BODY, 3, REAR_JOINT, slot, 65536)
    spring(FRONT_JOINT, 4, REAR_JOINT, slot, 65536)
    spring(RIDER, 8, FRONT_JOINT, slot, 65536)
    spring(RIDER, 7, REAR_JOINT, slot, 65536)
    spring(RIDER, 9, BODY, slot, 65536)

    rear = @parts[REAR_WHEEL].states[slot]
    @wheel_torque = F16.mul(@wheel_torque, 65536 - TORQUE_DAMPING)
    rear.torque = @wheel_torque
    rear.av = rear.av.clamp(-@max_wheel_speed, @max_wheel_speed)

    avg_vx = 0
    avg_vy = 0
    @parts.each do |p|
      avg_vx += p.states[slot].vx
      avg_vy += p.states[slot].vy
    end
    avg_vx = F16.div(avg_vx, 393216)
    avg_vy = F16.div(avg_vy, 393216)

    rel = 0
    @parts.each do |p|
      s = p.states[slot]
      dvx = s.vx - avg_vx
      dvy = s.vy - avg_vy
      rel = F16.max_abs(dvx, dvy)
      next unless rel > 1966080

      s.vx -= F16.div(dvx, rel)
      s.vy -= F16.div(dvy, rel)
    end

    sign_y = @parts[REAR_WHEEL].states[slot].y - @parts[BODY].states[slot].y >= 0 ? 1 : -1
    sign_v = @parts[REAR_WHEEL].states[slot].vx - @parts[BODY].states[slot].vx >= 0 ? 1 : -1
    @lean_speed = sign_y * sign_v > 0 ? rel : -rel
  end

  def spring(a_idx, spring_idx, b_idx, slot, strength)
    s = @springs[spring_idx]
    a = @parts[a_idx].states[slot]
    b = @parts[b_idx].states[slot]
    dx = a.x - b.x
    dy = a.y - b.y
    len = F16.max_abs(dx, dy)
    return unless len.abs >= 3

    dx = F16.div(dx, len)
    dy = F16.div(dy, len)
    stretch = len - s.rest
    fx = F16.mul(dx, F16.mul(stretch, s.stiffness))
    fy = F16.mul(dy, F16.mul(stretch, s.stiffness))
    rel_v = F16.mul(F16.mul(dx, a.vx - b.vx) + F16.mul(dy, a.vy - b.vy), s.damping)
    fx += F16.mul(dx, rel_v)
    fy += F16.mul(dy, rel_v)
    fx = F16.mul(fx, strength)
    fy = F16.mul(fy, strength)
    a.fx -= fx
    a.fy -= fy
    b.fx += fx
    b.fy += fy
  end

  # delta[to] = (velocity, force * inv_mass) * dt
  def derivative(from, to, dt)
    @parts.each do |p|
      src = p.states[from]
      dst = p.states[to]
      dst.x = F16.mul(src.vx, dt)
      dst.y = F16.mul(src.vy, dt)
      k = F16.mul(dt, p.inv_mass)
      dst.vx = F16.mul(src.fx, k)
      dst.vy = F16.mul(src.fy, k)
    end
  end

  # out = base + delta / 2
  def blend(out, base, delta)
    @parts.each do |p|
      o = p.states[out]
      b = p.states[base]
      d = p.states[delta]
      o.x = b.x + (d.x >> 1)
      o.y = b.y + (d.y >> 1)
      o.vx = b.vx + (d.vx >> 1)
      o.vy = b.vy + (d.vy >> 1)
    end
  end

  def integrate(dt)
    accumulate_forces(@cur)
    derivative(@cur, 2, dt)
    blend(4, @cur, 2)
    accumulate_forces(4)
    derivative(4, 3, dt >> 1)
    blend(4, @cur, 3)
    blend(@nxt, @cur, 2)
    blend(@nxt, @nxt, 3)

    [FRONT_WHEEL, REAR_WHEEL].each do |i|
      s = @parts[i].states[@cur]
      n = @parts[i].states[@nxt]
      n.angle = s.angle + F16.mul(dt, s.av)
      n.av = s.av + F16.mul(dt, F16.mul(@parts[i].ang_factor, s.torque))
    end
  end

  def detect_collisions(slot)
    result = Track::COLLIDE_NONE
    xs = [FRONT_WHEEL, REAR_WHEEL, RIDER].map { |i| @parts[i].states[slot].x }
    @track.update_visible_range(xs.min - RADII[0], xs.max + RADII[0], @parts[RIDER].states[slot].y)

    front = @parts[FRONT_WHEEL].states[slot]
    rear = @parts[REAR_WHEEL].states[slot]
    ax = front.x - rear.x
    ay = front.y - rear.y
    len = F16.max_abs(ax, ay)
    ax = F16.div(ax, len)
    up_x = -F16.div(ay, len)
    up_y = ax

    [BODY, FRONT_WHEEL, REAR_WHEEL, RIDER].each do |i|
      s = @parts[i].states[slot]
      if i == BODY
        s.x += up_x
        s.y += up_y
      end
      hit = @track.detect_collision(s, @parts[i].shape)
      if i == BODY
        s.x -= up_x
        s.y -= up_y
      end

      @normal_x = @track.collision_normal_x
      @normal_y = @track.collision_normal_y
      @rider_down = true if i == RIDER && hit != Track::COLLIDE_NONE
      @front_wheel_on_ground = true if i == FRONT_WHEEL && hit != Track::COLLIDE_NONE

      if hit == Track::COLLIDE_TOUCH
        @hit_part = i
        result = Track::COLLIDE_TOUCH
      elsif hit == Track::COLLIDE_DEEP
        @hit_part = i
        result = Track::COLLIDE_DEEP
        break
      end
    end
    result
  end

  def resolve_collision(slot)
    part = @parts[@hit_part]
    s = part.states[slot]
    s.x += F16.mul(@normal_x, 3276)
    s.y += F16.mul(@normal_y, 3276)

    wheel = @hit_part == REAR_WHEEL || @hit_part == FRONT_WHEEL
    if @input[:brake] && wheel && s.av < 6553
      grip = TIRE_GRIP - @brake_grip_loss
      damping = 13107
      ang_damping = 39321
      friction = 26214 - @brake_grip_loss
      bounce = 26214 - @brake_grip_loss
    else
      grip = TIRE_GRIP
      damping = TIRE_DAMPING
      ang_damping = TIRE_ANGULAR_DAMPING
      friction = @friction
      bounce = @bounce
    end

    len = F16.max_abs(@normal_x, @normal_y)
    @normal_x = F16.div(@normal_x, len)
    @normal_y = F16.div(@normal_y, len)
    nx = @normal_x
    ny = @normal_y
    vx = s.vx
    vy = s.vy
    v_normal = -(F16.mul(vx, nx) + F16.mul(vy, ny))
    v_tangent = -(F16.mul(vx, -ny) + F16.mul(vy, nx))
    new_av = F16.mul(grip, s.av) - F16.mul(damping, F16.div(v_tangent, part.radius))
    tangent = F16.mul(friction, v_tangent) - F16.mul(ang_damping, F16.mul(s.av, part.radius))
    normal = -F16.mul(bounce, v_normal)
    s.av = new_av
    s.vx = F16.mul(-tangent, -ny) + F16.mul(-normal, nx)
    s.vy = F16.mul(-tangent, nx) + F16.mul(-normal, ny)
  end
end
