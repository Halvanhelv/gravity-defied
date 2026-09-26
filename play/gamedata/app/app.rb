# Switches between the menu, a ride and a demo playback; records finishes and asks main.rb to save.
class App
  def initialize(progress, save:)
    @progress = progress
    @save = save
    @menu = Menu.new(progress)
    @game = Game.new(0, 0, 0)
    @scene = :menu
    @report = nil
    @demo = nil
  end

  def tick(inputs, out)
    keys = inputs.keyboard.key_down
    @scene == :menu ? menu_tick(keys) : ride_tick(keys, inputs)

    Renderer.new(out, sprites: @menu.sprites, face: @menu.face).draw(@game.physics, @game.track)
    if @scene == :menu
      @menu.draw(out)
    else
      Hud.draw(out, @game, @progress, @report, demo: !@demo.nil?)
    end
  end

  private

  # The menu shows the selected track behind it, bike waiting at the start.
  def menu_tick(keys)
    case @menu.handle(keys)
    when :changed then @game.start(@menu.level, @menu.track, @menu.bike)
    when :start then ride(@menu.level, @menu.track)
    when :demo then play_demo(@menu.level, @menu.track)
    end
    # A demo must start on a fresh frame to replay exactly as recorded.
    @game.tick(0, 0) if @scene == :menu
  end

  def ride_tick(keys, inputs)
    if keys.escape
      back_to_menu
      return
    end
    @menu.sprites = !@menu.sprites if keys.g
    @menu.face = !@menu.face if keys.h

    if @game.finished?
      if @demo then back_to_menu if keys.enter
      elsif keys.r then ride(@game.league, @game.track_no)
      elsif keys.enter then next_track
      end
      return
    end

    if @demo
      @game.tick(*@demo.next_input)
      return
    end

    @game.restart if keys.r
    @game.tick(inputs.up_down, inputs.left_right)
    record_finish if @game.finished?
  end

  def ride(level, track)
    @game.start(level, track, @menu.bike)
    @report = nil
    @demo = nil
    @scene = :ride
  end

  # Replays a recorded run looking like a normal ride; nothing it does is saved.
  def play_demo(level, track)
    @demo = Demo.for(level, track)
    return unless @demo

    @game.start(level, track, @demo.bike)
    @report = nil
    @scene = :ride
  end

  def next_track
    if Hud.next_track_open?(@game, @progress)
      ride(@game.league, @game.track_no + 1)
    else
      back_to_menu
    end
  end

  def back_to_menu
    @demo = nil
    @menu.select(@game.league, @game.track_no, @menu.bike)
    @game.start(@menu.level, @menu.track, @menu.bike)
    @scene = :menu
  end

  def record_finish
    @report = @progress.finish(@game.league, @game.track_no, @game.physics.bike, @game.result_time)
    @save.call(@progress.dump)
  end
end
