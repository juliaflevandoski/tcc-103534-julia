require "test_helper"

class AttemptDetailPresentationTest < ActionDispatch::IntegrationTest
  setup do
    suffix = SecureRandom.hex(6)
    @teacher = Teacher.create!(name: "Prof", username: "det_t_#{suffix}", email: "det_t_#{suffix}@example.test", password: "secret123")
    @school_class = @teacher.school_classes.create!(name: "Turma detalhe", active: true)
    @activity = @school_class.activities.create!(title: "Aula detalhe", published: true)
    @student = Student.create!(name: "Aluno detalhe", username: "det_s_#{suffix}", email: "det_s_#{suffix}@example.test", password: "secret123")
    @school_class.class_students.create!(student: @student, active: true)
    exercise = @teacher.exercises.create!(title: "Quiz detalhe", exercise_type: :quiz, object: {
      "questions" => [
        {
          "question_type" => "multiple_choice",
          "statement" => "Escolha A.",
          "options" => [ { "id" => "a", "text" => "A" }, { "id" => "b", "text" => "B" } ],
          "correct_option_ids" => [ "a" ]
        }
      ]
    })
    link = @activity.activity_exercises.create!(exercise:, position: 1, points: 10)
    @attempt = Exercises::QuizSubmission.call(activity_exercise: link, student: @student, answers: { "0" => "b" }).attempt
  end

  test "student sees header metrics, textual correctness markers and navigation" do
    login(@student, "student")

    get exercise_attempt_url(@attempt)

    assert_response :success
    assert_select "main.attempt-result-page .attempt-result-header h1", text: "Quiz detalhe"
    assert_select ".attempt-result-score", minimum: 2
    assert_select "li.attempt-question-card.is-incorrect .result-status--incorrect", text: "Incorreta"
    assert_select "nav.attempt-result-navigation a", text: "Resultados", count: 1
    assert_select "div.attempt-result-navigation", count: 0
    assert_select "main a", text: "Resultados", count: 1
    assert_select "a.button", text: "Tentar novamente"
  end

  test "teacher sees indicators but no detailed answer feedback" do
    login(@teacher, "teacher")

    get exercise_attempt_url(@attempt)

    assert_response :success
    assert_select ".attempt-result-header .result-status", text: "Tentativa oficial"
    assert_select "li.attempt-question-card", count: 0
    assert_select ".attempt-result-page", text: /Esta tentativa não possui feedback detalhado para exibição\./
    assert_select "a", text: "Tentar novamente", count: 0
  end

  private

  def login(user, role)
    post login_url, params: { role:, username: user.username, password: "secret123" }
  end
end
