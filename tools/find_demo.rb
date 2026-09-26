# Finds a clean run through a track by beam search over held inputs, then writes it as a demo.
# The physics is deterministic, so the recorded per-frame inputs replay identically in the game.
#
#   ruby tools/find_demo.rb <level> <track> <bike> [beam] [segment_frames]
#
# Output: data/demos/<level>_<track>.txt  ("bike N" then "throttle lean frames" lines).

%w[f16 levels_data track physics renderer game ui].each { |f| require_relative "../app/#{f}" }

level, track, bike, beam, segment = ARGV.map(&:to_i)
beam = 200 if beam.nil? || beam.zero?
segment = 6 if segment.nil? || segment.zero?
max_segments = 1500

ACTIONS = [1, 0, -1].product([-1, 0, 1]).freeze
Node = Struct.new(:game, :inputs)

def front_x(game)
  s = game.physics.parts
  [s[Physics::FRONT_WHEEL].states[5].x, s[Physics::REAR_WHEEL].states[5].x].max
end

def dead?(game)
  game.physics.crashed || game.physics.rider_down || game.message&.fetch(:text) == "Crashed"
end

start = Game.new(level, track, bike)
beam_nodes = [Node.new(start, [])]
started_at = Time.now
finished = nil

max_segments.times do |seg|
  children = []
  beam_nodes.each do |node|
    ACTIONS.each do |throttle, lean|
      game = Marshal.load(Marshal.dump(node.game))
      segment.times { game.tick(throttle, lean) }
      next if dead?(game)

      child = Node.new(game, node.inputs + [[throttle, lean]])
      if game.finished?
        finished = child if finished.nil? || game.result_time < finished.game.result_time
        next
      end
      children << child
    end
  end
  break if finished

  if children.empty?
    warn "all runs crashed at segment #{seg}"
    exit 1
  end
  # Furthest first; keep one node per small x bucket for variety, then fill up.
  children.sort_by! { |c| -front_x(c.game) }
  buckets = {}
  picked = children.select { |c| buckets[front_x(c.game) >> 14] ? false : (buckets[front_x(c.game) >> 14] = true) }
  beam_nodes = (picked + (children - picked)).first(beam)
  if (seg % 25).zero?
    best = beam_nodes.first.game
    best.physics.render_states # progress reads the render snapshot
    warn format("seg %4d  progress %5.1f%%  %.0fs", seg, best.physics.progress * 100.0 / 65536, Time.now - started_at)
  end
end

abort "no finish within #{max_segments} segments" unless finished

runs = []
finished.inputs.each do |throttle, lean|
  if runs.last && runs.last[0] == throttle && runs.last[1] == lean
    runs.last[2] += segment
  else
    runs << [throttle, lean, segment]
  end
end

dir = File.expand_path("../data/demos", __dir__)
Dir.mkdir(dir) unless Dir.exist?(dir)
path = File.join(dir, "#{level}_#{track}.txt")
File.write(path, "bike #{bike}\n" + runs.map { |r| r.join(" ") }.join("\n") + "\n")
puts "#{LEVELS[level][track][:name]}: finished in #{UI.format_time(finished.game.result_time)} " \
     "(#{finished.inputs.size * segment} frames, #{Time.now - started_at}s search) -> #{path}"

require_relative "bundle_demos"
