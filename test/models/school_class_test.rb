require "test_helper"

class SchoolClassTest < ActiveSupport::TestCase
  test "generates a unique access code" do
    teacher = Teacher.create!(name: "Ana", username: "ana", email: "ana@example.com", password: "secret123")
    school_class = SchoolClass.create!(teacher:, name: "História")

    assert_match(/\A[A-Z0-9]{8}\z/, school_class.access_code)
  end
end
