require "test_helper"

class StudentFillBlanksAttemptTest < ActionDispatch::IntegrationTest
  test "student answers inline blanks and receives server-calculated feedback" do
    _teacher, student, exercise, activity_exercise = create_student_fill_blanks(points: 9)
    post login_url, params: { role: "student", username: student.username, password: "secret123" }

    get exercise_url(exercise, activity_exercise_id: activity_exercise.id)

    assert_response :success
    assert_select "form[action='#{exercise_attempts_path}']"
    assert_select "input.fill-blank-input[name='exercise_attempt[answers][1]']", count: 1
    assert_select "input.fill-blank-input[name='exercise_attempt[answers][2]']", count: 1
    assert_select "input[name='exercise_attempt[correct]']", count: 0
    assert_select "input[name='exercise_attempt[score]']", count: 0
    assert_not_includes response.body, "Brasília"
    assert_not_includes response.body, "<pre>"

    assert_difference("ExerciseAttempt.count") do
      post exercise_attempts_url, params: {
        exercise_attempt: {
          activity_exercise_id: activity_exercise.id,
          answers: { "1" => "  BRASIL ", "2" => "Brasilia", "99" => "forged" },
          correct: { blanks: [] },
          score: 99
        }
      }
    end

    attempt = ExerciseAttempt.order(:id).last
    assert_redirected_to exercise_attempt_url(attempt)
    assert_equal 4, attempt.score
    assert_equal 4, student.reload.student_stat.xp
    assert_equal [ true, false ], attempt.correct.fetch("blanks").pluck("correct")
    assert_equal({ "1" => "  BRASIL ", "2" => "Brasilia" }, attempt.answer.fetch("answers"))

    follow_redirect!
    assert_response :success
    assert_select "ol.fill-blanks-feedback li", count: 2
    assert_includes response.body, "Resposta correta: Brasília"
    assert_select "a", text: "Tentar novamente"

    patch exercise_attempt_url(attempt), params: { exercise_attempt: { correct: { blanks: [] }, score: 99 } }
    assert_redirected_to root_url
    assert_equal 4, attempt.reload.score
    assert_equal [ true, false ], attempt.correct.fetch("blanks").pluck("correct")
  end

  test "retry preserves history and awards XP only once even after soft delete" do
    _teacher, student, _exercise, activity_exercise = create_student_fill_blanks(points: 9)
    post login_url, params: { role: "student", username: student.username, password: "secret123" }
    answers = { "1" => "Brasil", "2" => "Brasília" }

    post exercise_attempts_url, params: { exercise_attempt: { activity_exercise_id: activity_exercise.id, answers: } }
    first_attempt = ExerciseAttempt.order(:id).last
    assert_equal 9, first_attempt.score
    assert_equal 9, student.reload.student_stat.xp

    first_attempt.update!(active: false)
    post exercise_attempts_url, params: { exercise_attempt: { activity_exercise_id: activity_exercise.id, answers: } }
    second_attempt = ExerciseAttempt.order(:id).last

    assert_equal 2, ExerciseAttempt.where(student:, activity_exercise:).count
    assert_equal 9, second_attempt.score
    assert_equal false, second_attempt.correct.fetch("xp_award_claimed")
    assert_equal 9, student.reload.student_stat.xp
  end

  test "student cannot submit blanks from an unrelated class" do
    _teacher, _enrolled_student, _exercise, activity_exercise = create_student_fill_blanks(points: 9)
    student = Student.create!(name: "Outro aluno", username: "otherfill", email: "otherfill@example.com", password: "secret123")
    post login_url, params: { role: "student", username: student.username, password: "secret123" }

    assert_no_difference("ExerciseAttempt.count") do
      post exercise_attempts_url, params: {
        exercise_attempt: { activity_exercise_id: activity_exercise.id, answers: { "1" => "Brasil" } }
      }
    end

    assert_redirected_to root_url
  end

  private

  def create_student_fill_blanks(points:)
    teacher = Teacher.create!(name: "Professora Lacunas", username: "fillteacher", email: "fillteacher@example.com", password: "secret123")
    school_class = teacher.school_classes.create!(name: "Geografia", active: true)
    activity = school_class.activities.create!(title: "Complete as lacunas", published: true)
    student = Student.create!(name: "Aluno Lacunas", username: "fillstudent", email: "fillstudent@example.com", password: "secret123")
    school_class.class_students.create!(student:, active: true)
    exercise = teacher.exercises.create!(
      title: "Capitais",
      exercise_type: :fill_blanks,
      object: {
        "text_template" => "A capital do {{1}} é {{2}}.",
        "blanks" => { "1" => "Brasil", "2" => "Brasília" }
      }
    )
    activity_exercise = activity.activity_exercises.create!(exercise:, position: 1, points:)
    [ teacher, student, exercise, activity_exercise ]
  end
end
