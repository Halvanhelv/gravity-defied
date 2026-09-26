require_relative "test_helper"

class ProgressTest < Minitest::Test
  def setup
    @progress = Progress.new([10, 10, 10])
  end

  def test_starts_like_the_original
    assert @progress.bike_open?(0)
    refute @progress.bike_open?(1)
    assert @progress.level_open?(1)
    refute @progress.level_open?(2)
    assert @progress.track_open?(0, 0)
    refute @progress.track_open?(0, 1)
    refute @progress.track_open?(2, 0)
  end

  def test_finishing_a_track_opens_the_next_one
    report = @progress.finish(0, 0, 0, 900)

    assert_equal 1, report.new_track
    assert @progress.track_open?(0, 1)
    assert_nil report.new_level
  end

  def test_finishing_the_last_track_opens_next_level_and_bike
    report = @progress.finish(0, 9, 0, 900)

    assert_equal 2, report.new_level
    assert_equal 1, report.new_bike
    assert @progress.track_open?(2, 0)
    assert @progress.bike_open?(1)
  end

  def test_bike_unlocks_never_go_backwards
    @progress.finish(1, 9, 0, 900)
    @progress.finish(0, 9, 0, 900)

    assert @progress.bike_open?(2)
  end

  def test_keeps_three_fastest_times_per_track_and_bike
    [900, 700, 800, 1000].each { |t| @progress.finish(0, 0, 0, t) }
    report = @progress.finish(0, 0, 0, 750)

    assert_equal [700, 750, 800], @progress.records(0, 0, 0)
    assert_equal 2, report.place
    assert_empty @progress.records(0, 0, 1)
    assert_nil @progress.finish(0, 0, 0, 5000).place
  end

  def test_dump_and_load_round_trip
    @progress.finish(0, 9, 0, 900)
    @progress.finish(2, 0, 1, 1234)
    loaded = Progress.load(@progress.dump, [10, 10, 10])

    assert_equal @progress.dump, loaded.dump
    assert_equal [1234], loaded.records(2, 0, 1)
  end

  def test_load_ignores_missing_or_garbage_files
    assert Progress.load(nil, [10, 10, 10]).track_open?(0, 0)
    assert Progress.load("nonsense\nbike x", [10, 10, 10]).bike_open?(0)
  end
end
