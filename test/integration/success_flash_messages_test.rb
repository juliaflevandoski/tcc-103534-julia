require "test_helper"

class SuccessFlashMessagesTest < ActionDispatch::IntegrationTest
  parallelize(workers: 1)

  setup do
    @teacher = create_teacher("flash-teacher")
    @school_class = @teacher.school_classes.create!(name: "Turma base")
    @activity = @school_class.activities.create!(title: "Aula base")
    @exercise = create_quiz(@teacher, "Exercício base")
    @link = @activity.activity_exercises.create!(exercise: @exercise, position: 1, points: 2)
    sign_in(@teacher)
    follow_redirect!
  end

  test "class and activity creation and updates show one confirmation and preserve destinations" do
    post school_classes_url, params: { school_class: { name: "Nova turma" } }
    created_class = SchoolClass.order(:id).last
    assert_success_notice(school_class_url(created_class), "Turma criada com sucesso.")

    patch school_class_url(created_class), params: { school_class: { name: "Turma atualizada" } }
    assert_success_notice(school_class_url(created_class), "Turma atualizada com sucesso.")

    post activities_url, params: { activity: { class_id: created_class.id, title: "Nova aula" } }
    created_activity = Activity.order(:id).last
    assert_success_notice(activity_url(created_activity), "Aula criada com sucesso.")

    patch activity_url(created_activity), params: { activity: { title: "Aula atualizada" } }
    assert_success_notice(activity_url(created_activity), "Aula atualizada com sucesso.")

    patch activity_url(created_activity), params: { activity: { published: "1" } }
    assert_success_notice(activity_url(created_activity), "Aula publicada com sucesso.")

    patch activity_url(created_activity), params: { activity: { published: "0" } }
    assert_success_notice(activity_url(created_activity), "Aula retornou ao rascunho com sucesso.")

    patch activity_url(created_activity), params: { activity: { title: "Aula revisada" } }
    assert_success_notice(activity_url(created_activity), "Aula atualizada com sucesso.")
  end

  test "exercise creation and updates show confirmation and preserve activity context" do
    post exercises_url, params: {
      activity_id: @activity.id,
      exercise: quiz_params("Novo exercício")
    }
    created = Exercise.order(:id).last
    assert_success_notice(exercise_url(created, activity_id: @activity.id), "Exercício criado com sucesso.")

    patch exercise_url(created), params: {
      activity_id: @activity.id,
      exercise: quiz_params("Exercício atualizado")
    }
    assert_success_notice(exercise_url(created, activity_id: @activity.id), "Exercício atualizado com sucesso.")
  end

  test "memory game creation and update also show one confirmation" do
    post exercises_url, params: {
      exercise: memory_game_params("Novo jogo")
    }
    created = Exercise.order(:id).last
    assert_success_notice(exercise_url(created), "Exercício criado com sucesso.")

    patch exercise_url(created), params: {
      exercise: memory_game_params("Jogo atualizado")
    }
    assert_success_notice(exercise_url(created), "Exercício atualizado com sucesso.")
  end

  test "association creation keeps aula destination and update keeps association destination" do
    other_exercise = create_quiz(@teacher, "Exercício adicional")
    post activity_exercises_url, params: {
      activity_exercise: { activity_id: @activity.id, exercise_id: other_exercise.id, points: 3 }
    }
    created_link = @activity.activity_exercises.find_by!(exercise: other_exercise)
    assert_success_notice(activity_url(@activity), "Exercício adicionado à aula com sucesso.")

    patch activity_exercise_url(created_link), params: {
      activity_exercise: { points: 7 }
    }
    assert_success_notice(activity_exercise_url(created_link), "Associação atualizada com sucesso.")
  end

  test "validation failures do not set success messages" do
    post school_classes_url, params: { school_class: { name: "" } }
    assert_response :unprocessable_entity
    assert_nil flash[:notice]

    patch activity_url(@activity), params: { activity: { title: "" } }
    assert_response :unprocessable_entity
    assert_nil flash[:notice]

    patch activity_url(@activity), params: { activity: { published: "1", class_id: 0 } }
    assert_response :unprocessable_entity
    assert_nil flash[:notice]

    post exercises_url, params: {
      exercise: { title: "", exercise_type: "quiz", object: { questions: [] }.to_json }
    }
    assert_response :unprocessable_entity
    assert_nil flash[:notice]

    patch activity_exercise_url(@link), params: { activity_exercise: { points: "-1" } }
    assert_response :unprocessable_entity
    assert_nil flash[:notice]
  end

  test "another teacher remains unauthorized and receives no success confirmation" do
    other_teacher = create_teacher("flash-other")
    other_class = other_teacher.school_classes.create!(name: "Turma alheia")
    other_activity = other_class.activities.create!(title: "Aula alheia")
    other_exercise = create_quiz(other_teacher, "Exercício alheio")
    other_link = other_activity.activity_exercises.create!(exercise: other_exercise, position: 1, points: 2)

    sign_in(other_teacher)
    follow_redirect!

    patch school_class_url(@school_class), params: { school_class: { name: "Alterada" } }
    assert_redirected_to root_url
    assert_nil flash[:notice]

    patch activity_url(@activity), params: { activity: { title: "Alterada" } }
    assert_redirected_to root_url
    assert_nil flash[:notice]

    patch exercise_url(@exercise), params: { exercise: quiz_params("Alterado") }
    assert_redirected_to root_url
    assert_nil flash[:notice]

    patch activity_exercise_url(@link), params: { activity_exercise: { points: 99 } }
    assert_redirected_to root_url
    assert_nil flash[:notice]
  end

  private

  def assert_success_notice(path, message)
    assert_redirected_to path
    assert_equal message, flash[:notice]
    follow_redirect!
    assert_response :success
    assert_select ".notice", count: 1, text: message
  end

  def create_teacher(prefix)
    identifier = "#{prefix}-#{SecureRandom.hex(6)}"
    Teacher.create!(name: identifier, username: identifier, email: "#{identifier}@example.com", password: "secret123")
  end

  def create_quiz(teacher, title)
    teacher.exercises.create!(
      title:,
      exercise_type: :quiz,
      object: { questions: [ { question_type: "short_answer", statement: "Pergunta?", correct_answer: "Resposta" } ] }
    )
  end

  def quiz_params(title)
    {
      title:,
      exercise_type: "quiz",
      object: { questions: [ { question_type: "short_answer", statement: "Pergunta?", correct_answer: "Resposta" } ] }.to_json
    }
  end

  def memory_game_params(title)
    {
      title:,
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

  def sign_in(user)
    post login_url, params: { role: "teacher", username: user.username, password: "secret123" }
  end
end
