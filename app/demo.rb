# Plays back a recorded run: per-frame [throttle, lean] from run-length encoded inputs.
class Demo
  attr_reader :bike

  def self.for(level, track)
    data = DEMOS["#{level}_#{track}"]
    data && new(data[:bike], data[:runs])
  end

  def initialize(bike, runs)
    @bike = bike
    @runs = runs
    @run = 0
    @left = runs.empty? ? 0 : runs[0][2]
  end

  # Next frame's input; idles once the recording ends.
  def next_input
    return [0, 0] if @run >= @runs.size

    throttle, lean, = @runs[@run]
    @left -= 1
    if @left <= 0
      @run += 1
      @left = @runs[@run][2] if @run < @runs.size
    end
    [throttle, lean]
  end
end
