require "test_helper"

class StudentOrderingAttemptTest < ActionDispatch::IntegrationTest
  test "student orders items and receives proportional score and the expected sequence" do
    _teacher, student, exercise, activity_exercise = create_student_ordering(points: 10)
    post login_url, params: { role: "student", username: student.username, password: "secret123" }

    get exercise_url(exercise, activity_exercise_id: activity_exercise.id)

    assert_response :success
    assert_select "form[data-controller='ordering-player']"
    assert_select "ol.ordering-player-list > li[data-ordering-player-target='item']", count: 4
    assert_select "input[name='exercise_attempt[ordered_ids][]']", count: 4
    assert_select "button[aria-label='Mover item para cima']", count: 4
    assert_not_includes response.body, "correct_order"

    assert_difference("ExerciseAttempt.count") do
      post exercise_attempts_url, params: {
        exercise_attempt: {
          activity_exercise_id: activity_exercise.id,
          ordered_ids: %w[item-1 item-3 item-2 item-4],
          correct: { positions: [] },
          score: 99
        }
      }
    end

    attempt = ExerciseAttempt.order(:id).last
    assert_redirected_to exercise_attempt_url(attempt)
    assert_equal 5, attempt.score
    assert_equal 5, student.reload.student_stat.xp
    assert_equal %w[item-1 item-3 item-2 item-4], attempt.answer.fetch("ordered_ids")
    assert_equal [ true, false, false, true ], attempt.correct.fetch("positions").pluck("correct")

    follow_redirect!
    assert_response :success
    assert_select "ol.ordering-feedback-list li", count: 4
    assert_includes response.body, "Sequência correta:"
    assert_select "a", text: "Tentar novamente"

    patch exercise_attempt_url(attempt), params: { exercise_attempt: { correct: { positions: [] }, score: 99 } }
    assert_redirected_to root_url
    assert_equal 5, attempt.reload.score
    assert_equal [ true, false, false, true ], attempt.correct.fetch("positions").pluck("correct")
  end

  test "retry preserves history and awards XP only once even after soft delete" do
    _teacher, student, _exercise, activity_exercise = create_student_ordering(points: 10)
    post login_url, params: { role: "student", username: student.username, password: "secret123" }
    ordered_ids = %w[item-1 item-2 item-3 item-4]

    post exercise_attempts_url, params: { exercise_attempt: { activity_exercise_id: activity_exercise.id, ordered_ids: } }
    first_attempt = ExerciseAttempt.order(:id).last
    assert_equal 10, first_attempt.score
    assert_equal 10, student.reload.student_stat.xp

    first_attempt.update!(active: false)
    post exercise_attempts_url, params: { exercise_attempt: { activity_exercise_id: activity_exercise.id, ordered_ids: } }
    second_attempt = ExerciseAttempt.order(:id).last

    assert_equal 2, ExerciseAttempt.where(student:, activity_exercise:).count
    assert_equal 10, second_attempt.score
    assert_equal false, second_attempt.correct.fetch("xp_award_claimed")
    assert_equal 10, student.reload.student_stat.xp
  end

  test "student cannot submit ordering from an unrelated class" do
    _teacher, _enrolled_student, _exercise, activity_exercise = create_student_ordering(points: 10)
    student = Student.create!(name: "Outro aluno", username: "otherordering", email: "otherordering@example.com", password: "secret123")
    post login_url, params: { role: "student", username: student.username, password: "secret123" }

    assert_no_difference("ExerciseAttempt.count") do
      post exercise_attempts_url, params: {
        exercise_attempt: { activity_exercise_id: activity_exercise.id, ordered_ids: %w[item-1 item-2] }
      }
    end

    assert_redirected_to root_url
  end

  private

  def create_student_ordering(points:)
    teacher = Teacher.create!(name: "Professor Ordenação", username: "orderingteacher", email: "orderingteacher@example.com", password: "secret123")
    school_class = teacher.school_classes.create!(name: "Ciências", active: true)
    activity = school_class.activities.create!(title: "Ordem do universo", published: true)
    student = Student.create!(name: "Aluno Ordenação", username: "orderingstudent", email: "orderingstudent@example.com", password: "secret123")
    school_class.class_students.create!(student:, active: true)
    exercise = teacher.exercises.create!(
      title: "Organize os conceitos",
      exercise_type: :ordering,
      object: {
        "instructions" => "Organize do menor para o maior.",
        "item_type" => "words",
        "items" => [
          { "id" => "item-1", "label" => "Estrela" },
          { "id" => "item-2", "label" => "Planeta" },
          { "id" => "item-3", "label" => "Sistema solar" },
          { "id" => "item-4", "label" => "Galáxia" }
        ],
        "correct_order" => %w[item-1 item-2 item-3 item-4]
      }
    )
    activity_exercise = activity.activity_exercises.create!(exercise:, position: 1, points:)
    [ teacher, student, exercise, activity_exercise ]
  end
end
