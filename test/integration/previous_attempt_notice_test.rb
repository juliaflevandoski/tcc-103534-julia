require "test_helper"

class PreviousAttemptNoticeTest < ActionDispatch::IntegrationTest
  parallelize(workers: 1)

  NOTICE = "Você já respondeu este exercício. Sua primeira tentativa válida é considerada para a nota oficial.".freeze

  setup do
    @teacher = create_user(Teacher, "notice-teacher")
    @school_class = @teacher.school_classes.create!(name: "Turma aviso", active: true)
    @activity = @school_class.activities.create!(title: "Aula aviso", published: true)
    @other_activity = @school_class.activities.create!(title: "Outra aula", published: true)
    @student = create_user(Student, "notice-student")
    @other_student = create_user(Student, "notice-other")
    [ @student, @other_student ].each { |student| @school_class.class_students.create!(student:, active: true) }
    @exercises = {
      quiz: @teacher.exercises.create!(title: "Quiz", exercise_type: :quiz, object: {
        "questions" => [ { "question_type" => "short_answer", "statement" => "Pergunta?", "correct_answer" => "Resposta" } ]
      }),
      fill: @teacher.exercises.create!(title: "Lacunas", exercise_type: :fill_blanks, object: {
        "text_template" => "A capital do {{1}} é {{2}}.", "blanks" => { "1" => "Brasil", "2" => "Brasília" }
      }),
      ordering: @teacher.exercises.create!(title: "Ordenação", exercise_type: :ordering, object: {
        "instructions" => "Organize.", "item_type" => "words",
        "items" => [ { "id" => "item-1", "label" => "A" }, { "id" => "item-2", "label" => "B" } ],
        "correct_order" => %w[item-1 item-2]
      }),
      crossword: @teacher.exercises.create!(title: "Cruzada", exercise_type: :crossword, object: Exercises::CrosswordBuilder.call(
        instructions: "Complete", seed: 17, words: [ { word: "APPLE", clue: "Fruta" }, { word: "PEAR", clue: "Outra fruta" } ]
      ).object)
    }
    @links = @exercises.transform_values.with_index { |exercise, index| @activity.activity_exercises.create!(exercise:, position: index + 1, points: 4) }
    @other_link = @other_activity.activity_exercises.create!(exercise: @exercises[:quiz], position: 1, points: 4)
  end

  def submit(type, link)
    params = case type
    when :quiz then { answers: { "0" => "Resposta" } }
    when :fill then { answers: { "1" => "Brasil", "2" => "Brasília" } }
    when :ordering then { ordered_ids: %w[item-1 item-2] }
    when :crossword
      cells = @exercises[:crossword].object.fetch("grid").fetch("cells").each_with_index.flat_map do |row, r|
        row.each_with_index.filter_map { |cell, c| [ "#{r}-#{c}", cell ] if cell.present? }
      end.to_h
      { answer: { cells: }.to_json, time_spent: 5 }
    end
    post exercise_attempts_url, params: { exercise_attempt: params.merge(activity_exercise_id: link.id) }
    assert_response :redirect
  end

  test "no notice before the student has answered" do
    login(@student)

    @links.each_value do |link|
      get exercise_path(link.exercise, activity_exercise_id: link.id)
      assert_response :success
      assert_not_includes response.body, NOTICE
      assert_select "a", text: "Ver resultado anterior", count: 0
    end
  end

  %i[quiz fill ordering crossword].each do |type|
    test "#{type} shows the notice with a link to the official attempt after answering" do
      login(@student)
      link = @links.fetch(type)
      submit(type, link)
      official = ExerciseAttempt.order(:id).last
      submit(type, link)

      get exercise_path(link.exercise, activity_exercise_id: link.id)

      assert_response :success
      assert_includes response.body, NOTICE
      assert_select "a[href='#{exercise_attempt_path(official)}']", text: "Ver resultado anterior", count: 1
      assert_select "form[action='#{exercise_attempts_path}']", minimum: 1
    end
  end

  test "notice is isolated by student and by activity" do
    login(@student)
    submit(:quiz, @links[:quiz])

    get exercise_path(@exercises[:quiz], activity_exercise_id: @other_link.id)
    assert_not_includes response.body, NOTICE

    login(@other_student)
    get exercise_path(@exercises[:quiz], activity_exercise_id: @links[:quiz].id)
    assert_not_includes response.body, NOTICE
    assert_select "a", text: "Ver resultado anterior", count: 0
  end

  test "notice links only to the student's own official attempt and the link is authorized" do
    login(@student)
    submit(:quiz, @links[:quiz])
    mine = ExerciseAttempt.order(:id).last
    login(@other_student)
    submit(:quiz, @links[:quiz])
    theirs = ExerciseAttempt.order(:id).last

    login(@student)
    get exercise_path(@exercises[:quiz], activity_exercise_id: @links[:quiz].id)
    assert_select "a[href='#{exercise_attempt_path(mine)}']", count: 1
    assert_select "a[href='#{exercise_attempt_path(theirs)}']", count: 0
    get exercise_attempt_path(mine)
    assert_response :success
    get exercise_attempt_path(theirs)
    assert_redirected_to root_path
  end

  test "teacher preview does not show the notice and memory is untouched" do
    login(@student)
    submit(:quiz, @links[:quiz])

    login(@teacher)
    get exercise_path(@exercises[:quiz])
    assert_response :success
    assert_not_includes response.body, NOTICE
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
end
