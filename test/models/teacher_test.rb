require "test_helper"

class TeacherTest < ActiveSupport::TestCase
  test "stores passwords as a bcrypt digest" do
    teacher = Teacher.create!(name: "Ana", username: "ana", email: "ana@example.com", password: "secret123")

    assert_not_equal "secret123", teacher.reload.password_digest
    assert teacher.authenticate("secret123")
    assert_not teacher.authenticate("wrong")
  end
end
