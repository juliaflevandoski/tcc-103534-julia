require "test_helper"

class ExerciseMissingObjectTest < ActionDispatch::IntegrationTest
  parallelize(workers: 1)

  setup do
    @teacher = Teacher.create!(name: "Professora", username: "profsemobj", email: "semobj@example.com", password: "secret123")
    post login_url, params: { role: "teacher", username: @teacher.username, password: "secret123" }
  end

  %w[crossword memory_game].each do |type|
    test "creating #{type} without the object parameter returns 422 with a clear message" do
      assert_no_difference -> { Exercise.count } do
        post exercises_url, params: { exercise: { exercise_type: type, title: "Título preservado" } }
      end

      assert_response :unprocessable_entity
      assert_select ".errors"
      assert_select "input[name='exercise[title]'][value='Título preservado']"
    end

    test "creating #{type} with a null or non-object content returns 422" do
      [ "null", "[]", "\"texto\"", "123" ].each do |content|
        assert_no_difference -> { Exercise.count } do
          post exercises_url, params: { exercise: { exercise_type: type, title: "Título", object: content } }
        end
        assert_response :unprocessable_entity, content
      end
    end

    test "updating #{type} without the object parameter returns 422 and keeps the stored content" do
      exercise = create_valid(type)
      before = exercise.reload.object

      patch exercise_url(exercise), params: { exercise: { title: "Novo título" } }

      assert_response :unprocessable_entity
      assert_equal before, exercise.reload.object
      assert_equal "Exercício #{type}", exercise.title
    end
  end

  test "valid crossword creation still works" do
    post exercises_url, params: { exercise: { exercise_type: "crossword", title: "Cruzadinha", object: {
      instructions: "Preencha.", words: [ { word: "GATO", clue: "Animal" }, { word: "OVO", clue: "Alimento" } ]
    }.to_json } }

    assert_redirected_to exercise_url(Exercise.order(:id).last)
  end

  test "valid memory creation still works" do
    post exercises_url, params: { exercise: { exercise_type: "memory_game", title: "Memória", object: memory_object.to_json } }

    assert_redirected_to exercise_url(Exercise.order(:id).last)
  end

  private

  def memory_object
    { instructions: "Combine.", pair_type: "word_word", pairs: [
      { left: { type: "word", content: "CAT" }, right: { type: "word", content: "GATO" } },
      { left: { type: "word", content: "DOG" }, right: { type: "word", content: "CACHORRO" } }
    ] }
  end

  def create_valid(type)
    content = type == "memory_game" ? memory_object : { instructions: "Preencha.", words: [ { word: "GATO", clue: "Animal" }, { word: "OVO", clue: "Alimento" } ] }
    post exercises_url, params: { exercise: { exercise_type: type, title: "Exercício #{type}", object: content.to_json } }
    Exercise.order(:id).last
  end
end
