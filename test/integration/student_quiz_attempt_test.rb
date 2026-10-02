require "test_helper"

class StudentQuizAttemptTest < ActionDispatch::IntegrationTest
  test "student submits a quiz and receives server-calculated feedback" do
    _teacher, student, exercise, activity_exercise = create_student_quiz(points: 10)
    post login_url, params: { role: "student", username: student.username, password: "secret123" }

    get exercise_url(exercise, activity_exercise_id: activity_exercise.id)

    assert_response :success
    assert_select "form[action='#{exercise_attempts_path}']"
    assert_select "input[name='exercise_attempt[answers][0]']", count: 2
    assert_select "input[type='text'][name='exercise_attempt[answers][2]']", count: 1
    assert_select "input[name='exercise_attempt[correct]']", count: 0
    assert_select "input[name='exercise_attempt[score]']", count: 0
    assert_not_includes response.body, "<pre>"

    assert_difference("ExerciseAttempt.count") do
      post exercise_attempts_url, params: {
        exercise_attempt: {
          activity_exercise_id: activity_exercise.id,
          answers: { "0" => "four", "1" => "true", "2" => "  BRASÍLIA " },
          correct: { questions: [] },
          score: 100
        }
      }
    end

    attempt = ExerciseAttempt.order(:id).last
    assert_redirected_to exercise_attempt_url(attempt)
    assert_equal 6, attempt.score
    assert_equal 6, student.reload.student_stat.xp
    assert_equal [ true, false, true ], attempt.correct.fetch("questions").pluck("correct")
    assert_equal true, attempt.correct.fetch("xp_award_claimed")

    follow_redirect!
    assert_response :success
    assert_select "ol.quiz-feedback li", count: 3
    assert_includes response.body, "Resposta correta: Falso"
    assert_select "a", text: "Tentar novamente"
  end

  test "quiz retries keep history and award XP only on the first attempt, including after soft delete" do
    _teacher, student, _exercise, activity_exercise = create_student_quiz(points: 10)
    post login_url, params: { role: "student", username: student.username, password: "secret123" }
    answers = { "0" => "four", "1" => "false", "2" => "Brasília" }

    post exercise_attempts_url, params: { exercise_attempt: { activity_exercise_id: activity_exercise.id, answers: } }
    first_attempt = ExerciseAttempt.order(:id).last
    assert_equal 10, first_attempt.score
    assert_equal 10, student.reload.student_stat.xp

    first_attempt.update!(active: false)
    post exercise_attempts_url, params: { exercise_attempt: { activity_exercise_id: activity_exercise.id, answers: } }
    second_attempt = ExerciseAttempt.order(:id).last

    assert_equal 2, ExerciseAttempt.where(student:, activity_exercise:).count
    assert_equal 10, second_attempt.score
    assert_equal false, second_attempt.correct.fetch("xp_award_claimed")
    assert_equal 10, student.reload.student_stat.xp
  end

  test "student cannot submit a quiz outside an enrolled published class" do
    _teacher, _enrolled_student, _exercise, activity_exercise = create_student_quiz(points: 10)
    student = Student.create!(name: "Aluno sem turma", username: "semquiz", email: "semquiz@example.com", password: "secret123")
    post login_url, params: { role: "student", username: student.username, password: "secret123" }

    assert_no_difference("ExerciseAttempt.count") do
      post exercise_attempts_url, params: {
        exercise_attempt: { activity_exercise_id: activity_exercise.id, answers: { "0" => "four" } }
      }
    end

    assert_redirected_to root_url
  end

  private

  def create_student_quiz(points:)
    teacher = Teacher.create!(name: "Professora Quiz", username: "quizteacher", email: "quizteacher@example.com", password: "secret123")
    school_class = teacher.school_classes.create!(name: "Matemática", active: true)
    activity = school_class.activities.create!(title: "Quiz", published: true)
    student = Student.create!(name: "Aluno Quiz", username: "quizstudent", email: "quizstudent@example.com", password: "secret123")
    school_class.class_students.create!(student:, active: true)
    exercise = teacher.exercises.create!(
      title: "Quiz de capitais",
      exercise_type: :quiz,
      object: {
        "questions" => [
          {
            "question_type" => "multiple_choice",
            "statement" => "Qual opção representa quatro?",
            "options" => [ { "id" => "four", "text" => "4" }, { "id" => "five", "text" => "5" } ],
            "correct_option_ids" => [ "four" ]
          },
          {
            "question_type" => "true_false",
            "statement" => "2 + 2 é igual a 5?",
            "correct_option_ids" => [ "false" ]
          },
          {
            "question_type" => "short_answer",
            "statement" => "Qual é a capital do Brasil?",
            "correct_answer" => "Brasília"
          }
        ]
      }
    )
    activity_exercise = activity.activity_exercises.create!(exercise:, position: 1, points:)
    [ teacher, student, exercise, activity_exercise ]
  end
end
