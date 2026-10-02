require "test_helper"

class ExerciseContentValidationTest < ActiveSupport::TestCase
  setup do
    @teacher = Teacher.create!(
      name: "Professora Validação",
      username: "contentvalidator",
      email: "contentvalidator@example.com",
      password: "secret123"
    )
  end

  test "accepts the stored JSON contract for all exercise types" do
    valid_exercises.each do |exercise_type, object|
      exercise = build_exercise(exercise_type, object)

      assert exercise.valid?, "#{exercise_type}: #{exercise.errors.full_messages.join(', ')}"
    end
  end

  test "accepts memory image upload keys only when registered by the upload controller" do
    result = Exercises::MemoryGameBuilder.call(object: {
      instructions: "Combine palavras e imagens.",
      pair_type: "word_image",
      pairs: 2.times.map do |index|
        { left: { type: "word", content: "WORD-#{index}" }, right: { type: "image", upload_key: "upload-#{index}" } }
      end
    })
    exercise = build_exercise(:memory_game, result.object)
    exercise.memory_upload_keys = %w[upload-0 upload-1]

    assert exercise.valid?, exercise.errors.full_messages.join(", ")

    untrusted_exercise = build_exercise(:memory_game, result.object)
    assert_not untrusted_exercise.valid?
  end

  test "rejects incomplete quiz, fill blanks, ordering, crossword, and memory content before persistence" do
    invalid_exercises.each do |exercise_type, object|
      exercise = build_exercise(exercise_type, object)

      assert_no_difference("Exercise.count", "#{exercise_type} should not persist malformed content") do
        assert_not exercise.save, "#{exercise_type} should be invalid"
      end
      assert exercise.errors[:object].present?, "#{exercise_type} should report a content error"
    end
  end

  test "rejects wrong JSON types and malformed answer structures" do
    invalid_cases = [
      [ :quiz, { "questions" => "not-an-array" } ],
      [ :quiz, { "questions" => [ { "question_type" => "multiple_choice", "statement" => "Question", "options" => [ { "id" => "a", "text" => "A" }, { "id" => "b", "text" => "B" } ], "correct_option_ids" => [ "missing" ] } ] } ],
      [ :fill_blanks, { "text_template" => 42, "blanks" => { "1" => "answer" } } ],
      [ :fill_blanks, { "text_template" => "{{1}}", "blanks" => { "1" => 42 } } ],
      [ :ordering, { "instructions" => "Order", "item_type" => "words", "items" => [ { "id" => "same", "label" => "A" }, { "id" => "same", "label" => "B" } ], "correct_order" => [ "same", "same" ] } ],
      [ :ordering, { "instructions" => "Order", "item_type" => "numbers", "items" => [ { "id" => "a", "label" => "one" }, { "id" => "b", "label" => "2" } ], "correct_order" => [ "a", "b" ] } ]
    ]

    invalid_cases.each do |exercise_type, object|
      exercise = build_exercise(exercise_type, object)

      assert_not exercise.valid?, "#{exercise_type} should reject #{object.inspect}"
      assert exercise.errors[:object].present?
    end
  end

  private

  def build_exercise(exercise_type, object)
    Exercise.new(teacher: @teacher, exercise_type:, object:)
  end

  def valid_exercises
    crossword = Exercises::CrosswordBuilder.call(
      instructions: "Complete as palavras.",
      seed: 17,
      words: [ { word: "APPLE", clue: "A red fruit" }, { word: "PEAR", clue: "Another fruit" } ]
    )
    memory = Exercises::MemoryGameBuilder.call(object: {
      instructions: "Combine os pares.",
      pair_type: "word_word",
      pairs: [
        { left: { type: "word", content: "DOG" }, right: { type: "word", content: "CÃO" } },
        { left: { type: "word", content: "CAT" }, right: { type: "word", content: "GATO" } }
      ]
    })

    {
      quiz: {
        "questions" => [
          {
            "question_type" => "multiple_choice",
            "statement" => "Quanto é 2 + 2?",
            "options" => [ { "id" => "a", "text" => "4" }, { "id" => "b", "text" => "5" } ],
            "correct_option_ids" => [ "a" ]
          },
          { "question_type" => "true_false", "statement" => "2 + 2 = 4?", "correct_option_ids" => [ "true" ] },
          { "question_type" => "short_answer", "statement" => "Escreva quatro.", "correct_answer" => "Quatro" }
        ]
      },
      fill_blanks: { "text_template" => "{{1}} é a capital.", "blanks" => { "1" => "Brasília" } },
      ordering: {
        "instructions" => "Ordene os itens.",
        "item_type" => "words",
        "items" => [ { "id" => "item-1", "label" => "Um" }, { "id" => "item-2", "label" => "Dois" } ],
        "correct_order" => %w[item-1 item-2]
      },
      crossword: crossword.object,
      memory_game: memory.object
    }
  end

  def invalid_exercises
    bad_crossword = valid_exercises.fetch(:crossword).deep_dup
    bad_crossword["grid"] = { "rows" => 1, "columns" => 1, "cells" => [ [ nil ] ] }

    bad_memory = Exercises::MemoryGameBuilder.call(object: {
      instructions: "Combine os pares.",
      pair_type: "word_image",
      pairs: 2.times.map do |index|
        { left: { type: "word", content: "WORD-#{index}" }, right: { type: "image", blob_id: index + 10 } }
      end
    }).object

    [
      [ :quiz, { "questions" => [] } ],
      [ :quiz, { "questions" => [ { "question_type" => "multiple_choice", "statement" => "Q", "options" => [ { "id" => "a", "text" => "A" } ], "correct_option_ids" => [ "a" ] } ] } ],
      [ :fill_blanks, { "text_template" => "{{1}} e {{2}}", "blanks" => { "1" => "um" } } ],
      [ :fill_blanks, { "text_template" => "{{1}}", "blanks" => { "1" => "", "2" => "extra" } } ],
      [ :ordering, { "instructions" => "Ordene", "item_type" => "words", "items" => [ { "id" => "item-1", "label" => "Um" }, { "id" => "item-2", "label" => "Dois" } ], "correct_order" => [ "item-1" ] } ],
      [ :ordering, { "instructions" => "Ordene", "item_type" => "words", "items" => [ { "id" => "item-1", "label" => "Mesmo" }, { "id" => "item-2", "label" => "Mesmo" } ], "correct_order" => %w[item-1 item-2] } ],
      [ :ordering, { "instructions" => "Ordene", "item_type" => "invalid", "items" => [], "correct_order" => [] } ],
      [ :crossword, bad_crossword ],
      [ :memory_game, { "instructions" => "Combine", "pair_type" => "word_image", "pairs" => [ { "left" => { "type" => "word", "content" => "DOG" }, "right" => { "type" => "word", "content" => "CAT" } } ] } ],
      [ :memory_game, bad_memory ]
    ]
  end
end
