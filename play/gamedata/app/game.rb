# Game flow from the original app loop: fixed 30 ms outer steps, two physics steps each,
# crash/restart timers, the one-second "goal" run-out and the results screen.
class Game
  LEAGUES = %w[Easy Medium Pro].freeze
  BIKES = %w[100cc 175cc 220cc 325cc].freeze
  FRAME_MS = 1000 / 60.0
  OUTER_STEP_MS = 30
  PHYSICS_LOOPS = 2

  attr_reader :physics, :track, :league, :track_no, :message, :result_time

  def initialize(league, track_no, bike)
    @now = 0.0
    start(league, track_no, bike)
  end

  def start(league, track_no, bike)
    @league = league
    @track_no = track_no
    @track = Track.new(LEVELS[league][track_no])
    if @physics
      @physics.track = @track
      @physics.bike = bike
    else
      @physics = Physics.new(@track, bike: bike)
      @physics.screen_min_wh = Renderer::VIEW_H
    end
    restart
  end

  def track_count = LEVELS[@league].size
  def league_name = LEAGUES[@league]
  def bike_name = BIKES[@physics.bike]
  def finished? = !@result_time.nil?

  def time_10ms = F16.idiv(@game_time_ms, 10)

  def restart(show_name: true)
    @physics.reset
    @game_time_ms = 0
    @crash_deadline = nil
    @forced_restart_at = nil
    @timer_running = false
    @goal_until = nil
    @result_time = nil
    @accumulator = 0.0
    @message = nil
    show_message(@track.name, 3000) if show_name
  end

  # throttle: +1 gas / -1 brake, lean: -1 back / +1 forward.
  def tick(throttle, lean)
    @now += FRAME_MS
    @message = nil if @message && @now >= @message[:until]
    return if finished?

    @physics.set_input(throttle, lean)
    return goal_step if @goal_until

    @accumulator += FRAME_MS
    while @accumulator >= OUTER_STEP_MS
      outer_step
      @accumulator -= OUTER_STEP_MS
      break if @goal_until || finished?
    end
  end

  private

  def show_message(text, ms)
    @message = { text: text, until: @now + ms }
  end

  def outer_step
    if @forced_restart_at
      restart if @now >= @forced_restart_at
      return
    end

    PHYSICS_LOOPS.times do
      @game_time_ms += 20 if @timer_running
      result = @physics.update

      if result == Physics::CRASHED && @crash_deadline.nil?
        @crash_deadline = @now + 3000
        show_message("Crashed", 3000)
      end

      if @crash_deadline && @crash_deadline < @now
        restart
        return
      end

      if result == Physics::RIDER_DOWN
        show_message("Crashed", 3000)
        wait = @crash_deadline ? [@crash_deadline - @now, 1000].min : 1000
        @forced_restart_at = @now + [wait, 0].max
        return
      end

      if result == Physics::BEFORE_START
        @game_time_ms = 0
      elsif result == Physics::FINISHED_CROSSED || result == Physics::FINISHED_HALF_STEP
        @game_time_ms -= 10 if result == Physics::FINISHED_HALF_STEP
        start_goal
        return
      end

      @timer_running = result != Physics::BEFORE_START
    end

    @physics.sync_render_state
  end

  def start_goal
    @goal_until = @now + 1000
    @last_goal_step = @now
    show_message(@physics.front_wheel_on_ground ? "Finished" : "Wheelie!", 1000)
  end

  # After the finish line the bike keeps rolling for a second before the results.
  def goal_step
    if @now >= @goal_until
      finish
      return
    end

    while @now - @last_goal_step >= OUTER_STEP_MS
      PHYSICS_LOOPS.times do
        next unless @physics.update == Physics::RIDER_DOWN

        finish
        return
      end
      @physics.sync_render_state
      @last_goal_step += OUTER_STEP_MS
    end
  end

  def finish
    @goal_until = nil
    @result_time = F16.idiv(@game_time_ms, 10)
  end
end
