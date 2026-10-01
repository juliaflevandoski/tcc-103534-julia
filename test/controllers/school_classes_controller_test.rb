require "test_helper"

class SchoolClassesControllerTest < ActionDispatch::IntegrationTest
  test "lists active classes" do
    sign_in_as_teacher
    get school_classes_url

    assert_response :success
    assert_select "h1", "Turmas"
  end

  test "creates a class and assigns an access code" do
    teacher = Teacher.create!(name: "Ana", username: "ana", email: "ana@example.com", password: "secret123")
    sign_in_as_teacher(teacher)

    assert_difference("SchoolClass.count") do
      post school_classes_url, params: { school_class: { name: "História" } }
    end

    assert_redirected_to school_class_url(SchoolClass.order(:id).last)
    assert SchoolClass.order(:id).last.access_code.present?
  end

  private

  def sign_in_as_teacher(teacher = Teacher.create!(name: "Bia", username: "bia", email: "bia@example.com", password: "secret123"))
    post login_url, params: { role: "teacher", username: teacher.username, password: "secret123" }
  end
end
