require "test_helper"

class DeactivatedExerciseAttemptsTest < ActionDispatch::IntegrationTest
  parallelize(workers: 1)

  setup do
    @teacher = create_user(Teacher, "da-teacher")
    @school_class = @teacher.school_classes.create!(name: "Turma desativados", active: true)
    @activity = @school_class.activities.create!(title: "Aula desativados", published: true)
    @student = create_user(Student, "da-student")
    @school_class.class_students.create!(student: @student, active: true)
    @links = {
      quiz: link(:quiz, quiz_object),
      fill_blanks: link(:fill_blanks, fill_object),
      ordering: link(:ordering, ordering_object),
      crossword: link(:crossword, crossword_object),
      memory_game: link(:memory_game, memory_object)
    }
  end

  test "active authorized exercises still accept every attempt type" do
    login(@student)

    @links.each_key do |type|
      assert_difference("ExerciseAttempt.count", 1, type.to_s) { post_attempt(type) }
      assert_response :redirect
      assert_not_equal root_url, response.location, type.to_s
    end
  end

  test "direct posts to deactivated exercises are denied for all types without creating attempts" do
    login(@student)
    @links.each_value { |l| l.exercise.update!(active: false) }

    @links.each_key do |type|
      assert_no_difference("ExerciseAttempt.count", type.to_s) { post_attempt(type) }
      assert_redirected_to root_url
    end
  end

  test "old attempts stay stored and unchanged and remain viewable after deactivation" do
    login(@student)
    post_attempt(:quiz)
    attempt = ExerciseAttempt.order(:id).last
    snapshot = attempt.reload.attributes
    @links[:quiz].exercise.update!(active: false)

    assert_no_difference("ExerciseAttempt.count") { post_attempt(:quiz) }
    assert_equal snapshot, attempt.reload.attributes
    get exercise_attempt_url(attempt)
    assert_response :success
  end

  test "memory game turn is blocked after the exercise is deactivated mid-game" do
    login(@student)
    post_attempt(:memory_game)
    attempt = ExerciseAttempt.order(:id).last
    before = attempt.reload.attributes
    card = attempt.correct.fetch("deck").first
    @links[:memory_game].exercise.update!(active: false)

    post memory_game_turn_exercise_attempt_url(attempt), params: { operation: "reveal", card_id: card.fetch("id") }, as: :json

    assert_not_equal 200, response.status
    assert_equal before, attempt.reload.attributes
  end

  test "memory game turn works while the exercise is active" do
    login(@student)
    post_attempt(:memory_game)
    attempt = ExerciseAttempt.order(:id).last
    card = attempt.correct.fetch("deck").first

    post memory_game_turn_exercise_attempt_url(attempt), params: { operation: "reveal", card_id: card.fetch("id") }, as: :json

    assert_response :success
  end

  test "inactive link, unpublished lesson, missing enrollment and unauthorized class are denied" do
    login(@student)

    @links[:quiz].update!(active: false)
    assert_no_difference("ExerciseAttempt.count") { post_attempt(:quiz) }
    @links[:quiz].update!(active: true)

    @activity.update!(published: false)
    assert_no_difference("ExerciseAttempt.count") { post_attempt(:fill_blanks) }
    @activity.update!(published: true)

    @school_class.class_students.find_by!(student: @student).update!(active: false)
    assert_no_difference("ExerciseAttempt.count") { post_attempt(:ordering) }
    delete logout_url

    outsider = create_user(Student, "da-outsider")
    login(outsider)
    assert_no_difference("ExerciseAttempt.count") { post_attempt(:crossword) }
    assert_no_difference("ExerciseAttempt.count") { post_attempt(:memory_game) }
  end

  private

  def post_attempt(type)
    l = @links.fetch(type)
    attrs = { activity_exercise_id: l.id }
    case type
    when :quiz then attrs[:answers] = { "0" => "Resposta" }
    when :fill_blanks then attrs[:answers] = { "1" => "Brasil", "2" => "Brasília" }
    when :ordering then attrs[:ordered_ids] = %w[item-1 item-2]
    when :crossword
      cells = l.exercise.object.fetch("grid").fetch("cells").each_with_index.flat_map do |row, ri|
        row.each_with_index.filter_map { |cell, ci| [ "#{ri}-#{ci}", cell ] if cell.present? }
      end.to_h
      attrs[:answer] = { cells: }.to_json
      attrs[:time_spent] = 5
    end
    post exercise_attempts_url, params: { exercise_attempt: attrs }
  end

  def link(type, object)
    exercise = @teacher.exercises.create!(title: type.to_s, exercise_type: type, object:)
    @activity.activity_exercises.create!(exercise:, position: @activity.activity_exercises.maximum(:position).to_i + 1, points: 10)
  end

  def quiz_object
    { "questions" => [ { "question_type" => "short_answer", "statement" => "Pergunta?", "correct_answer" => "Resposta" } ] }
  end

  def fill_object
    { "text_template" => "A capital do {{1}} é {{2}}.", "blanks" => { "1" => "Brasil", "2" => "Brasília" } }
  end

  def ordering_object
    {
      "instructions" => "Organize.", "item_type" => "words",
      "items" => [ { "id" => "item-1", "label" => "A" }, { "id" => "item-2", "label" => "B" } ],
      "correct_order" => %w[item-1 item-2]
    }
  end

  def crossword_object
    Exercises::CrosswordBuilder.call(
      instructions: "Complete", seed: 17,
      words: [ { word: "APPLE", clue: "Fruta" }, { word: "PEAR", clue: "Outra fruta" } ]
    ).object
  end

  def memory_object
    Exercises::MemoryGameBuilder.call(object: {
      instructions: "Combine.", pair_type: "word_word",
      pairs: [
        { left: { type: "word", content: "DOG" }, right: { type: "word", content: "CACHORRO" } },
        { left: { type: "word", content: "CAT" }, right: { type: "word", content: "GATO" } }
      ]
    }).object
  end

  def create_user(klass, prefix)
    id = "#{prefix}-#{SecureRandom.hex(6)}"
    klass.create!(name: id, username: id, email: "#{id}@example.com", password: "secret123")
  end

  def login(user)
    role = user.is_a?(Teacher) ? "teacher" : "student"
    post login_url, params: { role:, username: user.username, password: "secret123" }
  end
end
