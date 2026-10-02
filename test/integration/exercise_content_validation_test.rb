require "test_helper"

class ExerciseContentValidationFlowTest < ActionDispatch::IntegrationTest
  setup do
    @teacher = Teacher.create!(name: "Professora", username: "exercisevalidation", email: "exercisevalidation@example.com", password: "secret123")
    post login_url, params: { role: "teacher", username: @teacher.username, password: "secret123" }
  end

  test "teacher cannot persist malformed quiz, fill blanks, or ordering content" do
    invalid_exercises = [
      {
        title: "Quiz incompleto",
        exercise_type: "quiz",
        object: { questions: [ { question_type: "multiple_choice", statement: "Escolha", options: [ { id: "a", text: "A" }, { id: "b", text: "B" } ], correct_option_ids: [ "missing" ] } ] }
      },
      {
        title: "Lacunas incompletas",
        exercise_type: "fill_blanks",
        object: { text_template: "{{1}} e {{2}}", blanks: { "1" => "um" } }
      },
      {
        title: "Ordenação incompleta",
        exercise_type: "ordering",
        object: { instructions: "Ordene", item_type: "words", items: [ { id: "a", label: "Um" }, { id: "b", label: "Dois" } ], correct_order: [ "a", "a" ] }
      },
      {
        title: "Cruzadinha incompleta",
        exercise_type: "crossword",
        object: { instructions: "Complete", layout_seed: 17, words: [ { word: "APPLE", clue: "Fruta" } ], grid: { rows: 1, columns: 1, cells: [ [ "X" ] ] } }
      },
      {
        title: "Memória incompatível",
        exercise_type: "memory_game",
        object: {
          instructions: "Combine",
          pair_type: "word_image",
          pairs: [
            { left: { type: "word", content: "A" }, right: { type: "word", content: "B" } },
            { left: { type: "word", content: "C" }, right: { type: "word", content: "D" } }
          ]
        }
      }
    ]

    invalid_exercises.each do |attributes|
      assert_no_difference("Exercise.count") do
        post exercises_url, params: { exercise: attributes.merge(object: attributes.fetch(:object).to_json) }
      end
      assert_response :unprocessable_entity
    end
  end

  test "invalid updates do not replace previously valid content" do
    exercise = @teacher.exercises.create!(
      title: "Quiz válido",
      exercise_type: :quiz,
      object: {
        "questions" => [
          {
            "question_type" => "short_answer",
            "statement" => "Qual é a resposta?",
            "correct_answer" => "42"
          }
        ]
      }
    )
    original_object = exercise.object.deep_dup

    patch exercise_url(exercise), params: {
      exercise: {
        object: { questions: [ { question_type: "short_answer", statement: "Sem resposta correta" } ] }.to_json
      }
    }

    assert_response :unprocessable_entity
    assert_equal original_object, exercise.reload.object
  end
end
