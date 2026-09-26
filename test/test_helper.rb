require "minitest/autorun"

APP_FILES = %w[f16 levels_data track physics renderer game progress ui demos_data demo hud menu app].freeze
APP_FILES.each { |f| require File.expand_path("../app/#{f}", __dir__) }

# Stand-ins for DragonRuby's inputs: key_down flags plus the up_down / left_right axes.
Keys = Struct.new(:up, :down, :left, :right, :enter, :escape, :r, :g, :h, :d)
Keyboard = Struct.new(:key_down)
Inputs = Struct.new(:keyboard, :up_down, :left_right)

def inputs(throttle: 0, lean: 0, **pressed)
  keys = Keys.new(*Keys.members.map { |k| pressed.fetch(k, false) })
  Inputs.new(Keyboard.new(keys), throttle, lean)
end
