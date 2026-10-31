require "test_helper"

class IncompleteSubmissionPreservationTest < ActionDispatch::IntegrationTest
  parallelize(workers: 1)

  MESSAGE = "Preencha todas as respostas obrigatórias antes de enviar a atividade.".freeze

  setup do
    @teacher = create_user(Teacher, "keep-teacher")
    @school_class = @teacher.school_classes.create!(name: "Turma preservação", active: true)
    @activity = @school_class.activities.create!(title: "Aula preservação", published: true)
    @student = create_user(Student, "keep-student")
    @school_class.class_students.create!(student: @student, active: true)
    post login_url, params: { role: "student", username: @student.username, password: "secret123" }
  end

  test "quiz keeps radio choices and text while rejecting the incomplete submission" do
    link = link_for(:quiz, quiz_object)
    incomplete = { "0" => "o1", "2" => "Resposta" }

    assert_no_difference("ExerciseAttempt.count") do
      post exercise_attempts_url, params: { exercise_attempt: { activity_exercise_id: link.id, answers: incomplete } }
    end

    assert_response :unprocessable_entity
    assert_includes response.body, MESSAGE
    assert_select "input[type='radio'][name='exercise_attempt[answers][0]'][value='o1'][checked]", count: 1
    assert_select "input[type='radio'][name='exercise_attempt[answers][1]'][checked]", count: 0
    assert_select "input[type='text'][name='exercise_attempt[answers][2]'][value='Resposta']", count: 1
    assert_select "input[name='exercise_attempt[activity_exercise_id]'][value='#{link.id}']", count: 1

    assert_difference("ExerciseAttempt.count", 1) do
      post exercise_attempts_url, params: { exercise_attempt: { activity_exercise_id: link.id, answers: incomplete.merge("1" => "true") } }
    end
    assert_redirected_to exercise_attempt_url(ExerciseAttempt.order(:id).last)
  end

  test "fill blanks keeps the filled blank" do
    link = link_for(:fill_blanks, { "text_template" => "O {{1}} é {{2}}.", "blanks" => { "1" => "céu", "2" => "azul" } })

    assert_no_difference("ExerciseAttempt.count") do
      post exercise_attempts_url, params: { exercise_attempt: { activity_exercise_id: link.id, answers: { "1" => "céu", "2" => "" } } }
    end

    assert_response :unprocessable_entity
    assert_includes response.body, MESSAGE
    assert_select "input[name='exercise_attempt[answers][1]'][value='céu']", count: 1
    assert_select "input[name='exercise_attempt[answers][2]'][value='']", count: 1
    assert_not_includes response.body, "azul"

    assert_difference("ExerciseAttempt.count", 1) do
      post exercise_attempts_url, params: { exercise_attempt: { activity_exercise_id: link.id, answers: { "1" => "céu", "2" => "azul" } } }
    end
  end

  test "single sequence ordering keeps the submitted order" do
    link = link_for(:ordering, ordering_object)

    assert_no_difference("ExerciseAttempt.count") do
      post exercise_attempts_url, params: { exercise_attempt: { activity_exercise_id: link.id, ordered_ids: %w[item-3 item-1] } }
    end

    assert_response :unprocessable_entity
    assert_includes response.body, MESSAGE
    ids = css_select("li[data-item-id]").map { |node| node["data-item-id"] }
    assert_equal %w[item-3 item-1], ids.first(2)
    assert_equal %w[item-1 item-2 item-3], ids.sort

    assert_difference("ExerciseAttempt.count", 1) do
      post exercise_attempts_url, params: { exercise_attempt: { activity_exercise_id: link.id, ordered_ids: %w[item-3 item-1 item-2] } }
    end
  end

  test "multiple sentences ordering keeps each sentence order" do
    link = link_for(:ordering, sentences_object)
    submitted = [ { "id" => "s1", "ordered_ids" => %w[b a] }, { "id" => "s2", "ordered_ids" => %w[d] } ].to_json

    assert_no_difference("ExerciseAttempt.count") do
      post exercise_attempts_url, params: { exercise_attempt: { activity_exercise_id: link.id, sentences_json: submitted } }
    end

    assert_response :unprocessable_entity
    assert_includes response.body, MESSAGE
    first, second = css_select("section[data-sentence-id]")
    assert_equal %w[b a], first.css("li[data-item-id]").map { |node| node["data-item-id"] }.first(2)
    assert_equal "d", second.css("li[data-item-id]").first["data-item-id"]
    assert_equal %w[c d], second.css("li[data-item-id]").map { |node| node["data-item-id"] }.sort
  end

  test "crossword keeps typed letters and cell structure" do
    object = Exercises::CrosswordBuilder.call(
      instructions: "Complete", seed: 17, words: [ { word: "APPLE", clue: "Fruta" }, { word: "PEAR", clue: "Outra fruta" } ]
    ).object
    link = link_for(:crossword, object)
    keys = object.fetch("grid").fetch("cells").each_with_index.flat_map do |row, r|
      row.each_with_index.filter_map { |cell, c| [ "#{r}-#{c}", cell ] if cell.present? }
    end.to_h
    first_key, first_letter = keys.first
    partial = { cells: { first_key => first_letter } }.to_json

    assert_no_difference("ExerciseAttempt.count") do
      post exercise_attempts_url, params: { exercise_attempt: { activity_exercise_id: link.id, answer: partial, time_spent: 5 } }
    end

    assert_response :unprocessable_entity
    assert_includes response.body, MESSAGE
    row, column = first_key.split("-")
    assert_select "input[data-row='#{row}'][data-column='#{column}'][value='#{first_letter}']", count: 1
    filled = css_select("input[data-crossword-player-target='cell']").select { |node| node["value"].present? }
    assert_equal 1, filled.size

    assert_difference("ExerciseAttempt.count", 1) do
      post exercise_attempts_url, params: { exercise_attempt: { activity_exercise_id: link.id, answer: { cells: keys }.to_json, time_spent: 5 } }
    end
  end

  test "submitted values are escaped" do
    link = link_for(:fill_blanks, { "text_template" => "O {{1}} é {{2}}.", "blanks" => { "1" => "céu", "2" => "azul" } })

    post exercise_attempts_url, params: { exercise_attempt: { activity_exercise_id: link.id, answers: { "1" => "\"><script>x</script>", "2" => "" } } }

    assert_response :unprocessable_entity
    assert_not_includes response.body, "<script>x</script>"
  end

  test "rejected submission does not change the official attempt or reveal answers" do
    link = link_for(:quiz, quiz_object)
    post exercise_attempts_url, params: { exercise_attempt: { activity_exercise_id: link.id, answers: { "0" => "o1", "1" => "true", "2" => "Resposta" } } }
    official = ExerciseAttempt.order(:id).last

    assert_no_difference("ExerciseAttempt.count") do
      post exercise_attempts_url, params: { exercise_attempt: { activity_exercise_id: link.id, answers: { "0" => "o2" } } }
    end

    assert_response :unprocessable_entity
    assert_select "a[href='#{exercise_attempt_path(official)}']", text: "Ver resultado anterior", count: 1
    assert_equal official, ActivityResults.official_attempt(activity_exercise: link, student: @student)
  end

  test "memory game and other redirects are untouched" do
    other = ActivityExercise.maximum(:id).to_i + 100
    post exercise_attempts_url, params: { exercise_attempt: { activity_exercise_id: other, answers: { "0" => "x" } } }
    assert_redirected_to root_url
  end

  private

  def link_for(type, object)
    exercise = @teacher.exercises.create!(title: "Ex #{type}", exercise_type: type, object:)
    @activity.activity_exercises.create!(exercise:, position: @activity.activity_exercises.count + 1, points: 4)
  end

  def quiz_object
    {
      "questions" => [
        { "question_type" => "multiple_choice", "statement" => "Escolha", "options" => [ { "id" => "o1", "text" => "A" }, { "id" => "o2", "text" => "B" } ], "correct_option_ids" => [ "o1" ] },
        { "question_type" => "true_false", "statement" => "Verdade?", "correct_option_ids" => [ "true" ] },
        { "question_type" => "short_answer", "statement" => "Escreva", "correct_answer" => "Resposta" }
      ]
    }
  end

  def ordering_object
    {
      "instructions" => "Organize.", "item_type" => "words",
      "items" => [ { "id" => "item-1", "label" => "A" }, { "id" => "item-2", "label" => "B" }, { "id" => "item-3", "label" => "C" } ],
      "correct_order" => %w[item-1 item-2 item-3]
    }
  end

  def sentences_object
    {
      "format" => "multiple_sentences", "instructions" => "Organize as frases.",
      "sentences" => [
        { "id" => "s1", "items" => [ { "id" => "a", "label" => "I" }, { "id" => "b", "label" => "can" } ], "correct_order" => %w[a b] },
        { "id" => "s2", "items" => [ { "id" => "c", "label" => "We" }, { "id" => "d", "label" => "go" } ], "correct_order" => %w[c d] }
      ]
    }
  end

  def create_user(klass, prefix)
    id = "#{prefix}-#{SecureRandom.hex(6)}"
    klass.create!(name: prefix, username: id, email: "#{id}@example.com", password: "secret123")
  end
end
