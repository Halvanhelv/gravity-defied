require_relative "test_helper"

# Menu -> ride -> results flow, driven through fake DragonRuby inputs.
class AppTest < Minitest::Test
  def setup
    @saved = nil
    @progress = Progress.new(LEVELS.map(&:size))
    @app = App.new(@progress, save: ->(text) { @saved = text })
  end

  def test_menu_browses_locked_tracks_but_does_not_start_them
    press(right: true) # cursor starts on Track
    assert_equal 1, menu.track

    press(enter: true)
    assert_equal :menu, scene

    press(left: true)
    press(enter: true)
    assert_equal :ride, scene
  end

  def test_locked_bike_cannot_be_ridden
    press(down: true) # Track -> Bike
    press(right: true)
    assert_equal 1, menu.bike

    press(enter: true)
    assert_equal :menu, scene
  end

  def test_finishing_intro_saves_a_record_and_opens_the_next_track
    press(enter: true)
    ride_until_finished

    assert_equal [game.result_time], @progress.records(0, 0, 0)
    assert_includes @saved, "record 0 0 0 #{game.result_time}"

    press(enter: true)
    assert_equal "Shorty", game.track.name
    refute game.finished?
  end

  def test_escape_returns_to_the_menu_on_the_current_track
    press(enter: true)
    press(escape: true)

    assert_equal :menu, scene
    assert_equal [0, 0], [menu.level, menu.track]
  end

  def test_screens_render_without_errors
    out = []
    @app.tick(inputs, out)
    refute_empty out.select { |p| p[:text] == "GRAVITY DEFIED" }

    press(enter: true)
    ride_until_finished
    out = []
    @app.tick(inputs, out)
    assert(out.any? { |p| p[:text] == "Finished!" })
  end

  private

  def menu = @app.instance_variable_get(:@menu)
  def scene = @app.instance_variable_get(:@scene)
  def game = @app.instance_variable_get(:@game)

  def press(times: 1, **keys)
    times.times { @app.tick(inputs(**keys), []) }
  end

  def ride_until_finished
    2000.times do
      @app.tick(inputs(throttle: 1), [])
      return if game.finished?
    end
    flunk "Intro was not finished on full gas"
  end
end
