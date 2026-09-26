require "app/f16.rb"
require "app/levels_data.rb"
require "app/track.rb"
require "app/physics.rb"
require "app/renderer.rb"
require "app/game.rb"
require "app/progress.rb"
require "app/ui.rb"
require "app/demos_data.rb"
require "app/demo.rb"
require "app/hud.rb"
require "app/menu.rb"
require "app/app.rb"

module Main
  SAVE_FILE = "progress.txt"

  def tick
    $app ||= App.new(Progress.load(DR.read_save_data(SAVE_FILE), LEVELS.map(&:size)),
                     save: ->(text) { DR.write_save_data(SAVE_FILE, text) })
    $app.tick(inputs, outputs.primitives)
  end

  def reset
    $app = nil
  end
end

DR.reset
