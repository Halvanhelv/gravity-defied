require_relative "test_helper"

# Every bundled demo must replay to the finish through the real menu -> demo path.
class DemoTest < Minitest::Test
  DEMOS.each_key do |key|
    define_method("test_demo_#{key}_finishes_and_saves_nothing") do
      level, track = key.split("_").map(&:to_i)
      saved = nil
      progress = Progress.new(LEVELS.map(&:size))
      app = App.new(progress, save: ->(text) { saved = text })
      app.instance_variable_get(:@menu).select(level, track, 0)
      app.tick(inputs(d: true), [])
      game = app.instance_variable_get(:@game)

      20_000.times do
        break if game.finished?

        app.tick(inputs, [])
      end

      assert game.finished?, "demo #{key} did not reach the finish"
      assert_nil saved
      assert_empty progress.records(level, track, DEMOS[key][:bike])
    end
  end
end
