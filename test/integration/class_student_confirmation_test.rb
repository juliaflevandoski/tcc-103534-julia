require "test_helper"

class ClassStudentConfirmationTest < ActionDispatch::IntegrationTest
  parallelize(workers: 1)

  setup do
    @teacher = create_user(Teacher, "confirmation-teacher")
    @school_class = @teacher.school_classes.create!(name: "Turma inicial")
    @other_class = @teacher.school_classes.create!(name: "Outra turma")
    @student = create_user(Student, "confirmation-student")
    @other_student = create_user(Student, "confirmation-other-student")
    @school_class.class_students.create!(student: @other_student)

    login(@teacher)
    follow_redirect!
  end

  test "manual enrollment creation and update confirm success and preserve destinations" do
    post class_students_url, params: {
      class_id: @school_class.id,
      class_student: { student_id: @student.id, class_id: @school_class.id }
    }

    membership = ClassStudent.find_by!(student: @student)
    assert_redirected_to class_student_url(membership, class_id: @school_class.id)
    assert_equal "Matrícula criada com sucesso.", flash[:notice]

    patch class_student_url(membership), params: {
      class_id: @school_class.id,
      class_student: { student_id: @student.id, class_id: @other_class.id }
    }

    assert_redirected_to class_student_url(membership, class_id: @other_class.id)
    assert_equal "Matrícula atualizada com sucesso.", flash[:notice]
    assert_equal @other_class.id, membership.reload.class_id
  end

  test "invalid enrollment creation and update do not show success" do
    @school_class.class_students.create!(student: @student)

    post class_students_url, params: {
      class_student: { student_id: @student.id, class_id: @school_class.id }
    }

    assert_response :unprocessable_entity
    assert_nil flash[:notice]

    membership = @school_class.class_students.find_by!(student: @student)
    patch class_student_url(membership), params: {
      class_student: { student_id: @other_student.id, class_id: @school_class.id }
    }

    assert_response :unprocessable_entity
    assert_nil flash[:notice]
  end

  test "unauthorized enrollment mutation does not show success" do
    foreign_teacher = create_user(Teacher, "confirmation-foreign-teacher")
    foreign_class = foreign_teacher.school_classes.create!(name: "Turma alheia")
    membership = foreign_class.class_students.create!(student: @student)

    patch class_student_url(membership), params: {
      class_student: { student_id: @student.id, class_id: foreign_class.id }
    }

    assert_redirected_to root_url
    assert_nil flash[:notice]
    assert_equal foreign_class.id, membership.reload.class_id
  end

  private

  def create_user(klass, prefix)
    identifier = "#{prefix}-#{SecureRandom.hex(6)}"
    klass.create!(name: identifier, username: identifier, email: "#{identifier}@example.com", password: "secret123")
  end

  def login(user)
    post login_url, params: { role: "teacher", username: user.username, password: "secret123" }
  end
end
