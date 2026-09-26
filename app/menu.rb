# Start screen: browse levels, tracks and bikes (locked ones are marked), then ride.
class Menu
  ROWS = %i[level track bike graphics head start].freeze
  LABELS = { level: "Level", track: "Track", bike: "Bike", graphics: "Graphics", head: "Head", start: "Ride!" }.freeze

  attr_reader :level, :track, :bike
  attr_accessor :sprites, :face

  def initialize(progress)
    @progress = progress
    @row = ROWS.index(:track)
    @level = 0
    @track = 0
    @bike = 0
    @sprites = true
    @face = false
  end

  def select(level, track, bike)
    @level = level
    @track = track
    @bike = bike
  end

  # Returns :start, :changed (selection moved to another track/bike) or nil.
  def handle(keys)
    if keys.up then @row = (@row - 1) % ROWS.size
    elsif keys.down then @row = (@row + 1) % ROWS.size
    elsif keys.enter then return playable? ? :start : nil
    elsif keys.d then return DEMOS.key?("#{@level}_#{@track}") ? :demo : nil
    elsif keys.left then return change(-1)
    elsif keys.right then return change(1)
    end
    nil
  end

  def draw(out)
    UI.panel(out, 30, 150, 520, 470)
    UI.label(out, 290, 580, "GRAVITY DEFIED", 48, anchor_x: 0.5)
    ROWS.each_with_index do |row, i|
      y = 510 - i * 60
      selected = i == @row
      out << { x: 50, y: y - 26, w: 480, h: 52, r: 220, g: 240, b: 220, path: :solid } if selected
      if row == :start
        draw_start(out, y, selected)
      else
        UI.label(out, 70, y, LABELS[row], 28, shade: UI::MUTED)
        UI.label(out, 190, y, "<  #{value(row)}  >", 26, shade: open?(row) ? UI::INK : UI::MUTED)
        UI.lock(out, 505, y) unless open?(row)
      end
    end
    draw_records(out)
    UI.label(out, 30, 125, lock_reason, 22, color: [170, 0, 0]) unless playable?
    UI.label(out, 30, 90, "Up/Down: choose   Left/Right: change   Enter: ride", 20, shade: UI::MUTED)
  end

  private

  def change(delta)
    case ROWS[@row]
    when :level
      @level = (@level + delta) % Game::LEAGUES.size
      @track = 0
    when :track
      @track = (@track + delta) % LEVELS[@level].size
    when :bike
      @bike = (@bike + delta) % Game::BIKES.size
    when :graphics
      @sprites = !@sprites
      return nil
    when :head
      @face = !@face
      return nil
    else
      return nil
    end
    :changed
  end

  def playable?
    %i[level track bike].all? { |row| open?(row) }
  end

  def open?(row)
    case row
    when :level then @progress.level_open?(@level)
    when :track then @progress.level_open?(@level) && @progress.track_open?(@level, @track)
    when :bike then @progress.bike_open?(@bike)
    else true
    end
  end

  def draw_start(out, y, selected)
    if playable?
      UI.label(out, 290, y, LABELS[:start], 34, anchor_x: 0.5, color: selected ? [0, 120, 0] : nil)
    else
      UI.lock(out, 220, y)
      UI.label(out, 300, y, "Locked", 34, anchor_x: 0.5, shade: UI::MUTED)
    end
  end

  # What to finish to open the current selection.
  def lock_reason
    if !open?(:level)
      "Finish all Easy or Medium tracks to open #{Game::LEAGUES[@level]}"
    elsif !open?(:track)
      "Finish \"#{LEVELS[@level][@track - 1][:name]}\" to open this track"
    elsif !open?(:bike)
      "Finish all #{Game::LEAGUES[@bike - 1]} tracks to get the #{Game::BIKES[@bike]} bike"
    end
  end

  def value(row)
    case row
    when :level then Game::LEAGUES[@level]
    when :track then "#{@track + 1}. #{LEVELS[@level][@track][:name]}"
    when :bike then Game::BIKES[@bike]
    when :graphics then @sprites ? "Sprites" : "Lines"
    when :head then @face ? "Face" : "Helmet"
    end
  end

  def draw_records(out)
    UI.panel(out, 870, 330, 380, 290)
    UI.label(out, 1060, 590, "Best times", 30, anchor_x: 0.5)
    UI.label(out, 1060, 552, "#{LEVELS[@level][@track][:name]}  ·  #{Game::BIKES[@bike]}", 22,
             anchor_x: 0.5, shade: UI::MUTED)
    times = @progress.records(@level, @track, @bike)
    if times.empty?
      UI.label(out, 1060, 480, "No times yet", 24, anchor_x: 0.5, shade: UI::MUTED)
    else
      times.each_with_index do |time, i|
        UI.label(out, 1060, 500 - i * 40, "#{i + 1}.  #{UI.format_time(time)}", 28, anchor_x: 0.5)
      end
    end
    done = @progress.completed_count(@level)
    UI.label(out, 1060, 360, "#{done} of #{LEVELS[@level].size} #{Game::LEAGUES[@level]} tracks done", 20,
             anchor_x: 0.5, shade: UI::MUTED)
  end
end
