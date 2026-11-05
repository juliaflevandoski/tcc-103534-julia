require "test_helper"

class StudentLevelTest < ActiveSupport::TestCase
  def assert_progress(result, level:, total_xp:, xp_in_level:, xp_for_next:, percent:)
    assert_equal level, result.level
    assert_equal total_xp, result.total_xp
    assert_equal xp_in_level, result.xp_in_level
    assert_equal xp_for_next, result.xp_for_next
    assert_in_delta percent, result.percent, 0.001
  end

  test "zero xp is level one" do
    assert_progress StudentLevel.call(0), level: 1, total_xp: 0, xp_in_level: 0, xp_for_next: 100, percent: 0
  end

  test "nil xp is treated as zero" do
    assert_progress StudentLevel.call(nil), level: 1, total_xp: 0, xp_in_level: 0, xp_for_next: 100, percent: 0
  end

  test "50 xp is half of level one" do
    assert_progress StudentLevel.call(50), level: 1, total_xp: 50, xp_in_level: 50, xp_for_next: 50, percent: 50
  end

  test "99 xp is one xp short of level two" do
    assert_progress StudentLevel.call(99), level: 1, total_xp: 99, xp_in_level: 99, xp_for_next: 1, percent: 99
  end

  test "100 xp reaches level two with zero progress" do
    assert_progress StudentLevel.call(100), level: 2, total_xp: 100, xp_in_level: 0, xp_for_next: 100, percent: 0
  end

  test "150 xp is half of level two" do
    assert_progress StudentLevel.call(150), level: 2, total_xp: 150, xp_in_level: 50, xp_for_next: 50, percent: 50
  end

  test "250 xp is half of level three" do
    assert_progress StudentLevel.call(250), level: 3, total_xp: 250, xp_in_level: 50, xp_for_next: 50, percent: 50
  end

  test "300 xp reaches level four with zero progress" do
    assert_progress StudentLevel.call(300), level: 4, total_xp: 300, xp_in_level: 0, xp_for_next: 100, percent: 0
  end

  test "negative xp is clamped to level one without negative progress" do
    assert_progress StudentLevel.call(-25), level: 1, total_xp: 0, xp_in_level: 0, xp_for_next: 100, percent: 0
  end

  test "large xp values progress correctly" do
    assert_progress StudentLevel.call(1_000_000_075), level: 10_000_001, total_xp: 1_000_000_075,
      xp_in_level: 75, xp_for_next: 25, percent: 75
  end

  test "calculation does not create or modify records" do
    student = Student.create!(name: "Aluno Nivel", username: "levelstudent", email: "levelstudent@example.com", password: "secret123")
    stat = StudentStat.create!(student:, xp: 250, level: 1)
    updated_at = stat.updated_at

    assert_no_difference -> { StudentStat.count } do
      StudentLevel.call(stat.xp)
    end
    stat.reload
    assert_equal 1, stat.level
    assert_equal 250, stat.xp
    assert_equal updated_at, stat.updated_at
  end
end
