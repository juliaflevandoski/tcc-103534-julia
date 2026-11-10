require "test_helper"

class CrosswordInvalidContentTest < ActionDispatch::IntegrationTest
  MESSAGE = "Este exercício está indisponível porque seu conteúdo é inválido.".freeze

  setup do
    @teacher = create_user(Teacher, "cwteacher")
    @student = create_user(Student, "cwstudent")
    @school_class = @teacher.school_classes.create!(name: "Cruzadinhas", active: true)
    @school_class.class_students.create!(student: @student, active: true)
    @activity = @school_class.activities.create!(title: "Aula de cruzadinhas", published: true)
    @valid_object = Exercises::CrosswordBuilder.call(
      instructions: "Complete a cruzadinha.", seed: 17,
      words: [ { word: "APPLE", clue: "Fruta" }, { word: "PEAR", clue: "Outra fruta" } ]
    ).object
  end

  test "a valid crossword keeps working for the student, the submission and the teacher preview" do
    link = create_link(@valid_object)

    sign_in(@student, "student")
    get exercise_url(link.exercise, activity_exercise_id: link.id)
    assert_response :success
    assert_select "table.crossword-answer-grid"

    assert_difference -> { ExerciseAttempt.count }, 1 do
      post exercise_attempts_url, params: { exercise_attempt: { activity_exercise_id: link.id, answer: { cells: all_cells("Z") }.to_json } }
    end
    assert_redirected_to exercise_attempt_url(ExerciseAttempt.order(:id).last)

    sign_out
    sign_in(@teacher, "teacher")
    get exercise_url(link.exercise)
    assert_response :success
    assert_select "table.crossword-teacher-grid"
    assert_select "p[role='alert']", text: MESSAGE, count: 0
  end

  invalid_variants = {
    "JSON null" => :json_null,
    "empty object" => :empty_object,
    "content of another exercise type" => :quiz_content
  }

  invalid_variants.each do |name, variant|
    test "the student is redirected with a clear message and nothing is recorded when the object is #{name}" do
      link = create_link(invalid_object(variant), variant:)
      sign_in(@student, "student")

      assert_no_writes do
        get exercise_url(link.exercise, activity_exercise_id: link.id)
        assert_redirected_to activity_url(@activity)
        assert_equal MESSAGE, flash[:alert]

        post exercise_attempts_url, params: { exercise_attempt: { activity_exercise_id: link.id, answer: { cells: all_cells("Z") }.to_json } }
        assert_redirected_to activity_url(@activity)
        assert_equal MESSAGE, flash[:alert]
      end
    end

    test "the teacher sees the message instead of the preview and can still edit when the object is #{name}" do
      link = create_link(invalid_object(variant), variant:)
      sign_in(@teacher, "teacher")

      assert_no_writes do
        get exercise_url(link.exercise)
        assert_response :success
        assert_select "p[role='alert']", text: MESSAGE
        assert_select "table.crossword-teacher-grid", count: 0
        assert_select "a[href='#{edit_exercise_path(link.exercise)}']", text: "Editar"

        get edit_exercise_url(link.exercise)
        assert_response :success
      end
    end
  end

  test "a student cannot reach another student's invalid crossword through the player of an unlinked lesson" do
    link = create_link(invalid_object(:json_null), variant: :json_null)
    other = create_user(Student, "cwoutsider")
    sign_in(other, "student")

    assert_no_writes do
      get exercise_url(link.exercise, activity_exercise_id: link.id)
      assert_redirected_to root_url
      post exercise_attempts_url, params: { exercise_attempt: { activity_exercise_id: link.id, answer: { cells: all_cells("Z") }.to_json } }
      assert_redirected_to root_url
    end
  end

  test "other exercise types keep their current behavior" do
    quiz = @teacher.exercises.create!(
      title: "Quiz", exercise_type: :quiz,
      object: { "questions" => [ { "question_type" => "short_answer", "statement" => "x?", "correct_answer" => "x" } ] }
    )
    link = @activity.activity_exercises.create!(exercise: quiz, position: 1, points: 10)
    sign_in(@student, "student")

    get exercise_url(quiz, activity_exercise_id: link.id)

    assert_response :success
    assert_no_match MESSAGE, response.body
  end

  private

  def create_user(klass, prefix)
    username = "#{prefix}_#{SecureRandom.hex(5)}"
    klass.create!(name: prefix, username:, email: "#{username}@example.test", password: "secret123")
  end

  def sign_in(user, role)
    post login_url, params: { role:, username: user.username, password: "secret123" }
  end

  def sign_out
    delete logout_url
  end

  def invalid_object(variant)
    { json_null: nil, empty_object: {}, quiz_content: { "question_type" => "multiple_choice", "statement" => "Qual?", "options" => [ { "id" => "a", "text" => "A" } ], "correct_option_ids" => [ "a" ] } }.fetch(variant)
  end

  def create_link(object, variant: nil)
    exercise = @teacher.exercises.build(title: "Cruzadinha", exercise_type: :crossword, object: object || {})
    exercise.save!(validate: variant.nil?)
    Exercise.connection.execute("UPDATE exercises SET object = 'null' WHERE id = #{exercise.id}") if variant == :json_null
    link = @activity.activity_exercises.build(exercise: Exercise.find(exercise.id), position: 1, points: 10)
    link.save!(validate: false)
    link
  end

  def all_cells(letter)
    @valid_object.fetch("grid").fetch("cells").each_with_index.flat_map do |row, row_index|
      row.each_with_index.filter_map { |cell, column_index| [ "#{row_index}-#{column_index}", letter ] if cell.present? }
    end.to_h
  end

  def counts
    { attempts: ExerciseAttempt.count, stats: StudentStat.count, xp: StudentStat.sum(:xp), exercises: Exercise.count, links: ActivityExercise.count }
  end

  def assert_no_writes
    before = counts
    yield
    assert_equal before, counts
  end
end
