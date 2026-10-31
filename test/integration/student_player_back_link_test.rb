require "test_helper"

class StudentPlayerBackLinkTest < ActionDispatch::IntegrationTest
  parallelize(workers: 1)

  setup do
    @teacher = create_user(Teacher, "back-teacher")
    @school_class = @teacher.school_classes.create!(name: "Turma retorno", active: true)
    @activity = @school_class.activities.create!(title: "Aula retorno", published: true)
    @other_activity = @school_class.activities.create!(title: "Outra aula", published: true)
    @student = create_user(Student, "back-student")
    @school_class.class_students.create!(student: @student, active: true)
  end

  {
    quiz: :quiz_object,
    fill_blanks: :fill_object,
    ordering: :ordering_object,
    crossword: :crossword_object
  }.each do |type, builder|
    test "#{type} player links back to the activity" do
      link = link_for(type, send(builder))
      login(@student)

      get exercise_path(link.exercise, activity_exercise_id: link.id)

      assert_response :success
      assert_select "a[href='#{activity_path(@activity)}']", text: "Voltar à aula", count: 1
    end
  end

  test "multiple sentence ordering player links back to the activity" do
    link = link_for(:ordering, multiple_ordering_object)
    login(@student)

    get exercise_path(link.exercise, activity_exercise_id: link.id)

    assert_response :success
    assert_select "[data-controller='ordering-multiple-player']"
    assert_select "a[href='#{activity_path(@activity)}']", text: "Voltar à aula", count: 1
  end

  test "link follows the association when the exercise belongs to two activities" do
    exercise = @teacher.exercises.create!(title: "Compartilhado", exercise_type: :quiz, object: quiz_object)
    first = @activity.activity_exercises.create!(exercise:, position: 1, points: 1)
    second = @other_activity.activity_exercises.create!(exercise:, position: 1, points: 1)
    login(@student)

    get exercise_path(exercise, activity_exercise_id: second.id)
    assert_select "a[href='#{activity_path(@other_activity)}']", text: "Voltar à aula", count: 1
    assert_select "a[href='#{activity_path(@activity)}']", count: 0

    get exercise_path(exercise, activity_exercise_id: first.id)
    assert_select "a[href='#{activity_path(@activity)}']", text: "Voltar à aula", count: 1
    assert_select "a[href='#{activity_path(@other_activity)}']", count: 0
  end

  test "student cannot reach a player of another class and sees no activity link" do
    outsider = create_user(Student, "back-outsider")
    link = link_for(:quiz, quiz_object)
    login(outsider)

    get exercise_path(link.exercise, activity_exercise_id: link.id)

    assert_response :redirect
    follow_redirect!
    assert_select "a[href='#{activity_path(@activity)}']", count: 0
    assert_not_includes response.body, "Aula retorno"
  end

  test "teacher view has no player back link" do
    link = link_for(:quiz, quiz_object)
    login(@teacher)

    get exercise_path(link.exercise)

    assert_response :success
    assert_select "a", text: "Voltar à aula", count: 0
    assert_select "form[action='#{exercise_attempts_path}']", count: 0
  end

  test "memory game shows a single back link before starting" do
    link = link_for(:memory_game, memory_object)
    login(@student)

    get exercise_path(link.exercise, activity_exercise_id: link.id)

    assert_response :success
    assert_select "input[type=submit][value='Começar jogo']", count: 1
    assert_select "a[href='#{activity_path(@activity)}']", text: "Voltar à aula", count: 1
  end

  test "memory game back link points to the associated activity" do
    exercise = @teacher.exercises.create!(title: "Memória dupla", exercise_type: :memory_game, object: memory_object)
    @activity.activity_exercises.create!(exercise:, position: 1, points: 1)
    second = @other_activity.activity_exercises.create!(exercise:, position: 1, points: 1)
    login(@student)

    get exercise_path(exercise, activity_exercise_id: second.id)

    assert_select "a[href='#{activity_path(@other_activity)}']", text: "Voltar à aula", count: 1
    assert_select "a[href='#{activity_path(@activity)}']", count: 0
  end

  test "memory game keeps a single back link while playing" do
    link = link_for(:memory_game, memory_object)
    login(@student)

    post exercise_attempts_path, params: { exercise_attempt: { activity_exercise_id: link.id } }
    follow_redirect!

    assert_response :success
    assert_select ".memory-game > .memory-game-back-link a[href='#{activity_path(@activity)}']", text: "Voltar à aula", count: 1
    assert_select "section[data-memory-game-target='completion'] a[href='#{activity_path(@activity)}']", text: "Voltar à aula", count: 1
    assert_select "[hidden] .memory-game-back-link", count: 0
  end

  test "memory game keeps a single back link after completion" do
    link = link_for(:memory_game, memory_object)
    login(@student)
    post exercise_attempts_path, params: { exercise_attempt: { activity_exercise_id: link.id } }
    attempt = ExerciseAttempt.order(:id).last
    attempt.update_columns(answer: attempt.answer.to_h.merge("completed" => true))

    get exercise_path(link.exercise, activity_exercise_id: link.id, memory_game_attempt_id: attempt.id)

    assert_response :success
    assert_select "a[href='#{activity_path(@activity)}']", text: "Voltar à aula", count: 1
    assert_select "input[type=submit][value='Jogar novamente']", count: 1
  end

  private

  def link_for(type, object)
    exercise = @teacher.exercises.create!(title: "Exercício #{type}", exercise_type: type, object:)
    @activity.activity_exercises.create!(exercise:, position: 1, points: 1)
  end

  def create_user(klass, prefix)
    id = "#{prefix}-#{SecureRandom.hex(6)}"
    klass.create!(name: prefix, username: id, email: "#{id}@example.com", password: "secret123")
  end

  def login(user)
    role = user.is_a?(Teacher) ? "teacher" : "student"
    post login_url, params: { role:, username: user.username, password: "secret123" }
  end

  def quiz_object
    { "questions" => [ { "question_type" => "short_answer", "statement" => "Pergunta?", "correct_answer" => "Resposta" } ] }
  end

  def fill_object
    { "text_template" => "A capital do {{1}} é {{2}}.", "blanks" => { "1" => "Brasil", "2" => "Brasília" } }
  end

  def ordering_object
    {
      "instructions" => "Organize.",
      "item_type" => "words",
      "items" => [
        { "id" => "item-1", "label" => "A" }, { "id" => "item-2", "label" => "B" },
        { "id" => "item-3", "label" => "C" }, { "id" => "item-4", "label" => "D" }
      ],
      "correct_order" => %w[item-1 item-2 item-3 item-4]
    }
  end

  def multiple_ordering_object
    {
      "format" => "multiple_sentences",
      "instructions" => "Organize as frases.",
      "sentences" => [
        { "id" => "sentence-one", "items" => [ { "id" => "a", "label" => "I" }, { "id" => "b", "label" => "think" }, { "id" => "c", "label" => "I" }, { "id" => "d", "label" => "can." } ], "correct_order" => %w[a b c d] },
        { "id" => "sentence-two", "items" => [ { "id" => "e", "label" => "We" }, { "id" => "f", "label" => "will" }, { "id" => "g", "label" => "go" }, { "id" => "h", "label" => "now." } ], "correct_order" => %w[e f g h] }
      ]
    }
  end

  def crossword_object
    Exercises::CrosswordBuilder.call(
      instructions: "Complete",
      seed: 17,
      words: [ { word: "APPLE", clue: "Fruta" }, { word: "PEAR", clue: "Outra fruta" } ]
    ).object
  end

  def memory_object
    Exercises::MemoryGameBuilder.call(object: {
      instructions: "Combine.",
      pair_type: "word_word",
      pairs: [
        { left: { type: "word", content: "DOG" }, right: { type: "word", content: "CACHORRO" } },
        { left: { type: "word", content: "CAT" }, right: { type: "word", content: "GATO" } }
      ]
    }).object
  end
end
