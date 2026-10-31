require "test_helper"

class FormConsistencyTest < ActionDispatch::IntegrationTest
  parallelize(workers: 1)

  QUIZ = { questions: [ { question_type: "short_answer", statement: "Qual a capital?", correct_answer: "Brasilia" } ] }.freeze

  setup do
    @teacher = Teacher.create!(name: "Prof", username: "prof_fc", email: "prof_fc@example.com", password: "secret123")
    @school_class = SchoolClass.create!(teacher: @teacher, name: "Turma FC")
    @activity = @school_class.activities.create!(title: "Aula FC", published: true)
    @exercise = create_exercise("Exercicio base")
    post login_url, params: { role: "teacher", username: @teacher.username, password: "secret123" }
  end

  def create_exercise(title)
    @teacher.exercises.create!(title:, exercise_type: :quiz, object: QUIZ)
  end

  def errors_list
    css_select(".errors li").map(&:text)
  end

  def exercise_params(**overrides)
    { title: "Titulo", exercise_type: "quiz", object: QUIZ.to_json }.merge(overrides)
  end

  # Tipo de exercício

  test "invalid exercise type on create returns 422 without saving" do
    assert_no_difference -> { Exercise.count } do
      post exercises_url, params: { exercise: exercise_params(exercise_type: "foo") }
    end
    assert_response :unprocessable_entity
    assert_equal [ "Tipo de exercício inválido." ], errors_list
    assert_select "form"
  end

  test "invalid exercise type on update returns 422 and keeps the record" do
    patch exercise_url(@exercise), params: { exercise: exercise_params(exercise_type: "foo", title: "Novo") }
    assert_response :unprocessable_entity
    assert_equal [ "Tipo de exercício inválido." ], errors_list
    assert_equal "quiz", @exercise.reload.exercise_type
    assert_equal "Exercicio base", @exercise.title
  end

  test "valid types still work on create and update" do
    assert_difference -> { Exercise.count } => 1 do
      post exercises_url, params: { exercise: exercise_params }
    end
    assert_response :redirect
    patch exercise_url(@exercise), params: { exercise: exercise_params(title: "Editado") }
    assert_redirected_to exercise_url(@exercise)
    assert_equal "Editado", @exercise.reload.title
  end

  # JSON

  test "malformed JSON returns 422 with a specific message on create" do
    assert_no_difference -> { Exercise.count } do
      post exercises_url, params: { exercise: exercise_params(object: "{bad json") }
    end
    assert_response :unprocessable_entity
    assert_equal [ "Conteúdo do exercício inválido." ], errors_list
  end

  test "malformed JSON on update does not replace the stored content" do
    patch exercise_url(@exercise), params: { exercise: exercise_params(object: "{bad json") }
    assert_response :unprocessable_entity
    assert_equal [ "Conteúdo do exercício inválido." ], errors_list
    assert_equal QUIZ.deep_stringify_keys, @exercise.reload.object
  end

  test "well formed but incomplete JSON keeps using the type validators" do
    assert_no_difference -> { Exercise.count } do
      post exercises_url, params: { exercise: exercise_params(object: "{}") }
    end
    assert_response :unprocessable_entity
    assert_includes errors_list, "Adicione pelo menos uma pergunta ao Quiz."
    assert_not_includes errors_list, "Conteúdo do exercício inválido."
  end

  # Título e descrição

  test "exercise title is trimmed, required and limited to 150 characters" do
    assert Exercise.new(teacher: @teacher, exercise_type: :quiz, object: QUIZ, title: "a" * 150).valid?
    too_long = Exercise.new(teacher: @teacher, exercise_type: :quiz, object: QUIZ, title: "a" * 151)
    assert_not too_long.valid?
    assert_includes too_long.errors.full_messages, "Título é muito longo (máximo: 150 caracteres)"
    assert_equal "Ola", Exercise.new(title: "  Ola  ").title
    assert_not Exercise.new(teacher: @teacher, exercise_type: :quiz, object: QUIZ, title: "   ").valid?
  end

  test "exercise description is limited to 255 characters and not modified" do
    attrs = { teacher: @teacher, exercise_type: :quiz, object: QUIZ, title: "T" }
    assert Exercise.new(**attrs, description: "a" * 255).valid?
    assert_not Exercise.new(**attrs, description: "a" * 256).valid?
    assert_equal "  texto  ", Exercise.new(description: "  texto  ").description
  end

  test "exercise form rejects long title and description with 422 and keeps typed data" do
    assert_no_difference -> { Exercise.count } do
      post exercises_url, params: { exercise: exercise_params(title: "a" * 151, description: "b" * 256) }
    end
    assert_response :unprocessable_entity
    assert_equal 2, errors_list.size
    assert_select "input[name='exercise[title]'][value='#{"a" * 151}']"
  end

  test "exercise form has required and maxlength attributes" do
    get new_exercise_url
    assert_select "input[name='exercise[title]'][required][maxlength='150']"
    assert_select "textarea[name='exercise[description]'][maxlength='255']"
  end

  # Pontos

  def link_params(points)
    { activity_exercise: { activity_id: @activity.id, exercise_id: @exercise.id, points: } }
  end

  test "points accept the boundaries 0 and 1,000,000" do
    [ 0, 1_000_000 ].each do |points|
      ActivityExercise.delete_all
      assert_difference -> { ActivityExercise.count } => 1 do
        post activity_exercises_url, params: link_params(points)
      end
      assert_redirected_to activity_url(@activity)
      assert_equal points, ActivityExercise.last.points
    end
  end

  [ "1000001", "-1", "1.5", "abc", "1e3", "9" * 25, "" ].each do |points|
    test "create rejects points #{points.inspect} without saving or failing" do
      assert_no_difference -> { ActivityExercise.count } do
        post activity_exercises_url, params: link_params(points)
      end
      assert_redirected_to activity_url(@activity)
      follow_redirect!
      assert_match(/Pontos/, response.body)
    end
  end

  test "points error messages are not duplicated when blank" do
    link = @activity.activity_exercises.create!(exercise: @exercise, position: 1, points: 10)
    patch activity_exercise_url(link), params: { activity_exercise: { points: "" } }
    assert_response :unprocessable_entity
    assert_equal [ "Pontos não pode ficar em branco" ], errors_list
    assert_equal 10, link.reload.points
  end

  [ [ "1.5", "Pontos não é um número inteiro" ], [ "abc", "Pontos não é um número" ],
    [ "-1", "Pontos deve ser maior ou igual a 0" ], [ "1000001", "Pontos deve ser menor ou igual a 1000000" ],
    [ "9" * 25, "Pontos deve ser menor ou igual a 1000000" ] ].each do |points, message|
    test "update rejects points #{points.inspect}" do
      link = @activity.activity_exercises.create!(exercise: @exercise, position: 1, points: 10)
      patch activity_exercise_url(link), params: { activity_exercise: { points: } }
      assert_response :unprocessable_entity
      assert_equal [ message ], errors_list
      assert_equal 10, link.reload.points
    end
  end

  test "update accepts valid points and keeps position" do
    link = @activity.activity_exercises.create!(exercise: @exercise, position: 1, points: 10)
    patch activity_exercise_url(link), params: { activity_exercise: { points: "25" } }
    assert_redirected_to activity_exercise_url(link)
    assert_equal [ 25, 1 ], [ link.reload.points, link.position ]
  end

  # Posição

  [ "1.5", "abc", "-1", (2**31).to_s, "9" * 25 ].each do |position|
    test "update rejects position #{position.inspect} without failing" do
      link = @activity.activity_exercises.create!(exercise: @exercise, position: 1, points: 10)
      patch activity_exercise_url(link), params: { activity_exercise: { position: } }
      assert_response :unprocessable_entity
      assert_equal 1, errors_list.size
      assert_match(/\APosição/, errors_list.first)
      assert_equal 1, link.reload.position
    end
  end

  test "position accepts the technical limit and append keeps working" do
    link = @activity.activity_exercises.create!(exercise: @exercise, position: 1, points: 10)
    patch activity_exercise_url(link), params: { activity_exercise: { position: ActivityExercise::MAX_POSITION } }
    assert_redirected_to activity_exercise_url(link)

    other = create_exercise("Outro")
    post activity_exercises_url, params: { activity_exercise: { activity_id: @activity.id, exercise_id: other.id, points: 5 } }
    assert_redirected_to activity_url(@activity)
    assert_equal [ 1, 2 ], @activity.activity_exercises.active.ordered.pluck(:position)
  end

  test "automatic reorder keeps consecutive positions" do
    second = create_exercise("Segundo")
    post activity_exercises_url, params: link_params(5)
    post activity_exercises_url, params: { activity_exercise: { activity_id: @activity.id, exercise_id: second.id, points: 5 } }
    assert_equal [ 1, 2 ], @activity.activity_exercises.active.ordered.pluck(:position)
    ids = @activity.activity_exercises.active.ordered.pluck(:id)
    patch reorder_activity_exercises_url(@activity), params: { ordered_ids: ids.reverse }, as: :json
    assert_response :ok
    assert_equal ids.reverse, @activity.activity_exercises.active.ordered.pluck(:id)
  end

  # Formulários

  test "assignment form on the activity has required fields" do
    get activity_url(@activity)
    assert_select "select[name='activity_exercise[exercise_id]'][required]"
    assert_select "input[name='activity_exercise[points]'][required][min='0'][max='1000000'][step='1']"
  end

  test "activity exercise form has required fields" do
    get new_activity_exercise_url
    %w[activity_id exercise_id].each { |field| assert_select "select[name='activity_exercise[#{field}]'][required]" }
    %w[position points].each { |field| assert_select "input[name='activity_exercise[#{field}]'][required]" }
  end

  test "enrollment form has required selects" do
    get new_class_student_url
    %w[student_id class_id].each { |field| assert_select "select[name='class_student[#{field}]'][required]" }
  end

  # Cadastro

  %w[teacher student].each do |role|
    test "#{role} registration limits name to 150 and username to 50 characters" do
      model = role.capitalize.constantize
      build = ->(name, username) { model.new(name:, username:, email: "#{SecureRandom.hex(4)}@example.com", password: "secret123") }

      assert build.call("n" * 150, "u" * 50).valid?
      long_name = build.call("n" * 151, "u")
      assert_not long_name.valid?
      assert_equal [ "Nome é muito longo (máximo: 150 caracteres)" ], long_name.errors.full_messages
      long_username = build.call("n", "u" * 51)
      assert_not long_username.valid?
      assert_equal [ "Usuário é muito longo (máximo: 50 caracteres)" ], long_username.errors.full_messages
    end

    test "#{role} registration form rejects long values and exposes maxlength" do
      get register_url(role)
      assert_select "input[name='registration[name]'][maxlength='150']"
      assert_select "input[name='registration[username]'][maxlength='50']"

      assert_no_difference -> { role.capitalize.constantize.count } do
        post register_url(role), params: { registration: { name: "n" * 151, username: "u" * 51, email: "x@example.com",
                                                          password: "secret123", password_confirmation: "secret123" } }
      end
      assert_response :unprocessable_entity
    end

    test "#{role} keeps logging in by username" do
      model = role.capitalize.constantize
      model.create!(name: "N", username: "login_#{role}", email: "#{role}_login@example.com", password: "secret123")
      delete logout_url
      post login_url, params: { role:, username: "login_#{role}", password: "secret123" }
      assert_response :redirect
      assert_not_equal login_url, response.location
    end
  end
end
