require "test_helper"

class StudentGamificationPanelTest < ActionDispatch::IntegrationTest
  setup do
    @teacher = Teacher.create!(name: "Professor", username: "gamprof", email: "gamprof@example.com", password: "secret123")
    @school_class = @teacher.school_classes.create!(name: "Turma Gamificada", active: true)
    @activity = @school_class.activities.create!(title: "Aula Gamificada", published: true)
    @student = Student.create!(name: "Aluno", username: "gamstudent", email: "gamstudent@example.com", password: "secret123")
    @school_class.class_students.create!(student: @student, active: true)
  end

  test "student without stat sees level one, zero xp and locked badges without records being created" do
    sign_in(@student, "student")

    assert_no_difference([ "StudentStat.count", "ExerciseAttempt.count" ]) do
      get exercise_attempts_url
    end

    assert_response :success
    assert_select ".gamification-panel .gamification-level-number strong", text: "1"
    assert_select ".gamification-xp strong", text: "0"
    assert_select "progress.gamification-progress[value='0']"
    assert_select ".gamification-next", text: /faltam 100 XP para o nível 2/
    assert_select ".gamification-badge", count: 4
    assert_select ".gamification-badge--locked", count: 4
    assert_select ".gamification-badge--earned", count: 0
  end

  test "student sees calculated level, total xp and progress instead of the stored level" do
    stat = StudentStat.create!(student: @student, xp: 250, level: 1)
    updated_at = stat.updated_at
    sign_in(@student, "student")

    assert_no_difference([ "StudentStat.count" ]) { get exercise_attempts_url }

    assert_select ".gamification-level-number strong", text: "3"
    assert_select ".gamification-xp strong", text: "250"
    assert_select "progress.gamification-progress[value='50']"
    assert_select ".gamification-next", text: /50 \/ 100 XP neste nível.*faltam 50 XP para o nível 4/
    assert_equal [ 250, 1, updated_at ], stat.reload.then { |s| [ s.xp, s.level, s.updated_at ] }
    assert_select ".gamification-badge--earned[data-badge='explorer']"
  end

  test "earned and locked badges are distinguished and all four are shown" do
    link = create_quiz_link
    Exercises::QuizSubmission.call(activity_exercise: link, student: @student, answers: { "0" => "a", "1" => "42" })
    sign_in(@student, "student")

    get exercise_attempts_url

    assert_select ".gamification-badge", count: 4
    %w[first_steps perfect_score mission_accomplished].each do |id|
      assert_select ".gamification-badge--earned[data-badge='#{id}']"
    end
    assert_select ".gamification-badge--locked[data-badge='explorer']"
    assert_select ".gamification-badge-name", text: "Primeiros Passos"
    assert_select ".gamification-badge-name", text: "Nota Máxima"
    assert_select ".gamification-badge-name", text: "Missão Cumprida"
    assert_select ".gamification-badge-name", text: "Explorador"
    assert_select ".gamification-badge-description", count: 4
    assert_select ".gamification-xp strong", text: "10"
  end

  test "results listing is preserved for the student" do
    create_quiz_link
    sign_in(@student, "student")

    get exercise_attempts_url

    assert_select "h1", text: "Resultados"
    assert_select ".results-class-title", text: "Turma Gamificada"
    assert_select ".results-activity-title", text: "Aula Gamificada"
    assert_select ".result-status--pending", text: "Pendente"
  end

  test "teacher does not receive the student gamification panel" do
    sign_in(@teacher, "teacher")

    get exercise_attempts_url

    assert_response :success
    assert_select ".gamification-panel", count: 0
    assert_select "h1", text: "Resultados"
  end

  test "anonymous visitors are still redirected to login" do
    get exercise_attempts_url

    assert_redirected_to login_url
    assert_select ".gamification-panel", count: 0
  end

  private

  def sign_in(user, role)
    post login_url, params: { role:, username: user.username, password: "secret123" }
  end

  def create_quiz_link
    exercise = @teacher.exercises.create!(title: "Quiz", exercise_type: :quiz, object: {
      "questions" => [
        {
          "question_type" => "multiple_choice",
          "statement" => "Escolha a resposta correta.",
          "options" => [ { "id" => "a", "text" => "A" }, { "id" => "b", "text" => "B" } ],
          "correct_option_ids" => [ "a" ]
        },
        { "question_type" => "short_answer", "statement" => "Responda 42.", "correct_answer" => "42" }
      ]
    })
    @activity.activity_exercises.create!(exercise:, position: 1, points: 10)
  end
end
