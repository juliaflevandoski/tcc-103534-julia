require "test_helper"

class ResultsDashboardTest < ActionDispatch::IntegrationTest
  setup do
    @teacher = Teacher.create!(name: "Professora", username: "reportteacher", email: "reportteacher@example.com", password: "secret123")
    @school_class = @teacher.school_classes.create!(name: "Turma de resultados", active: true)
    @activity = @school_class.activities.create!(title: "Resultados", published: true)
    @student = create_student("reportstudent")
    @other_student = create_student("reportother")
    [ @student, @other_student ].each do |student|
      @school_class.class_students.create!(student:, active: true)
    end

    other_teacher = Teacher.create!(name: "Outro professor", username: "otherreportteacher", email: "otherreportteacher@example.com", password: "secret123")
    @other_school_class = other_teacher.school_classes.create!(name: "Turma privada", active: true)
  end

  test "teacher sees scoped status, official normalized results, equal-student class average, and item breakdowns" do
    quiz = create_quiz_link(points: 10)
    ordering = create_ordering_link(points: 20)
    fill_blanks = create_fill_blanks_link(points: 10)
    crossword = create_crossword_link(points: 10)
    zero_points = create_zero_point_link
    memory = create_memory_link(points: 10)

    official_quiz_attempt = Exercises::QuizSubmission.call(
      activity_exercise: quiz,
      student: @student,
      answers: { "0" => "a", "1" => "wrong" }
    ).attempt
    later_quiz_attempt = Exercises::QuizSubmission.call(
      activity_exercise: quiz,
      student: @student,
      answers: { "0" => "a", "1" => "42" }
    ).attempt
    official_quiz_attempt.update!(active: false)
    other_quiz_attempt = Exercises::QuizSubmission.call(
      activity_exercise: quiz,
      student: @other_student,
      answers: { "0" => "a", "1" => "42" }
    ).attempt
    ordering_attempt = Exercises::OrderingSubmission.call(
      activity_exercise: ordering,
      student: @student,
      ordered_ids: %w[item-1 item-3 item-2 item-4]
    ).attempt
    fill_blanks_attempt = Exercises::FillBlanksSubmission.call(
      activity_exercise: fill_blanks,
      student: @student,
      answers: { "1" => "incorreta", "2" => "também incorreta" }
    ).attempt
    crossword_attempt = Exercises::CrosswordSubmission.call(
      activity_exercise: crossword,
      student: @student,
      answer: { "cells" => crossword_cells(crossword.exercise.object) }
    ).attempt
    Exercises::QuizSubmission.call(
      activity_exercise: zero_points,
      student: @student,
      answers: { "0" => "wrong" }
    )
    start_memory_game(memory)
    memory_attempt = complete_memory_game(memory, @other_student)
    quiz.update!(points: 20)
    ordering.update!(points: 0)

    post login_url, params: { role: "teacher", username: @teacher.username, password: "secret123" }
    get exercise_attempts_url, params: { school_class_id: @school_class.id }

    assert_response :success
    assert_includes response.body, "Turma de resultados"
    assert_not_includes response.body, @other_school_class.name
    assert_includes response.body, "Média das médias individuais"
    assert_includes response.body, "62.5%"
    assert_includes response.body, "Média oficial do exercício"
    assert_includes response.body, "75.0%"
    assert_includes response.body, "50.0%"
    assert_includes response.body, "10 / 20 pontos"
    assert_includes response.body, "Pendente"
    assert_includes response.body, "Em andamento"
    assert_includes response.body, "Nota oficial"
    assert_includes response.body, "Tentativa não oficial"
    assert_includes response.body, "Desativada"
    assert_includes response.body, "5 / 10 pontos"
    assert_includes response.body, "Escolha A."
    assert_includes response.body, "Desempenho por questão/item"
    assert_includes response.body, "0 / 0 pontos"
    assert_includes response.body, "2 pares encontrados"
    assert_includes response.body, "erros registrados"
    assert_not_includes response.body, "APPLE"
    assert_not_includes response.body, "PEAR"
    [ official_quiz_attempt, later_quiz_attempt, other_quiz_attempt, fill_blanks_attempt, crossword_attempt ].each do |attempt|
      assert_equal 10, ActivityResults.points_possible(attempt:)
    end
    assert_equal 20, ActivityResults.points_possible(attempt: ordering_attempt)
    assert_equal 10, ActivityResults.points_possible(attempt: memory_attempt)
    assert_nil ActivityResults.activity_average_percentage(activity_exercise: zero_points)
    assert_equal official_quiz_attempt, ActivityResults.official_attempt(activity_exercise: quiz, student: @student)
    assert_not_equal official_quiz_attempt, later_quiz_attempt
  end

  test "student sees only their class report and can read an inactive official attempt" do
    quiz = create_quiz_link(points: 10)
    official_attempt = Exercises::QuizSubmission.call(
      activity_exercise: quiz,
      student: @student,
      answers: { "0" => "a", "1" => "wrong" }
    ).attempt
    official_attempt.update!(active: false)

    post login_url, params: { role: "student", username: @student.username, password: "secret123" }
    get exercise_attempts_url, params: { school_class_id: @school_class.id }

    assert_response :success
    assert_includes response.body, "Turma de resultados"
    assert_includes response.body, "Concluída"
    assert_includes response.body, "5 / 10"
    assert_includes response.body, "50.0%"
    assert_includes response.body, "Nota oficial"
    assert_includes response.body, "Desativada"
    assert_select "a[href='#{exercise_attempt_path(official_attempt)}']", text: "Detalhes", count: 1

    get exercise_attempt_url(official_attempt)
    assert_response :success

    get exercise_attempts_url, params: { school_class_id: @other_school_class.id }
    assert_redirected_to root_url
  end

  test "teacher cannot filter results to a class owned by another teacher" do
    post login_url, params: { role: "teacher", username: @teacher.username, password: "secret123" }

    get exercise_attempts_url, params: { school_class_id: @other_school_class.id }

    assert_redirected_to root_url
    assert_equal "Turma inválida.", flash[:alert]
  end

  test "legacy attempts without saved maximum keep their score and stay out of normalized metrics" do
    quiz = create_quiz_link(points: 20)
    grade = Exercises::QuizGrader.call(
      quiz: quiz.exercise.object,
      answers: { "0" => "a", "1" => "wrong" },
      points: quiz.points
    )
    legacy_attempt = ExerciseAttempt.create!(
      student: @student,
      activity_exercise: quiz,
      answer: grade.answer,
      correct: grade.correct,
      score: grade.score
    )
    quiz.update!(points: 30)

    assert_equal legacy_attempt, ActivityResults.official_attempt(activity_exercise: quiz, student: @student)
    assert_nil ActivityResults.points_possible(attempt: legacy_attempt)
    assert_nil ActivityResults.attempt_percentage(attempt: legacy_attempt)
    assert_nil ActivityResults.activity_average_percentage(activity_exercise: quiz)

    post login_url, params: { role: "student", username: @student.username, password: "secret123" }
    get exercise_attempts_url, params: { school_class_id: @school_class.id }

    assert_response :success
    assert_includes response.body, "10 / máximo não registrado"
    assert_includes response.body, "Máximo histórico não registrado"
    assert_select ".results-metric-label", text: "Sua média de notas oficiais"
    assert_select ".results-metric-value", text: "Sem notas elegíveis"
  end

  test "inactive incomplete memory remains visible but is not resumable or official" do
    memory = create_memory_link(points: 10)
    attempt = start_memory_game(memory)
    attempt.update!(active: false)

    post login_url, params: { role: "student", username: @student.username, password: "secret123" }
    get exercise_attempts_url, params: { school_class_id: @school_class.id }

    assert_response :success
    assert_includes response.body, "Pendente"
    assert_includes response.body, "Desativada"
    assert_nil ActivityResults.official_attempt(activity_exercise: memory, student: @student)

    get exercise_attempt_url(attempt)

    assert_response :success
    assert_select ".attempt-result-header .result-status", text: "Desativada", count: 1
    assert_select ".attempt-result-header .result-status", text: "Em andamento", count: 0
    assert_select "a", text: "Voltar ao jogo", count: 0
  end

  private

  def create_student(username)
    Student.create!(name: username, username:, email: "#{username}@example.com", password: "secret123")
  end

  def create_exercise_link(type, object, title:, points:)
    exercise = @teacher.exercises.create!(title:, exercise_type: type, object:)
    @activity.activity_exercises.create!(exercise:, position: @activity.activity_exercises.active.maximum(:position).to_i + 1, points:)
  end

  def create_quiz_link(points:)
    create_exercise_link(:quiz, {
      "questions" => [
        {
          "question_type" => "multiple_choice",
          "statement" => "Escolha A.",
          "options" => [ { "id" => "a", "text" => "A" }, { "id" => "b", "text" => "B" } ],
          "correct_option_ids" => [ "a" ]
        },
        { "question_type" => "short_answer", "statement" => "Responda 42.", "correct_answer" => "42" }
      ]
    }, title: "Quiz da turma", points:)
  end

  def create_ordering_link(points:)
    create_exercise_link(:ordering, {
      "instructions" => "Ordene os itens.",
      "item_type" => "words",
      "items" => %w[item-1 item-2 item-3 item-4].map { |id| { "id" => id, "label" => id.upcase } },
      "correct_order" => %w[item-1 item-2 item-3 item-4]
    }, title: "Ordenação da turma", points:)
  end

  def create_zero_point_link
    create_exercise_link(:quiz, {
      "questions" => [
        { "question_type" => "short_answer", "statement" => "Responda.", "correct_answer" => "certo" }
      ]
    }, title: "Exercício sem pontos", points: 0)
  end

  def create_fill_blanks_link(points:)
    create_exercise_link(:fill_blanks, {
      "text_template" => "{{1}} e {{2}}",
      "blanks" => { "1" => "um", "2" => "dois" }
    }, title: "Lacunas da turma", points:)
  end

  def create_crossword_link(points:)
    result = Exercises::CrosswordBuilder.call(
      instructions: "Complete a cruzadinha.",
      seed: 29,
      words: [ { word: "APPLE", clue: "Fruta" }, { word: "PEAR", clue: "Outra fruta" } ]
    )
    create_exercise_link(:crossword, result.object, title: "Cruzadinha da turma", points:)
  end

  def crossword_cells(object)
    object.fetch("grid").fetch("cells").each_with_index.flat_map do |row, row_index|
      row.each_with_index.filter_map do |cell, column_index|
        [ "#{row_index}-#{column_index}", "Z" ] if cell.present?
      end
    end.to_h
  end

  def create_memory_link(points:)
    result = Exercises::MemoryGameBuilder.call(object: {
      "instructions" => "Combine os pares.",
      "pair_type" => "word_word",
      "pairs" => [
        { "left" => { "type" => "word", "content" => "DOG" }, "right" => { "type" => "word", "content" => "CÃO" } },
        { "left" => { "type" => "word", "content" => "CAT" }, "right" => { "type" => "word", "content" => "GATO" } }
      ]
    })
    create_exercise_link(:memory_game, result.object, title: "Memória da turma", points:)
  end

  def start_memory_game(activity_exercise)
    game = Exercises::MemoryGamePlay.start(object: activity_exercise.exercise.object, points: activity_exercise.points)
    ExerciseAttempt.create!(student: @student, activity_exercise:, answer: game.fetch("answer"), correct: game.fetch("correct"), score: 0)
  end

  def complete_memory_game(activity_exercise, student)
    game = Exercises::MemoryGamePlay.start(object: activity_exercise.exercise.object, points: activity_exercise.points)
    answer = game.fetch("answer")
    score = 0
    pairs = game.fetch("correct").fetch("deck").group_by { |card| card.fetch("pair_id") }
    pairs.each_value do |cards|
      first_reveal = Exercises::MemoryGamePlay.reveal(
        answer:, correct: game.fetch("correct"), card_id: cards[0].fetch("id"), points: activity_exercise.points
      )
      second_reveal = Exercises::MemoryGamePlay.reveal(
        answer: first_reveal.answer, correct: game.fetch("correct"), card_id: cards[1].fetch("id"), points: activity_exercise.points
      )
      answer = second_reveal.answer
      score = second_reveal.score
    end
    ExerciseAttempt.create!(student:, activity_exercise:, answer:, correct: game.fetch("correct"), score:)
  end
end
