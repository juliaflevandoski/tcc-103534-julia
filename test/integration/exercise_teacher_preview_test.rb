require "test_helper"

class ExerciseTeacherPreviewTest < ActionDispatch::IntegrationTest
  parallelize(workers: 1)

  setup do
    @teacher = Teacher.create!(
      name: "Professor Preview",
      username: "teacher-preview-#{SecureRandom.hex(6)}",
      email: "teacher-preview-#{SecureRandom.hex(6)}@example.com",
      password: "secret123"
    )
    post login_url, params: { role: "teacher", username: @teacher.username, password: "secret123" }
  end

  test "teacher sees readable quiz questions and answer keys without raw JSON or technical IDs" do
    quiz = @teacher.exercises.create!(
      title: "Quiz de preview",
      exercise_type: :quiz,
      object: {
        "questions" => [
          {
            "question_type" => "multiple_choice",
            "statement" => "Qual é a capital da França?",
            "options" => [ { "id" => "secret-option-id", "text" => "Paris" }, { "id" => "other-id", "text" => "Lyon" } ],
            "correct_option_ids" => [ "secret-option-id" ]
          },
          { "question_type" => "true_false", "statement" => "A água ferve a 100 graus?", "correct_option_ids" => [ "true" ] },
          { "question_type" => "short_answer", "statement" => "Qual resposta não deve aparecer ao aluno?", "correct_answer" => "TeacherSecretAnswer" }
        ]
      }
    )

    get exercise_url(quiz)

    assert_response :success
    assert_select "ol.quiz-questions > li", count: 3
    assert_select "legend", text: /Questão 1.*Múltipla escolha/
    assert_select "ol.quiz-questions ul > li", text: /Paris/
    assert_select "ol.quiz-questions ul > li strong.quiz-correct-badge", text: "Correta", count: 1
    assert_select ".quiz-question p", text: /Resposta correta: Verdadeiro/
    assert_select ".quiz-question p", text: /Resposta esperada: TeacherSecretAnswer/
    assert_not_includes response.body, "question_type"
    assert_not_includes response.body, "correct_option_ids"
    assert_not_includes response.body, "secret-option-id"
    assert_not_includes response.body, "<pre>"
  end

  test "teacher sees fill blanks as visible slots and a separate readable answer key" do
    exercise = @teacher.exercises.create!(
      title: "Lacunas de geografia",
      exercise_type: :fill_blanks,
      object: { "text_template" => "A capital do {{1}} é {{2}}.", "blanks" => { "1" => "Brasil", "2" => "Brasília" } }
    )

    get exercise_url(exercise)

    assert_response :success
    assert_select ".fill-blanks-teacher-preview .fill-blanks-text", text: /A capital do.*é/
    assert_select ".fill-blanks-teacher-preview .fill-blank-input", count: 2
    assert_select ".fill-blanks-teacher-preview .fill-blanks-feedback li", count: 2
    assert_includes response.body, "Resposta esperada: Brasil"
    assert_includes response.body, "Resposta esperada: Brasília"
    assert_not_includes response.body, "text_template"
    assert_not_includes response.body, "{{1}}"
    assert_not_includes response.body, "<pre>"
  end

  test "teacher sees ordering instructions and labels in correct order without IDs or JSON" do
    exercise = @teacher.exercises.create!(
      title: "Etapas de uma planta",
      exercise_type: :ordering,
      object: {
        "instructions" => "Ordene as etapas de crescimento.",
        "item_type" => "words",
        "items" => [ { "id" => "item-1", "label" => "Semente" }, { "id" => "item-2", "label" => "Muda" }, { "id" => "item-3", "label" => "Planta" } ],
        "correct_order" => %w[item-1 item-2 item-3]
      }
    )

    get exercise_url(exercise)

    assert_response :success
    assert_includes response.body, "Ordene as etapas de crescimento."
    assert_select ".ordering-teacher-preview li", count: 3
    ordered_labels = css_select(".ordering-teacher-preview li").map(&:text)
    assert_equal %w[Semente Muda Planta], ordered_labels
    assert_not_includes response.body, "item-1"
    assert_not_includes response.body, "correct_order"
    assert_not_includes response.body, "<pre>"
  end

  test "new and edit forms hide raw JSON while retaining the exercise object field for create and update" do
    get new_exercise_url

    assert_response :success
    assert_select "div[data-exercise-form-target='rawFields'][hidden] textarea[data-exercise-form-target='rawObject']", count: 1
    assert_select "input[type='hidden'][name='exercise[object]']", count: 1

    object = {
      "questions" => [
        { "question_type" => "short_answer", "statement" => "Qual é a capital da França?", "correct_answer" => "Paris" }
      ]
    }
    assert_difference("Exercise.count") do
      post exercises_url, params: { exercise: { title: "Quiz oculto", exercise_type: "quiz", object: object.to_json } }
    end
    exercise = @teacher.exercises.order(:id).last
    assert_redirected_to exercise_url(exercise)
    assert_equal object, exercise.object

    get edit_exercise_url(exercise)

    assert_response :success
    assert_select "div[data-exercise-form-target='rawFields'][hidden] textarea[data-exercise-form-target='rawObject']", count: 1
    assert_select "input[type='hidden'][name='exercise[object]']", count: 1

    updated_object = {
      "questions" => [
        { "question_type" => "short_answer", "statement" => "Qual é a capital da Itália?", "correct_answer" => "Roma" }
      ]
    }
    patch exercise_url(exercise), params: { exercise: { object: updated_object.to_json } }

    assert_redirected_to exercise_url(exercise)
    assert_equal updated_object, exercise.reload.object
  end

  test "each AI generation dialog has a Cancel button and native close invalidation" do
    get new_exercise_url

    assert_response :success
    %w[quizAiModal fillBlanksAiModal orderingAiModal crosswordAiModal memoryGameAiModal].each do |target|
      assert_select "dialog[data-exercise-form-target='#{target}'][data-action~='close->exercise-form#invalidateAiGeneration']", count: 1 do
        assert_select "button[type='button'][data-action='exercise-form#closeAiModal']", text: "Cancelar", count: 1
      end
    end
  end

  test "student pages keep answer keys out of Quiz, fill blanks, and ordering HTML" do
    student = Student.create!(
      name: "Aluno Preview",
      username: "student-preview-#{SecureRandom.hex(6)}",
      email: "student-preview-#{SecureRandom.hex(6)}@example.com",
      password: "secret123"
    )
    school_class = @teacher.school_classes.create!(name: "Turma Preview", active: true)
    school_class.class_students.create!(student:, active: true)
    activity = school_class.activities.create!(title: "Aula Preview", published: true)
    exercises = [
      @teacher.exercises.create!(title: "Quiz seguro", exercise_type: :quiz, object: {
        "questions" => [
          { "question_type" => "multiple_choice", "statement" => "Enunciado do Quiz", "options" => [ { "id" => "option-a", "text" => "Alternativa A" }, { "id" => "option-b", "text" => "Alternativa B" } ], "correct_option_ids" => [ "option-a" ] },
          { "question_type" => "short_answer", "statement" => "Enunciado curto", "correct_answer" => "RespostaSecretaQuiz" }
        ]
      }),
      @teacher.exercises.create!(title: "Lacunas seguras", exercise_type: :fill_blanks, object: {
        "text_template" => "A resposta é {{1}}.", "blanks" => { "1" => "RespostaSecretaLacuna" }
      }),
      @teacher.exercises.create!(title: "Ordem segura", exercise_type: :ordering, object: {
        "instructions" => "Ordene os itens.",
        "item_type" => "words",
        "items" => [ { "id" => "item-1", "label" => "Primeiro" }, { "id" => "item-2", "label" => "Segundo" } ],
        "correct_order" => %w[item-1 item-2]
      })
    ]
    links = exercises.each_with_index.map do |exercise, index|
      activity.activity_exercises.create!(exercise:, position: index + 1, points: 10)
    end
    delete logout_url
    post login_url, params: { role: "student", username: student.username, password: "secret123" }

    exercises.zip(links).each do |exercise, link|
      get exercise_url(exercise, activity_exercise_id: link.id)

      assert_response :success
      assert_not_includes response.body, "<pre>"
      assert_not_includes response.body, "correct_option_ids"
      assert_not_includes response.body, "correct_answer"
      assert_not_includes response.body, "RespostaSecretaQuiz"
      assert_not_includes response.body, "RespostaSecretaLacuna"
      assert_not_includes response.body, "correct_order"
      assert_not_includes response.body, "teacher-only"
    end
  end

  test "existing teacher Crossword and Memory previews keep their specialized presentations" do
    crossword_result = Exercises::CrosswordBuilder.call(
      instructions: "Complete a cruzadinha.",
      seed: 17,
      words: [ { word: "APPLE", clue: "A red fruit" }, { word: "PEAR", clue: "Another fruit" } ]
    )
    crossword = @teacher.exercises.create!(title: "Cruzadinha", exercise_type: :crossword, object: crossword_result.object)

    get exercise_url(crossword)
    assert_response :success
    assert_select "table.crossword-grid.crossword-teacher-grid"
    assert_includes response.body, "APPLE"
    assert_not_includes response.body, "<pre>"

    memory_result = Exercises::MemoryGameBuilder.call(object: {
      instructions: "Combine os pares.",
      pair_type: "word_word",
      pairs: [
        { left: { type: "word", content: "DOG" }, right: { type: "word", content: "CÃO" } },
        { left: { type: "word", content: "CAT" }, right: { type: "word", content: "GATO" } }
      ]
    })
    memory = @teacher.exercises.create!(title: "Memória", exercise_type: :memory_game, object: memory_result.object)

    get exercise_url(memory)
    assert_response :success
    assert_select ".memory-board-preview .memory-card", count: 4
    assert_select ".memory-pair-summary li", count: 2
    assert_includes response.body, "CÃO"
    assert_not_includes response.body, "<pre>"
  end
end
