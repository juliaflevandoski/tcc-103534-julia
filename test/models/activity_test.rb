require "test_helper"

class ActivityTest < ActiveSupport::TestCase
  test "copies the class teacher" do
    teacher = Teacher.create!(name: "Ana", username: "ana", email: "ana@example.com", password: "secret123")
    school_class = SchoolClass.create!(teacher:, name: "História")
    activity = Activity.create!(school_class:, title: "Aula 1")

    assert_equal teacher, activity.teacher
  end
end
