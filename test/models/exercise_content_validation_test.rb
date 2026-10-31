require "test_helper"

class ExerciseContentValidationTest < ActiveSupport::TestCase
  setup do
    @teacher = Teacher.create!(
      name: "Professora Validação",
      username: "contentvalidator-#{SecureRandom.hex(6)}",
      email: "contentvalidator-#{SecureRandom.hex(6)}@example.com",
      password: "secret123"
    )
  end

  test "accepts the stored JSON contract for all exercise types" do
    valid_exercises.each do |exercise_type, object|
      exercise = build_exercise(exercise_type, object)

      assert exercise.valid?, "#{exercise_type}: #{exercise.errors.full_messages.join(', ')}"
    end
  end

  test "accepts legacy ordering JSON without a format discriminator" do
    object = valid_exercises.fetch(:ordering)

    assert_not object.key?("format")
    assert build_exercise(:ordering, object).valid?
  end

  test "accepts multiple sentences with repeated words and punctuation" do
    object = multiple_sentences_ordering([
      sentence("sentence-1", [ [ "word-1", "Olá," ], [ "word-2", "mundo!" ] ], %w[word-1 word-2]),
      sentence("sentence-2", [ [ "word-3", "Olá," ], [ "word-4", "mundo?" ] ], %w[word-3 word-4])
    ])

    exercise = build_exercise(:ordering, object)

    assert exercise.valid?, exercise.errors.full_messages.join(", ")
  end

  test "multiple sentence ordering can be published, linked to a published activity, and edited" do
    object = multiple_sentences_ordering([
      sentence("sentence-1", [ [ "word-1", "Olá," ], [ "word-2", "mundo!" ] ], %w[word-1 word-2]),
      sentence("sentence-2", [ [ "word-3", "Tudo" ], [ "word-4", "bem?" ] ], %w[word-3 word-4])
    ])
    exercise = @teacher.exercises.create!(title: "Frases", exercise_type: :ordering, object:)
    school_class = @teacher.school_classes.create!(name: "Turma em rascunho")
    draft_activity = school_class.activities.create!(title: "Aula em rascunho")
    existing_link = draft_activity.activity_exercises.create!(exercise:, position: 1, points: 10)
    assert draft_activity.update(published: true), draft_activity.errors.full_messages.join(", ")

    another_exercise = @teacher.exercises.create!(title: "Mais frases", exercise_type: :ordering, object:)
    published_link = draft_activity.activity_exercises.create!(exercise: another_exercise, position: 2, points: 10)
    assert published_link.persisted?
    assert exercise.update(object: object), exercise.errors.full_messages.join(", ")
    assert_equal object, existing_link.exercise.reload.object
  end

  test "rejects multiple sentence contracts with insufficient phrases or words" do
    invalid_objects = [
      multiple_sentences_ordering([ sentence("sentence-1", [ [ "word-1", "Olá" ], [ "word-2", "mundo" ] ], %w[word-1 word-2]) ]),
      multiple_sentences_ordering([
        sentence("sentence-1", [ [ "word-1", "Olá" ] ], [ "word-1" ]),
        sentence("sentence-2", [ [ "word-2", "Tudo" ], [ "word-3", "bem?" ] ], %w[word-2 word-3])
      ])
    ]

    invalid_objects.each do |object|
      exercise = build_exercise(:ordering, object)

      assert_not exercise.valid?, object.inspect
      assert exercise.errors[:object].present?
    end
  end

  test "rejects missing, duplicate, or unknown sentence and word IDs" do
    valid_sentences = [
      sentence("sentence-1", [ [ "word-1", "Olá" ], [ "word-2", "mundo" ] ], %w[word-1 word-2]),
      sentence("sentence-2", [ [ "word-3", "Tudo" ], [ "word-4", "bem" ] ], %w[word-3 word-4])
    ]
    invalid_sentences = [
      valid_sentences.deep_dup.tap { |sentences| sentences.last["id"] = "sentence-1" },
      valid_sentences.deep_dup.tap { |sentences| sentences.first.delete("id") },
      valid_sentences.deep_dup.tap { |sentences| sentences.last["items"].last["id"] = "word-2" },
      valid_sentences.deep_dup.tap { |sentences| sentences.first["items"].first.delete("id") },
      valid_sentences.deep_dup.tap { |sentences| sentences.first["correct_order"][1] = "unknown-word" }
    ]

    invalid_sentences.each do |sentences|
      exercise = build_exercise(:ordering, multiple_sentences_ordering(sentences))

      assert_not exercise.valid?, sentences.inspect
      assert exercise.errors[:object].present?
    end
  end

  test "rejects malformed sentences, empty words, whitespace in words, and ambiguous legacy fields" do
    valid_sentences = [
      sentence("sentence-1", [ [ "word-1", "Olá" ], [ "word-2", "mundo" ] ], %w[word-1 word-2]),
      sentence("sentence-2", [ [ "word-3", "Tudo" ], [ "word-4", "bem" ] ], %w[word-3 word-4])
    ]
    invalid_objects = [
      multiple_sentences_ordering([ "not-an-object", *valid_sentences.drop(1) ]),
      multiple_sentences_ordering(valid_sentences.deep_dup.tap { |sentences| sentences.first["items"].first["label"] = " " }),
      multiple_sentences_ordering(valid_sentences.deep_dup.tap { |sentences| sentences.first["items"].first["label"] = "duas palavras" }),
      multiple_sentences_ordering(valid_sentences).merge("items" => [], "correct_order" => []),
      multiple_sentences_ordering(valid_sentences).merge("format" => nil),
      multiple_sentences_ordering(valid_sentences).merge("format" => "unknown")
    ]

    invalid_objects.each do |object|
      exercise = build_exercise(:ordering, object)

      assert_not exercise.valid?, object.inspect
      assert exercise.errors[:object].present?
    end
  end

  test "rejects incomplete or duplicated per-sentence correct orders" do
    valid_sentences = [
      sentence("sentence-1", [ [ "word-1", "Olá" ], [ "word-2", "mundo" ] ], %w[word-1 word-2]),
      sentence("sentence-2", [ [ "word-3", "Tudo" ], [ "word-4", "bem" ] ], %w[word-3 word-4])
    ]
    invalid_sentences = [
      valid_sentences.deep_dup.tap { |sentences| sentences.first["correct_order"] = [ "word-1" ] },
      valid_sentences.deep_dup.tap { |sentences| sentences.first["correct_order"] = %w[word-1 word-1] },
      valid_sentences.deep_dup.tap { |sentences| sentences.first["correct_order"] = [ "word-1", 2 ] },
      valid_sentences.deep_dup.tap { |sentences| sentences.first.delete("correct_order") }
    ]

    invalid_sentences.each do |sentences|
      exercise = build_exercise(:ordering, multiple_sentences_ordering(sentences))

      assert_not exercise.valid?, sentences.inspect
      assert exercise.errors[:object].present?
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
    Exercise.new(teacher: @teacher, title: "Exercicio de teste", exercise_type:, object:)
  end

  def multiple_sentences_ordering(sentences)
    { "format" => "multiple_sentences", "instructions" => "Organize as frases.", "sentences" => sentences }
  end

  def sentence(id, items, correct_order)
    { "id" => id, "items" => items.map { |item_id, label| { "id" => item_id, "label" => label } }, "correct_order" => correct_order }
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
