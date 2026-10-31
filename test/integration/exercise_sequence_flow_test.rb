require "test_helper"

class ExerciseSequenceFlowTest < ActionDispatch::IntegrationTest
  parallelize(workers: 1)

  setup do
    @teacher = create_teacher("seq")
    @school_class = @teacher.school_classes.create!(name: "Turma sequência", active: true)
    @activity = @school_class.activities.create!(title: "Aula sequência", published: true)
    post login_url, params: { role: "teacher", username: @teacher.username, password: "secret123" }
  end

  test "preview after creation offers add and create-another links without associating" do
    assert_no_difference("ActivityExercise.count") do
      post exercises_url, params: { activity_id: @activity.id, exercise: quiz_attributes }
    end
    exercise = Exercise.order(:id).last
    follow_redirect!

    assert_select "a[href='#{activity_path(@activity, exercise_id: exercise.id)}']", text: "Voltar à aula e adicionar este exercício"
    assert_select "a[href='#{new_exercise_path(activity_id: @activity.id)}']", text: "Criar outro exercício", count: 1
    assert_select "a[href='#{edit_exercise_path(exercise, activity_id: @activity.id)}']", text: "Editar"
  end

  test "preview of an associated exercise shows back link and create another" do
    exercise = create_exercise(@teacher)
    @activity.activity_exercises.create!(exercise:, position: 1, points: 1)

    assert_no_difference("ActivityExercise.count") do
      get exercise_url(exercise, activity_id: @activity.id)
    end

    assert_select "a[href='#{activity_path(@activity)}']", text: "Voltar à aula", count: 1
    assert_select "a", text: "Voltar à aula e adicionar este exercício", count: 0
    assert_select "a[href='#{new_exercise_path(activity_id: @activity.id)}']", text: "Criar outro exercício", count: 1
  end

  test "edit form keeps the context and cancels to the activity" do
    exercise = create_exercise(@teacher)

    get edit_exercise_url(exercise, activity_id: @activity.id)

    assert_response :success
    assert_select "form input[type='hidden'][name='activity_id'][value='#{@activity.id}']", count: 1
    assert_select "a[href='#{activity_path(@activity)}']", text: "Cancelar"
  end

  test "update with context redirects to the preview keeping the activity" do
    exercise = create_exercise(@teacher)

    assert_no_difference("ActivityExercise.count") do
      patch exercise_url(exercise), params: { activity_id: @activity.id, exercise: quiz_attributes.merge(title: "Editado") }
    end

    assert_redirected_to exercise_url(exercise, activity_id: @activity.id)
    assert_equal "Editado", exercise.reload.title
  end

  test "update with validation error keeps the context" do
    exercise = create_exercise(@teacher)

    patch exercise_url(exercise), params: { activity_id: @activity.id, exercise: quiz_attributes.merge(title: "") }

    assert_response :unprocessable_entity
    assert_select "form input[type='hidden'][name='activity_id'][value='#{@activity.id}']", count: 1
  end

  test "update of a memory game with context keeps the activity" do
    exercise = @teacher.exercises.create!(title: "Memória", exercise_type: :memory_game, object: memory_object)

    patch exercise_url(exercise), params: { activity_id: @activity.id, exercise: memory_attributes.merge(title: "Memória nova") }

    assert_redirected_to exercise_url(exercise, activity_id: @activity.id)
    assert_equal "Memória nova", exercise.reload.title
  end

  test "creating and editing a memory game without context stays global" do
    post exercises_url, params: { exercise: memory_attributes }
    exercise = Exercise.order(:id).last
    assert_redirected_to exercise_url(exercise)

    patch exercise_url(exercise), params: { exercise: memory_attributes.merge(title: "Outro") }
    assert_redirected_to exercise_url(exercise)

    follow_redirect!
    assert_select "a", text: "Criar outro exercício", count: 0
    assert_select "a[href='#{edit_exercise_path(exercise)}']", text: "Editar"
  end

  test "global edit and update behave as before" do
    exercise = create_exercise(@teacher)

    get edit_exercise_url(exercise)
    assert_select "input[name='activity_id']", count: 0
    assert_select "a[href='#{exercises_path}']", text: "Cancelar"

    patch exercise_url(exercise), params: { exercise: quiz_attributes.merge(title: "Global") }
    assert_redirected_to exercise_url(exercise)
  end

  test "foreign, inactive or invalid activity ids give no context on preview, edit and update" do
    foreign = create_teacher("seq-foreign").school_classes.create!(name: "Alheia", active: true).activities.create!(title: "Alheia")
    inactive = @school_class.activities.create!(title: "Inativa", active: false)
    exercise = create_exercise(@teacher)

    [ foreign.id, inactive.id, 0, "abc" ].each do |id|
      get exercise_url(exercise, activity_id: id)
      assert_select "a", text: "Criar outro exercício", count: 0
      assert_select "a", text: "Voltar à aula", count: 0
      assert_select "a[href='#{edit_exercise_path(exercise)}']", text: "Editar"

      get edit_exercise_url(exercise, activity_id: id)
      assert_select "input[name='activity_id']", count: 0
      assert_select "a[href='#{exercises_path}']", text: "Cancelar"

      patch exercise_url(exercise), params: { activity_id: id, exercise: quiz_attributes }
      assert_redirected_to exercise_url(exercise)
    end
  end

  test "teacher journey: activity list → preview → edit → save keeps the activity context" do
    exercise = create_exercise(@teacher)
    link = @activity.activity_exercises.create!(exercise:, position: 1, points: 1)

    get activity_url(@activity)
    href = exercise_path(exercise, activity_exercise_id: link.id, activity_id: @activity.id)
    assert_select "a[href='#{href}']", text: exercise.title, count: 1

    get href
    assert_select "a[href='#{activity_path(@activity)}']", text: "Voltar à aula", count: 1
    assert_select "a[href='#{new_exercise_path(activity_id: @activity.id)}']", text: "Criar outro exercício", count: 1
    edit_href = edit_exercise_path(exercise, activity_id: @activity.id)
    assert_select "a[href='#{edit_href}']", text: "Editar", count: 1

    get edit_href
    assert_select "form input[type='hidden'][name='activity_id'][value='#{@activity.id}']", count: 1

    assert_no_difference("ActivityExercise.count") do
      patch exercise_url(exercise), params: { activity_id: @activity.id, exercise: quiz_attributes.merge(title: "Editado") }
    end
    assert_redirected_to exercise_url(exercise, activity_id: @activity.id)
    follow_redirect!
    assert_select "a", text: "Criar outro exercício", count: 1
  end

  test "global list links carry no activity context" do
    create_exercise(@teacher)

    get exercises_url

    assert_select "a[href*='activity_id']", count: 0
  end

  test "student activity list link keeps no activity_id" do
    exercise = create_exercise(@teacher)
    link = @activity.activity_exercises.create!(exercise:, position: 1, points: 1)
    student = Student.create!(name: "Aluno", username: "j-st-#{SecureRandom.hex(6)}", email: "j-#{SecureRandom.hex(6)}@example.com", password: "secret123")
    @school_class.class_students.create!(student:, active: true)
    delete logout_url
    post login_url, params: { role: "student", username: student.username, password: "secret123" }

    get activity_url(@activity)

    assert_select "a[href='#{exercise_path(exercise, activity_exercise_id: link.id)}']", count: 1
  end

  test "FL-1B return links stay intact for students" do
    exercise = create_exercise(@teacher)
    link = @activity.activity_exercises.create!(exercise:, position: 1, points: 1)
    student = Student.create!(name: "Aluno", username: "seq-st-#{SecureRandom.hex(6)}", email: "seq-#{SecureRandom.hex(6)}@example.com", password: "secret123")
    @school_class.class_students.create!(student:, active: true)
    delete logout_url
    post login_url, params: { role: "student", username: student.username, password: "secret123" }

    get exercise_url(exercise, activity_exercise_id: link.id)

    assert_select "a[href='#{activity_path(@activity)}']", text: "Voltar à aula", minimum: 1
    assert_select "a", text: "Criar outro exercício", count: 0
  end

  private

  def create_teacher(prefix)
    id = "#{prefix}-#{SecureRandom.hex(6)}"
    Teacher.create!(name: "Professor #{prefix}", username: id, email: "#{id}@example.com", password: "secret123")
  end

  def create_exercise(teacher)
    teacher.exercises.create!(title: "Exercício #{SecureRandom.hex(3)}", exercise_type: :quiz, object: quiz_object)
  end

  def quiz_object
    { "questions" => [ { "question_type" => "short_answer", "statement" => "Pergunta?", "correct_answer" => "Resposta" } ] }
  end

  def quiz_attributes
    { title: "Novo quiz", exercise_type: "quiz", object: quiz_object.to_json }
  end

  def memory_hash
    {
      instructions: "Combine os nomes.",
      pair_type: "word_word",
      pairs: [
        { left: { type: "word", content: "DOG" }, right: { type: "word", content: "CACHORRO" } },
        { left: { type: "word", content: "CAT" }, right: { type: "word", content: "GATO" } }
      ]
    }
  end

  def memory_object
    Exercises::MemoryGameBuilder.call(object: memory_hash).object
  end

  def memory_attributes
    { title: "Novo jogo", exercise_type: "memory_game", object: memory_hash.to_json }
  end
end
