# What the player has unlocked and their best times, with the original unlock rules:
# start with the 100cc bike, Easy and Medium open with their first track each;
# finishing a track opens the next one, finishing a level's last track opens the next
# level and a bigger bike (175cc after Easy, 220cc after Medium, 325cc after Pro).
class Progress
  RECORDS_KEPT = 3
  LAST_LEVEL = 2
  LAST_BIKE = 3

  # What finishing a track changed, for the results screen.
  Report = Struct.new(:place, :new_track, :new_level, :new_bike)

  attr_reader :max_bike, :max_level

  def self.load(text, track_counts)
    progress = new(track_counts)
    progress.restore(text) if text
    progress
  end

  def initialize(track_counts)
    @track_counts = track_counts
    @max_bike = 0
    @max_level = 1
    @max_track = [0, 0, -1]
    @records = {}
  end

  def level_open?(level) = level <= @max_level
  def track_open?(level, track) = track <= @max_track[level]
  def bike_open?(bike) = bike <= @max_bike
  def tracks_open(level) = @max_track[level] + 1

  # Best times in 1/100 s, fastest first.
  def records(level, track, bike)
    @records[[level, track, bike]] || []
  end

  def completed_count(level)
    (0...@track_counts[level]).count { |t| (0..LAST_BIKE).any? { |b| !records(level, t, b).empty? } }
  end

  def finish(level, track, bike, time)
    report = Report.new(add_record(level, track, bike, time), nil, nil, nil)
    last = @track_counts[level] - 1

    if track < last && @max_track[level] < track + 1
      @max_track[level] = track + 1
      report.new_track = track + 1
    end

    if track == last
      if @max_bike < level + 1
        @max_bike = level + 1
        report.new_bike = level + 1
      end
      if @max_level < LAST_LEVEL
        @max_level += 1
        report.new_level = @max_level
      end
      @max_track[@max_level] = 0 if @max_track[@max_level] < 0
    end
    report
  end

  def dump
    lines = ["gravity-defied 1", "bike #{@max_bike}", "level #{@max_level}", "tracks #{@max_track.join(' ')}"]
    @records.each { |(l, t, b), times| lines << "record #{l} #{t} #{b} #{times.join(' ')}" }
    lines.join("\n") + "\n"
  end

  def restore(text)
    text.split("\n").each do |line|
      key, *values = line.split(" ")
      numbers = values.map(&:to_i)
      case key
      when "bike" then @max_bike = numbers[0].clamp(0, LAST_BIKE)
      when "level" then @max_level = numbers[0].clamp(1, LAST_LEVEL)
      when "tracks" then @max_track = numbers if numbers.size == 3
      when "record" then @records[numbers[0, 3]] = numbers.drop(3).sort.first(RECORDS_KEPT)
      end
    end
  end

  private

  # Returns the 1-based place if the time made the table, else nil.
  def add_record(level, track, bike, time)
    times = (records(level, track, bike) + [time]).sort.first(RECORDS_KEPT)
    @records[[level, track, bike]] = times
    index = times.index(time)
    index && index + 1
  end
end
