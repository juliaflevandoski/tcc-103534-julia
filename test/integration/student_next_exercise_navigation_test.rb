require "test_helper"

class StudentNextExerciseNavigationTest < ActionDispatch::IntegrationTest
  parallelize(workers: 1)

  setup do
    @teacher = create_user(Teacher, "next-teacher")
    @school_class = @teacher.school_classes.create!(name: "Turma navegação", active: true)
    @activity = @school_class.activities.create!(title: "Aula navegação", published: true)
    @student = create_user(Student, "next-student")
    @school_class.class_students.create!(student: @student, active: true)
    @quiz = @teacher.exercises.create!(title: "Quiz um", exercise_type: :quiz, object: quiz_object)
    @fill = @teacher.exercises.create!(title: "Lacunas dois", exercise_type: :fill_blanks, object: fill_object)
    @ordering = @teacher.exercises.create!(title: "Ordenação três", exercise_type: :ordering, object: ordering_object)
    @crossword = @teacher.exercises.create!(title: "Cruzada quatro", exercise_type: :crossword, object: crossword_object)
    @memory = @teacher.exercises.create!(title: "Memória cinco", exercise_type: :memory_game, object: memory_object)
    @links = [ @quiz, @fill, @ordering, @crossword, @memory ].each_with_index.map do |exercise, index|
      @activity.activity_exercises.create!(exercise:, position: (index + 1) * 10, points: 4)
    end
    login(@student)
  end

  test "each common type links to the next exercise in order" do
    submit_quiz(@links[0])
    assert_next_link(@links[1])

    submit_fill(@links[1])
    assert_next_link(@links[2])

    submit_ordering(@links[2])
    assert_next_link(@links[3])

    submit_crossword(@links[3])
    assert_next_link(@links[4])
  end

  test "next link keeps the return link and is a plain GET link" do
    submit_quiz(@links[0])
    follow_redirect!

    assert_select ".attempt-result-navigation a[href='#{activity_path(@activity)}']", text: "Voltar à aula", minimum: 1
    assert_select "a[href='#{next_path(@links[1])}']", text: "Próximo exercício", count: 1
    assert_select "form[action='#{next_path(@links[1])}']", count: 0
  end

  test "last exercise has no next link" do
    submit_crossword(@links[3])
    @links[4].update!(active: false)
    get exercise_attempt_url(ExerciseAttempt.order(:id).last)

    assert_response :success
    assert_select "a", text: "Próximo exercício", count: 0
    assert_select "a[href='#{activity_path(@activity)}']", text: "Voltar à aula", minimum: 1
  end

  test "next link points to an already answered exercise" do
    submit_fill(@links[1])
    submit_quiz(@links[0])

    assert_next_link(@links[1])
  end

  test "next link skips inactive links and inactive exercises" do
    @links[1].update!(active: false)
    @ordering.update!(active: false)

    submit_quiz(@links[0])

    assert_next_link(@links[3])
  end

  test "next link never points to another activity" do
    other = @school_class.activities.create!(title: "Outra", published: true)
    other.activity_exercises.create!(exercise: @fill, position: 15, points: 1)
    @links[1..].each { |link| link.update!(active: false) }

    submit_quiz(@links[0])

    assert_select "a", text: "Próximo exercício", count: 0
  end

  test "next link is absent when the activity is unpublished or enrollment is inactive" do
    submit_quiz(@links[0])
    attempt = ExerciseAttempt.order(:id).last

    @activity.update!(published: false)
    get exercise_attempt_url(attempt)
    assert_select "a", text: "Próximo exercício", count: 0
    assert_select "a", text: "Voltar à aula", count: 0

    @activity.update!(published: true)
    @school_class.class_students.find_by!(student: @student).update!(active: false)
    get exercise_attempt_url(attempt)
    assert_select "a", text: "Próximo exercício", count: 0

    @school_class.class_students.find_by!(student: @student).update!(active: true)
    @school_class.update!(active: false)
    get exercise_attempt_url(attempt)
    assert_select "a", text: "Próximo exercício", count: 0
  end

  test "teacher viewing a result does not get a next link" do
    submit_quiz(@links[0])
    attempt = ExerciseAttempt.order(:id).last
    delete logout_url
    login(@teacher)

    get exercise_attempt_url(attempt)

    assert_response :success
    assert_select "a", text: "Próximo exercício", count: 0
    assert_select "a[href='#{activity_path(@activity)}']", text: "Voltar à aula", minimum: 1
  end

  test "following the next link is a GET that creates no attempts" do
    submit_quiz(@links[0])

    assert_no_difference("ExerciseAttempt.count") do
      get next_path(@links[1])
    end
    assert_response :success
  end

  test "memory game loaded already completed shows the next link" do
    attempt = complete_memory(@links[4])
    @activity.activity_exercises.create!(exercise: create_quiz("Extra"), position: 60, points: 1)

    get exercise_url(@memory, activity_exercise_id: @links[4].id, memory_game_attempt_id: attempt.id)

    assert_response :success
    assert_select ".memory-result a[href='#{activity_path(@activity)}']", text: "Voltar à aula", count: 1
    assert_select ".memory-result a[href='#{next_path(@activity.activity_exercises.order(:position).last)}']", text: "Próximo exercício", count: 1
  end

  test "memory game in progress renders the next link inside the hidden completion section for AJAX completion" do
    @links[4].update!(position: 5)
    post exercise_attempts_url, params: { exercise_attempt: { activity_exercise_id: @links[4].id } }
    attempt = ExerciseAttempt.order(:id).last

    get exercise_url(@memory, activity_exercise_id: @links[4].id, memory_game_attempt_id: attempt.id)

    assert_response :success
    assert_select "section[data-memory-game-target='completion'][hidden] a[href='#{next_path(@links[0])}']", text: "Próximo exercício", count: 1
    assert_select "section[data-memory-game-target='completion'][hidden] a[href='#{activity_path(@activity)}']", text: "Voltar à aula", count: 1
    assert_select "section[data-memory-game-target='completion'][hidden] input[value='Jogar novamente']", count: 1
  end

  test "memory game as the last exercise has no next link" do
    attempt = complete_memory(@links[4])

    get exercise_url(@memory, activity_exercise_id: @links[4].id, memory_game_attempt_id: attempt.id)

    assert_response :success
    assert_select "a", text: "Próximo exercício", count: 0
    assert_select ".memory-result a[href='#{activity_path(@activity)}']", text: "Voltar à aula", count: 1
  end

  test "memory game player is not reachable and shows no next link when the activity is unpublished" do
    @links[4].update!(position: 5)
    post exercise_attempts_url, params: { exercise_attempt: { activity_exercise_id: @links[4].id } }
    attempt = ExerciseAttempt.order(:id).last
    @activity.update!(published: false)

    get exercise_url(@memory, activity_exercise_id: @links[4].id, memory_game_attempt_id: attempt.id)

    assert_redirected_to root_url
    assert_select "a", text: "Próximo exercício", count: 0
  end

  test "navigation does not change official attempt or lesson completion" do
    submit_quiz(@links[0])
    first = ExerciseAttempt.order(:id).last
    submit_quiz(@links[0])

    assert_equal first, ActivityResults.official_attempt(activity_exercise: @links[0], student: @student)
    assert_not ActivityResults.lesson_completed?(activity: @activity, student: @student)
  end

  test "teacher creation flow from an activity still keeps context" do
    delete logout_url
    login(@teacher)

    get activity_url(@activity)
    assert_select "a[href='#{new_exercise_path(activity_id: @activity.id)}']", text: "Criar exercício"

    get new_exercise_url(activity_id: @activity.id)
    assert_select "input[type='hidden'][name='activity_id'][value='#{@activity.id}']", count: 1
  end

  private

  def create_user(klass, prefix)
    id = "#{prefix}-#{SecureRandom.hex(6)}"
    klass.create!(name: prefix, username: id, email: "#{id}@example.com", password: "secret123")
  end

  def login(user)
    role = user.is_a?(Teacher) ? "teacher" : "student"
    post login_url, params: { role:, username: user.username, password: "secret123" }
  end

  def next_path(link)
    exercise_path(link.exercise, activity_exercise_id: link.id)
  end

  def assert_next_link(link)
    follow_redirect!
    assert_response :success
    assert_select "a[href='#{next_path(link)}']", text: "Próximo exercício", count: 1
  end

  def create_quiz(title)
    @teacher.exercises.create!(title:, exercise_type: :quiz, object: quiz_object)
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

  def submit_quiz(link)
    post exercise_attempts_url, params: { exercise_attempt: { activity_exercise_id: link.id, answers: { "0" => "Resposta" } } }
    assert_response :redirect
  end

  def submit_fill(link)
    post exercise_attempts_url, params: { exercise_attempt: { activity_exercise_id: link.id, answers: { "1" => "Brasil", "2" => "Brasília" } } }
    assert_response :redirect
  end

  def submit_ordering(link)
    post exercise_attempts_url, params: { exercise_attempt: { activity_exercise_id: link.id, ordered_ids: %w[item-1 item-2 item-3 item-4] } }
    assert_response :redirect
  end

  def submit_crossword(link)
    cells = @crossword.object.fetch("grid").fetch("cells").each_with_index.flat_map do |row, row_index|
      row.each_with_index.filter_map { |cell, column_index| [ "#{row_index}-#{column_index}", cell ] if cell.present? }
    end.to_h
    post exercise_attempts_url, params: { exercise_attempt: { activity_exercise_id: link.id, answer: { cells: }.to_json, time_spent: 5 } }
    assert_response :redirect
  end

  def complete_memory(link)
    post exercise_attempts_url, params: { exercise_attempt: { activity_exercise_id: link.id } }
    attempt = ExerciseAttempt.order(:id).last
    attempt.correct.fetch("deck").group_by { |card| card.fetch("pair_id") }.each_value do |cards|
      cards.each do |card|
        post memory_game_turn_exercise_attempt_url(attempt), params: { operation: "reveal", card_id: card.fetch("id") }, as: :json
        assert_response :success
      end
    end
    assert attempt.reload.answer.fetch("completed")
    attempt
  end
end
