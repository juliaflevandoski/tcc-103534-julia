require "test_helper"

class LessonCompletionIndicatorTest < ActionDispatch::IntegrationTest
  parallelize(workers: 1)

  setup do
    suffix = SecureRandom.hex(6)
    @teacher = Teacher.create!(name: "Professor", username: "lci-t-#{suffix}", email: "lci-t-#{suffix}@example.com", password: "secret123")
    @student = Student.create!(name: "Aluno", username: "lci-s-#{suffix}", email: "lci-s-#{suffix}@example.com", password: "secret123")
    @school_class = @teacher.school_classes.create!(name: "Turma", active: true)
    @school_class.class_students.create!(student: @student, active: true)
    @activity = @school_class.activities.create!(title: "Aula", published: true)
  end

  test "student who answered every exercise sees completed" do
    first = link(create_quiz("Um"), 1)
    second = link(create_quiz("Dois"), 2)
    submit(first)
    submit(second)

    visit_as_student
    assert_select ".result-status--completed", text: "Aula concluída", count: 1
    assert_select ".result-status--in-progress", count: 0
    assert_select "p", text: "Publicada", count: 1
  end

  test "student who answered only part sees in progress" do
    first = link(create_quiz("Um"), 1)
    link(create_quiz("Dois"), 2)
    submit(first)

    visit_as_student
    assert_select ".result-status--in-progress", text: "Em andamento", count: 1
    assert_select ".result-status--completed", count: 0
  end

  test "student without attempts sees in progress" do
    link(create_quiz("Um"), 1)

    visit_as_student
    assert_select ".result-status--in-progress", text: "Em andamento", count: 1
    assert_select ".result-status--completed", count: 0
  end

  test "empty lesson keeps the notice and shows no indicator" do
    visit_as_student
    assert_select ".empty-lesson-notice", text: "Esta aula ainda não possui exercícios disponíveis.", count: 1
    assert_select ".result-status", count: 0
  end

  test "lesson with only inactive exercises shows no indicator" do
    hidden = link(create_quiz("Oculto"), 1)
    hidden.exercise.update!(active: false)
    inactive_link = link(create_quiz("Vínculo inativo"), 2)
    inactive_link.update!(active: false)

    visit_as_student
    assert_select ".empty-lesson-notice", count: 1
    assert_select ".result-status", count: 0
  end

  test "inactive exercises do not block completion" do
    active = link(create_quiz("Ativo"), 1)
    hidden = link(create_quiz("Oculto"), 2)
    hidden.exercise.update!(active: false)
    submit(active)

    visit_as_student
    assert_select ".result-status--completed", text: "Aula concluída", count: 1
  end

  test "incomplete memory game does not complete the lesson" do
    memory = link(create_memory, 1)
    started = Exercises::MemoryGamePlay.start(object: memory.exercise.object, points: memory.points)
    ExerciseAttempt.create!(student: @student, activity_exercise: memory, answer: started.fetch("answer"), correct: started.fetch("correct"), score: 0)

    visit_as_student
    assert_select ".result-status--in-progress", text: "Em andamento", count: 1
    assert_select ".result-status--completed", count: 0
  end

  test "teacher does not see the completion indicator" do
    submit(link(create_quiz("Um"), 1))

    post login_url, params: { role: "teacher", username: @teacher.username, password: "secret123" }
    get activity_url(@activity)

    assert_response :success
    assert_select ".result-status", count: 0
    assert_no_match(/Aula concluída|Em andamento/, response.body)
  end

  private

  def visit_as_student
    post login_url, params: { role: "student", username: @student.username, password: "secret123" }
    get activity_url(@activity)
    assert_response :success
  end

  def link(exercise, position)
    @activity.activity_exercises.create!(exercise:, position:, points: 10)
  end

  def submit(activity_exercise)
    Exercises::QuizSubmission.call(activity_exercise:, student: @student, answers: { "0" => "Resposta" })
  end

  def create_quiz(title)
    @teacher.exercises.create!(title:, exercise_type: :quiz, object: {
      "questions" => [ { "question_type" => "short_answer", "statement" => "Pergunta?", "correct_answer" => "Resposta" } ]
    })
  end

  def create_memory
    game = Exercises::MemoryGameBuilder.call(object: {
      instructions: "Combine os pares.",
      pair_type: "word_word",
      pairs: [
        { left: { type: "word", content: "DOG" }, right: { type: "word", content: "CACHORRO" } },
        { left: { type: "word", content: "CAT" }, right: { type: "word", content: "GATO" } }
      ]
    })
    @teacher.exercises.create!(title: "Memória", exercise_type: :memory_game, object: game.object)
  end
end
