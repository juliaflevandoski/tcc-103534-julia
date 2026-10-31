require "test_helper"

class ExerciseActivityContextTest < ActionDispatch::IntegrationTest
  parallelize(workers: 1)

  setup do
    @teacher = create_teacher("owner")
    @school_class = @teacher.school_classes.create!(name: "Turma contexto", active: true)
    @activity = @school_class.activities.create!(title: "Aula de origem", published: true)
    login(@teacher)
  end

  test "activity page links to the new exercise form with the activity context" do
    get activity_url(@activity)

    assert_response :success
    assert_select "a[href='#{new_exercise_path(activity_id: @activity.id)}']", text: "Criar exercício"
  end

  test "new form with an owned activity keeps the hidden field and cancels back to the activity" do
    get new_exercise_url(activity_id: @activity.id)

    assert_response :success
    assert_select "form input[type='hidden'][name='activity_id'][value='#{@activity.id}']", count: 1
    assert_select "a[href='#{activity_path(@activity)}']", text: "Cancelar"
  end

  test "global new form has no context and cancels to the exercise list" do
    get new_exercise_url

    assert_response :success
    assert_select "input[name='activity_id']", count: 0
    assert_select "a[href='#{exercises_path}']", text: "Cancelar"
  end

  test "invalid, inactive or foreign activity ids are ignored" do
    other_activity = create_teacher("other").school_classes.create!(name: "Outra", active: true).activities.create!(title: "Alheia")
    inactive = @school_class.activities.create!(title: "Inativa", active: false)

    [ other_activity.id, inactive.id, 0, "abc" ].each do |id|
      get new_exercise_url(activity_id: id)

      assert_response :success
      assert_select "input[name='activity_id']", count: 0
      assert_select "a[href='#{exercises_path}']", text: "Cancelar"
    end
  end

  test "creating a quiz from an activity redirects to the preview with a link back, without associating" do
    assert_difference("Exercise.count", 1) do
      assert_no_difference("ActivityExercise.count") do
        post exercises_url, params: { activity_id: @activity.id, exercise: quiz_attributes }
      end
    end

    exercise = Exercise.order(:id).last
    assert_redirected_to exercise_url(exercise, activity_id: @activity.id)
    follow_redirect!
    assert_select "a[href='#{activity_path(@activity, exercise_id: exercise.id)}']", text: "Voltar à aula e adicionar este exercício"
  end

  test "creating a memory game from an activity preserves the context" do
    assert_no_difference("ActivityExercise.count") do
      post exercises_url, params: { activity_id: @activity.id, exercise: memory_attributes }
    end

    exercise = Exercise.order(:id).last
    assert_redirected_to exercise_url(exercise, activity_id: @activity.id)
  end

  test "validation errors keep the activity context" do
    assert_no_difference("Exercise.count") do
      post exercises_url, params: { activity_id: @activity.id, exercise: quiz_attributes.merge(object: { questions: [] }.to_json) }
    end

    assert_response :unprocessable_entity
    assert_select "form input[type='hidden'][name='activity_id'][value='#{@activity.id}']", count: 1
    assert_select "a[href='#{activity_path(@activity)}']", text: "Cancelar"
  end

  test "global creation redirects to the plain preview without the back link" do
    post exercises_url, params: { exercise: quiz_attributes }

    exercise = Exercise.order(:id).last
    assert_redirected_to exercise_url(exercise)
    follow_redirect!
    assert_select "a", text: "Voltar à aula e adicionar este exercício", count: 0
  end

  test "creation with a foreign or inactive activity behaves as global" do
    foreign = create_teacher("foreign").school_classes.create!(name: "Alheia", active: true).activities.create!(title: "Alheia")
    inactive = @school_class.activities.create!(title: "Inativa", active: false)

    [ foreign.id, inactive.id ].each do |id|
      post exercises_url, params: { activity_id: id, exercise: quiz_attributes }
      exercise = Exercise.order(:id).last
      assert_redirected_to exercise_url(exercise)
    end
  end

  test "preview shows a plain back link when the exercise is already in the activity" do
    exercise = create_exercise(@teacher)
    @activity.activity_exercises.create!(exercise:, position: 1, points: 1)

    get exercise_url(exercise, activity_id: @activity.id)

    assert_response :success
    assert_select "a", text: "Voltar à aula e adicionar este exercício", count: 0
    assert_select "a[href='#{activity_path(@activity)}']", text: "Voltar à aula", count: 1
  end

  test "preview ignores a foreign activity id" do
    foreign = create_teacher("foreign2").school_classes.create!(name: "Alheia", active: true).activities.create!(title: "Alheia")
    exercise = create_exercise(@teacher)

    get exercise_url(exercise, activity_id: foreign.id)

    assert_response :success
    assert_select "a", text: "Voltar à aula e adicionar este exercício", count: 0
  end

  test "activity preselects a valid exercise without associating it" do
    exercise = create_exercise(@teacher)

    assert_no_difference("ActivityExercise.count") do
      get activity_url(@activity, exercise_id: exercise.id)
    end

    assert_response :success
    assert_select "select[name='activity_exercise[exercise_id]'] option[selected][value='#{exercise.id}']", count: 1
  end

  test "activity does not preselect missing, inactive, foreign or already associated exercises" do
    inactive = create_exercise(@teacher, active: false)
    foreign = create_exercise(create_teacher("foreign3"))
    associated = create_exercise(@teacher)
    @activity.activity_exercises.create!(exercise: associated, position: 1, points: 1)

    [ 0, inactive.id, foreign.id, associated.id, "abc" ].each do |id|
      get activity_url(@activity, exercise_id: id)

      assert_response :success
      assert_select "select[name='activity_exercise[exercise_id]'] option[selected]", count: 0
    end
  end

  test "student cannot open the new form and sees no back link on a previewed exercise" do
    exercise = create_exercise(@teacher)
    activity_exercise = @activity.activity_exercises.create!(exercise:, position: 1, points: 1)
    student = Student.create!(name: "Aluno", username: "ctx-student-#{SecureRandom.hex(6)}", email: "ctx-#{SecureRandom.hex(6)}@example.com", password: "secret123")
    @school_class.class_students.create!(student:, active: true)
    delete logout_url
    post login_url, params: { role: "student", username: student.username, password: "secret123" }

    get new_exercise_url(activity_id: @activity.id)
    assert_redirected_to root_url

    get exercise_url(exercise, activity_exercise_id: activity_exercise.id, activity_id: @activity.id)
    assert_response :success
    assert_select "a", text: "Voltar à aula e adicionar este exercício", count: 0
    assert_select "a", text: "Editar", count: 0
  end

  test "student is denied creating, editing and updating exercises without side effects" do
    exercise = create_exercise(@teacher)
    @activity.activity_exercises.create!(exercise:, position: 1, points: 1)
    student = Student.create!(name: "Aluno", username: "deny-student-#{SecureRandom.hex(6)}", email: "deny-#{SecureRandom.hex(6)}@example.com", password: "secret123")
    @school_class.class_students.create!(student:, active: true)
    delete logout_url
    post login_url, params: { role: "student", username: student.username, password: "secret123" }

    assert_no_difference("Exercise.count") do
      post exercises_url, params: { activity_id: @activity.id, exercise: quiz_attributes }
    end
    assert_redirected_to root_url

    assert_no_difference("Exercise.count") do
      post exercises_url, params: { exercise: quiz_attributes }
    end
    assert_redirected_to root_url

    get edit_exercise_url(exercise)
    assert_redirected_to root_url

    patch exercise_url(exercise), params: { exercise: quiz_attributes.merge(title: "Hackeado") }
    assert_redirected_to root_url
    assert_not_equal "Hackeado", exercise.reload.title
  end

  test "teacher activity page does not render attempt return links and keeps a single create link" do
    exercise = create_exercise(@teacher)
    @activity.activity_exercises.create!(exercise:, position: 1, points: 1)

    get activity_url(@activity)

    assert_select "a[href^='#{new_exercise_path}']", text: "Criar exercício", count: 1
    assert_select "a", text: "Voltar à aula", count: 0
  end

  private

  def create_teacher(prefix)
    id = "#{prefix}-#{SecureRandom.hex(6)}"
    Teacher.create!(name: "Professor #{prefix}", username: id, email: "#{id}@example.com", password: "secret123")
  end

  def login(teacher)
    post login_url, params: { role: "teacher", username: teacher.username, password: "secret123" }
  end

  def create_exercise(teacher, active: true)
    teacher.exercises.create!(title: "Exercício #{SecureRandom.hex(3)}", exercise_type: :quiz, active:, object: quiz_object)
  end

  def quiz_object
    { "questions" => [ { "question_type" => "short_answer", "statement" => "Pergunta?", "correct_answer" => "Resposta" } ] }
  end

  def quiz_attributes
    { title: "Novo quiz", exercise_type: "quiz", object: quiz_object.to_json }
  end

  def memory_attributes
    {
      title: "Novo jogo",
      exercise_type: "memory_game",
      object: {
        instructions: "Combine os nomes.",
        pair_type: "word_word",
        pairs: [
          { left: { type: "word", content: "DOG" }, right: { type: "word", content: "CACHORRO" } },
          { left: { type: "word", content: "CAT" }, right: { type: "word", content: "GATO" } }
        ]
      }.to_json
    }
  end
end
