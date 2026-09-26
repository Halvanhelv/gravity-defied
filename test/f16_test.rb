require_relative "test_helper"

class F16Test < Minitest::Test
  def test_idiv_floors_integers
    assert_equal 2, F16.idiv(7, 3)
    assert_equal(-3, F16.idiv(-7, 3))
  end

  def test_tdiv_truncates_toward_zero_like_cpp
    assert_equal(-2, F16.tdiv(-7, 3))
    assert_equal(-2, F16.tdiv(7, -3))
    assert_equal 2, F16.tdiv(-7, -3)
  end

  def test_mul_and_div_are_16_16_fixed_point
    assert_equal 98304, F16.mul(65536, 98304)
    assert_equal 32768, F16.div(65536, 131072)
    assert_equal(-32768, F16.div(-65536, 131072))
  end

  def test_i32_wraps_like_int32
    assert_equal(-2147483648, F16.i32(2147483648))
    assert_equal 0, F16.i32(4294967296)
  end
end
