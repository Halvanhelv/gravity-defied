# In-game overlay: track and timer, progress bar, messages and the results panel.
module Hud
  def self.draw(out, game, progress, report, demo: false)
    UI.label(out, 16, 704, "#{game.league_name}  #{game.track_no + 1}/#{game.track_count}  " \
                           "#{game.track.name}  ·  #{game.bike_name}", 22)
    UI.label(out, 1264, 704, UI.format_time(game.time_10ms), 28, anchor_x: 1)
    UI.bar(out, 16, 660, 300, 8, game.physics.progress / 65536.0, Renderer::FAR_GROUND)
    UI.label(out, 640, 520, game.message[:text], 40, anchor_x: 0.5) if game.message

    if game.finished? && demo
      demo_results(out, game)
    elsif game.finished?
      results(out, game, progress, report)
    else
      UI.label(out, 16, 30, "Arrows/WASD: ride   R: restart   G: graphics   H: head   Esc: menu", 18, shade: UI::MUTED)
    end
  end

  def self.results(out, game, progress, report)
    lines = []
    lines << ["New record!  ##{report.place}", 26, [170, 0, 0]] if report&.place
    progress.records(game.league, game.track_no, game.physics.bike).each_with_index do |time, i|
      lines << ["#{i + 1}.  #{UI.format_time(time)}", 24, nil]
    end
    if report
      lines << ["Unlocked track: #{LEVELS[game.league][report.new_track][:name]}", 22, [0, 120, 0]] if report.new_track
      lines << ["Unlocked level: #{Game::LEAGUES[report.new_level]}", 22, [0, 120, 0]] if report.new_level
      lines << ["Unlocked bike: #{Game::BIKES[report.new_bike]}", 22, [0, 120, 0]] if report.new_bike
    end

    height = 190 + lines.size * 34
    top = 360 + height / 2
    UI.panel(out, 390, top - height, 500, height)
    UI.label(out, 640, top - 40, "Finished!", 40, anchor_x: 0.5)
    UI.label(out, 640, top - 90, UI.format_time(game.result_time), 36, anchor_x: 0.5)
    lines.each_with_index do |(text, size, color), i|
      UI.label(out, 640, top - 140 - i * 34, text, size, anchor_x: 0.5, color: color)
    end
    enter = next_track_open?(game, progress) ? "Enter: next track" : "Enter: menu"
    UI.label(out, 640, top - height + 35, "#{enter}   R: retry   Esc: menu", 22, anchor_x: 0.5)
  end

  def self.demo_results(out, game)
    UI.panel(out, 390, 250, 500, 220)
    UI.label(out, 640, 430, "Finished!", 40, anchor_x: 0.5)
    UI.label(out, 640, 370, UI.format_time(game.result_time), 36, anchor_x: 0.5)
    UI.label(out, 640, 290, "Enter: menu", 22, anchor_x: 0.5)
  end

  def self.next_track_open?(game, progress)
    next_no = game.track_no + 1
    next_no < game.track_count && progress.track_open?(game.league, next_no)
  end
end
