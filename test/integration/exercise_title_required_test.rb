require "test_helper"

class ExerciseTitleRequiredTest < ActionDispatch::IntegrationTest
  parallelize(workers: 1)

  MESSAGE = "Informe o título do exercício.".freeze

  PAYLOADS = {
    "quiz" => { questions: [ { question_type: "short_answer", statement: "Qual a capital?", correct_answer: "Brasilia" } ] },
    "fill_blanks" => { text_template: "A capital do {{1}} e {{2}}.", blanks: { "1" => "Brasil", "2" => "Brasilia" } },
    "ordering" => {
      instructions: "Coloque as etapas em ordem.", item_type: "words",
      items: [ { id: "item-2", label: "Condensacao" }, { id: "item-1", label: "Evaporacao" } ],
      correct_order: [ "item-1", "item-2" ]
    },
    "crossword" => { instructions: "Complete", words: [ { word: "APPLE", clue: "Fruta" }, { word: "PEAR", clue: "Outra fruta" } ], layout_seed: 17 },
    "memory_game" => {
      instructions: "Combine os nomes.", pair_type: "word_word",
      pairs: [
        { id: "a", left: { type: "word", content: "DOG" }, right: { type: "word", content: "CACHORRO" } },
        { id: "b", left: { type: "word", content: "CAT" }, right: { type: "word", content: "GATO" } }
      ]
    }
  }.freeze

  setup do
    @teacher = Teacher.create!(name: "Prof", username: "title-#{SecureRandom.hex(5)}", email: "title-#{SecureRandom.hex(5)}@example.com", password: "secret123")
    post login_url, params: { role: "teacher", username: @teacher.username, password: "secret123" }
  end

  PAYLOADS.each do |type, object|
    test "#{type} is created with a title" do
      assert_difference -> { Exercise.count } => 1 do
        post exercises_url, params: { exercise: { title: "Titulo #{type}", exercise_type: type, object: object.to_json } }
      end
      assert_redirected_to exercise_url(Exercise.order(:id).last)
      assert_equal "Titulo #{type}", Exercise.order(:id).last.title
    end

    test "#{type} without title is rejected in Portuguese" do
      [ nil, "", "   " ].each do |title|
        assert_no_difference -> { Exercise.count } do
          post exercises_url, params: { exercise: { title:, exercise_type: type, object: object.to_json } }
        end
        assert_response :unprocessable_entity
        assert_includes response.body, MESSAGE
      end
    end

    test "#{type} cannot lose its title on edit" do
      exercise = create_exercise(type, object)
      before = exercise.reload.attributes

      [ "", "   " ].each do |title|
        patch exercise_url(exercise), params: { exercise: { title:, exercise_type: type, object: object.to_json } }
        assert_response :unprocessable_entity
        assert_includes response.body, MESSAGE
      end
      assert_equal before, exercise.reload.attributes
    end

    test "#{type} edit keeps working with a title" do
      exercise = create_exercise(type, object)

      patch exercise_url(exercise), params: { exercise: { title: "Novo titulo", exercise_type: type, object: object.to_json } }

      assert_redirected_to exercise_url(exercise)
      assert_equal "Novo titulo", exercise.reload.title
    end
  end

  test "content is preserved in the form after a missing title error" do
    post exercises_url, params: { exercise: { title: "", exercise_type: "quiz", object: PAYLOADS["quiz"].to_json } }

    assert_response :unprocessable_entity
    assert_includes response.body, "Qual a capital?"
  end

  test "AI draft without title is not saved but saves once the teacher adds a title" do
    draft = PAYLOADS["fill_blanks"]

    assert_no_difference -> { Exercise.count } do
      post exercises_url, params: { exercise: { exercise_type: "fill_blanks", object: draft.to_json } }
    end
    assert_response :unprocessable_entity

    assert_difference -> { Exercise.count } => 1 do
      post exercises_url, params: { exercise: { title: "Revisado pelo professor", exercise_type: "fill_blanks", object: draft.to_json } }
    end
  end

  test "title requirement does not change the stored content" do
    post exercises_url, params: { exercise: { title: "Quiz", exercise_type: "quiz", object: PAYLOADS["quiz"].to_json } }

    assert_equal "Brasilia", Exercise.order(:id).last.object["questions"].first["correct_answer"]
  end

  private

  def create_exercise(type, object)
    post exercises_url, params: { exercise: { title: "Original #{type}", exercise_type: type, object: object.to_json } }
    Exercise.order(:id).last
  end
end
