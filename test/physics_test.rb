require_relative "test_helper"

# Compares the physics step by step against traces recorded from the TypeScript port.
# Fixture name: trace_<level>_<track>_<bike>[_gas].txt, each line
# "<step> <result> <x,y,angle,vx,vy per part>".
class PhysicsTest < Minitest::Test
  # Same script as the TypeScript tracer: phases of gas / lean back / lean forward / brake.
  def self.scripted_input(step, gas_only)
    return [1, 0] if gas_only

    phase = (step / 40) % 4
    [phase == 3 ? -1 : 1, { 1 => -1, 2 => 1 }.fetch(phase, 0)]
  end

  Dir[File.join(__dir__, "fixtures/trace_*.txt")].sort.each do |path|
    name = File.basename(path, ".txt")
    define_method("test_matches_#{name}") do
      level, track, bike = name.split("_")[1, 3].map(&:to_i)
      gas_only = name.end_with?("_gas")
      physics = Physics.new(Track.new(LEVELS[level][track]), bike: bike)
      expected = File.readlines(path, chomp: true)
      refute_empty expected

      expected.each_with_index do |line, step|
        physics.set_input(*PhysicsTest.scripted_input(step, gas_only))
        result = physics.update
        cur = physics.instance_variable_get(:@cur)
        parts = physics.parts.map { |p| s = p.states[cur]; [s.x, s.y, s.angle, s.vx, s.vy].join(",") }
        assert_equal line, "#{step} #{result} #{parts.join(' ')}", "#{name} diverged at step #{step}"
        physics.reset if result == Physics::RIDER_DOWN
      end
    end
  end

  # The original (and the TypeScript port) loop forever here; the port crashes the rider instead.
  def test_does_not_hang_when_the_sub_step_collapses
    physics = Physics.new(Track.new(LEVELS[2][5]), bike: 3)
    results = Array.new(1500) do |step|
      physics.set_input(*PhysicsTest.scripted_input(step, false))
      physics.update.tap { |r| physics.reset if r == Physics::RIDER_DOWN }
    end

    assert_includes results, Physics::RIDER_DOWN
  end
end
