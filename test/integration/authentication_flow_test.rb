require "test_helper"
require "base64"
require "tempfile"

class AuthenticationFlowTest < ActionDispatch::IntegrationTest
  test "requires login and offers both profiles" do
    get root_url

    assert_redirected_to login_url
    follow_redirect!
    assert_select "a", text: "Entrar como professor"
    assert_select "a", text: "Entrar como aluno"
  end

  test "registers and logs in an open student account" do
    assert_difference("Student.count") do
      post register_url("student"), params: {
        registration: {
          name: "Joana", username: "joana", email: "joana@example.com",
          password: "secret123", password_confirmation: "secret123"
        }
      }
    end

    assert_redirected_to root_url
    delete logout_url
    post login_url, params: { role: "student", username: "joana", password: "secret123" }
    assert_redirected_to root_url
  end

  test "does not reveal whether password reset email exists" do
    post new_password_reset_url, params: { role: "student", email: "missing@example.com" }

    assert_redirected_to login_url(role: "student")
    assert_equal "Se os dados estiverem corretos, enviaremos instruções para redefinir sua senha.", flash[:notice]
  end

  test "resets password with a valid token" do
    student = Student.create!(name: "Aluno", username: "aluno3", email: "aluno3@example.com", password: "oldsecret")
    student.update!(password_reset_token: "reset-token", password_reset_sent_at: Time.current)
    assert_not student.reload.password_reset_expired?

    get edit_password_reset_url("student", "reset-token")
    assert_response :success

    patch edit_password_reset_url("student", "reset-token"), params: {
      user: { password: "newsecret", password_confirmation: "newsecret" }
    }

    assert_redirected_to login_url(role: "student")
    assert_equal "Senha redefinida com sucesso.", flash[:notice]
    assert Student.find(student.id).authenticate("newsecret")
  end

  test "student cannot access exercise index" do
    student = Student.create!(name: "Aluno", username: "aluno", email: "aluno@example.com", password: "secret123")
    post login_url, params: { role: "student", username: student.username, password: "secret123" }

    get exercises_url

    assert_redirected_to root_url
  end

  test "student sees only their own exercise attempts" do
    _teacher, student, _exercise, activity_exercise = create_student_memory_game(points: 6)
    other_student = Student.create!(name: "Outro aluno", username: "outroaluno", email: "outroaluno@example.com", password: "secret123")
    game = Exercises::MemoryGamePlay.start(object: activity_exercise.exercise.object, points: activity_exercise.points)
    own_attempt = ExerciseAttempt.create!(student:, activity_exercise:, answer: game.fetch("answer"), correct: game.fetch("correct"))
    other_attempt = ExerciseAttempt.create!(student: other_student, activity_exercise:, answer: game.fetch("answer"), correct: game.fetch("correct"))
    post login_url, params: { role: "student", username: student.username, password: "secret123" }

    get exercise_attempts_url

    assert_response :success
    assert_select "tbody tr", count: 1
    assert_select "tbody tr td", text: student.name
    assert_not_includes response.body, other_student.name
    assert_select "a[href='#{exercise_attempt_path(own_attempt)}']", text: "Ver", count: 1
    assert_select "a[href='#{exercise_attempt_path(other_attempt)}']", count: 0
  end

  test "student can join and leave a class" do
    teacher = Teacher.create!(name: "Professora", username: "prof", email: "prof@example.com", password: "secret123")
    school_class = teacher.school_classes.create!(name: "História")
    student = Student.create!(name: "Aluno", username: "aluno2", email: "aluno2@example.com", password: "secret123")
    post login_url, params: { role: "student", username: student.username, password: "secret123" }

    post join_school_classes_url, params: { access_code: school_class.access_code }
    assert school_class.class_students.active.exists?(student_id: student.id)

    delete leave_school_class_url(school_class)
    assert_not school_class.class_students.active.exists?(student_id: student.id)
  end

  test "teacher creates an exercise and links it from the activity" do
    teacher = Teacher.create!(name: "Professora 2", username: "prof2", email: "prof2@example.com", password: "secret123")
    school_class = teacher.school_classes.create!(name: "Matemática")
    activity = school_class.activities.create!(title: "Aula 1")
    post login_url, params: { role: "teacher", username: teacher.username, password: "secret123" }

    get new_exercise_url
    assert_select "select[name='exercise[exercise_type]'] option[value='quiz']"
    assert_select "fieldset[data-exercise-form-target='memoryGameFields']"
    assert_select "select[data-exercise-form-target='memoryPairType'] option[value='word_word']"
    assert_select "select[data-exercise-form-target='memoryPairType'] option[value='word_image']"
    assert_select "select[data-exercise-form-target='memoryPairType'] option[value='image_image']"
    assert_select "template[data-exercise-form-target='memoryPairTemplate'] input[data-memory-image][accept='image/png,image/jpeg,image/webp']"
    assert_select "button[data-action='exercise-form#addMemoryPair']", text: "Adicionar par"
    assert_select "button[data-action='exercise-form#previewMemoryGame']", text: "Pré-visualizar jogo"
    assert_select "button[data-action='exercise-form#convertSelection']", text: "Converter seleção em lacuna"
    assert_select "textarea[data-exercise-form-target='fillTextTemplate']"
    assert_select "div[data-exercise-form-target='blanksList']"
    assert_select "template[data-exercise-form-target='blankTemplate'] input[data-blank-answer]"
    assert_select "section[data-exercise-form-target='orderingFields']", count: 1
    assert_select "section[data-exercise-form-target='crosswordFields']", count: 1
    assert_select "button[data-action='exercise-form#previewCrossword']", text: "Gerar prévia"
    assert_select "button[data-action='exercise-form#regenerateCrossword']", text: "Gerar outra disposição"
    assert_select "template[data-exercise-form-target='crosswordWordTemplate'] input[data-crossword-word-value]"
    assert_select "template[data-exercise-form-target='crosswordWordTemplate'] input[data-crossword-clue-value]"
    assert_select "select[data-exercise-form-target='orderingItemType'] option[value='words']"
    assert_select "select[data-exercise-form-target='orderingItemType'] option[value='numbers']"
    assert_select "button[data-action='exercise-form#addOrderingItem']", text: "Adicionar item"
    assert_select "template[data-exercise-form-target='orderingItemTemplate'] [data-ordering-item][draggable='true']"
    assert_select "button[data-action='exercise-form#addQuestion']", text: "Adicionar pergunta"
    assert_select "template[data-exercise-form-target='questionTemplate'] select[data-question-type] option[value='multiple_choice']"
    assert_select "template[data-exercise-form-target='questionTemplate'] select[data-question-type] option[value='true_false']"
    assert_select "template[data-exercise-form-target='questionTemplate'] select[data-question-type] option[value='short_answer']"
    assert_select "template[data-exercise-form-target='questionTemplate'] select[data-question-type] option[value='multiple_answer']", count: 0
    assert_select "div[data-exercise-form-target='questionsList']"
    assert_select "textarea[data-exercise-form-target='rawObject']"

    assert_difference("Exercise.count") do
      post exercises_url, params: { exercise: { title: "Quiz de matemática", exercise_type: "quiz", object: { questions: [ { question_type: "multiple_choice", statement: "Quanto é 2 + 2?", options: [ { id: "a", text: "4" }, { id: "b", text: "5" } ], correct_option_ids: [ "a" ] }, { question_type: "true_false", statement: "2 + 2 é igual a 4?", correct_option_ids: [ "true" ] }, { question_type: "short_answer", statement: "Qual é o resultado?", correct_answer: "4" } ] }.to_json } }
    end

    assert_redirected_to exercise_url(Exercise.order(:id).last)
    exercise = Exercise.order(:id).last
    assert_equal %w[multiple_choice true_false short_answer], exercise.object["questions"].pluck("question_type")
    assert_equal [ "a" ], exercise.object["questions"].first["correct_option_ids"]

    get activity_url(activity)
    assert_select "form[action='#{activity_exercises_path}']"
    get edit_activity_url(activity)
    assert_select "form[action='#{activity_exercises_path}']"
    get school_class_url(school_class)
    assert_select "form[action='#{activity_exercises_path}']"

    assert_difference("ActivityExercise.count") do
      post activity_exercises_url, params: { activity_exercise: { activity_id: activity.id, exercise_id: exercise.id, points: 5 } }
    end

    assert_redirected_to activity_url(activity)
    assert_equal activity, exercise.activity_exercises.order(:id).last.activity
    assert_equal 1, exercise.activity_exercises.order(:id).last.position

    second_exercise = teacher.exercises.create!(title: "Quanto é 3 + 3?", exercise_type: "quiz", object: {
      questions: [ { question_type: "short_answer", statement: "Quanto é 3 + 3?", correct_answer: "6" } ]
    })
    post activity_exercises_url, params: { activity_exercise: { activity_id: activity.id, exercise_id: second_exercise.id, points: 7 } }
    assert_equal 2, activity.activity_exercises.active.order(:position).last.position

    patch reorder_activity_exercises_url(activity), params: { ordered_ids: [ second_exercise.activity_exercises.first.id, exercise.activity_exercises.first.id ] }, as: :json
    assert_response :success
    assert_equal [ second_exercise.id, exercise.id ], activity.reload.activity_exercises.active.order(:position).pluck(:exercise_id)

    exercise.activity_exercises.first.update!(active: false)
    third_exercise = teacher.exercises.create!(title: "Quanto é 4 + 4?", exercise_type: "quiz", object: {
      questions: [ { question_type: "short_answer", statement: "Quanto é 4 + 4?", correct_answer: "8" } ]
    })
    post activity_exercises_url, params: { activity_exercise: { activity_id: activity.id, exercise_id: third_exercise.id, points: 9 } }

    assert_redirected_to activity_url(activity)
    assert_equal 2, activity.activity_exercises.active.where(exercise: third_exercise).pick(:position)

    patch reorder_activity_exercises_url(activity), params: { ordered_ids: [ third_exercise.activity_exercises.active.first.id, second_exercise.activity_exercises.first.id ] }, as: :json
    assert_response :success
    assert_equal [ third_exercise.id, second_exercise.id ], activity.reload.activity_exercises.active.ordered.pluck(:exercise_id)

    get activity_url(activity)
    assert_select "a[href='#{new_exercise_path}']", text: "Criar exercício"
    assert_select "tr[data-id='#{second_exercise.activity_exercises.first.id}'] td form[action='#{activity_exercise_path(second_exercise.activity_exercises.first)}'] input[name='_method'][value='delete']"
    assert_select "tr[data-id='#{second_exercise.activity_exercises.first.id}'] i.fa-solid.fa-grip-vertical"
    assert_select "tr[data-id='#{second_exercise.activity_exercises.first.id}'] span[data-position]", text: "2"
    assert_operator response.body.index("action=\"#{activity_exercises_path}\""), :<, response.body.index('<table class="exercise-table"')

    delete activity_exercise_url(second_exercise.activity_exercises.first)
    assert_redirected_to activity_url(activity)
    assert_not second_exercise.activity_exercises.first.reload.active?
  end

  test "teacher saves a quiz short answer using the approved JSON contract" do
    teacher = Teacher.create!(name: "Professora Quiz", username: "profquiz", email: "profquiz@example.com", password: "secret123")
    post login_url, params: { role: "teacher", username: teacher.username, password: "secret123" }

    post exercises_url, params: {
      exercise: {
        title: "Capital do Brasil",
        exercise_type: "quiz",
        object: { questions: [ { question_type: "short_answer", statement: "Qual é a capital do Brasil?", correct_answer: "Brasília" } ] }.to_json
      }
    }

    exercise = Exercise.order(:id).last
    assert_redirected_to exercise_url(exercise)
    assert_equal "short_answer", exercise.object["questions"].first["question_type"]
    assert_equal "Brasília", exercise.object["questions"].first["correct_answer"]
  end

  test "teacher saves a fill blanks exercise using the approved JSON contract" do
    teacher = Teacher.create!(name: "Professora Lacunas", username: "proflacunas", email: "lacunas@example.com", password: "secret123")
    post login_url, params: { role: "teacher", username: teacher.username, password: "secret123" }

    post exercises_url, params: {
      exercise: {
        title: "Capitais",
        exercise_type: "fill_blanks",
        object: { text_template: "A capital do {{1}} é {{2}}.", blanks: { "1" => "Brasil", "2" => "Brasília" } }.to_json
      }
    }

    exercise = Exercise.order(:id).last
    assert_redirected_to exercise_url(exercise)
    assert_equal "A capital do {{1}} é {{2}}.", exercise.object["text_template"]
    assert_equal({ "1" => "Brasil", "2" => "Brasília" }, exercise.object["blanks"])
  end

  test "teacher saves an ordering exercise using item IDs in the answer order" do
    teacher = Teacher.create!(name: "Professora Ordem", username: "profordem", email: "ordem@example.com", password: "secret123")
    post login_url, params: { role: "teacher", username: teacher.username, password: "secret123" }

    post exercises_url, params: {
      exercise: {
        title: "Etapas do ciclo da água",
        exercise_type: "ordering",
        object: {
          instructions: "Coloque as etapas em ordem.",
          item_type: "words",
          items: [ { id: "item-2", label: "Condensação" }, { id: "item-1", label: "Evaporação" }, { id: "item-3", label: "Precipitação" } ],
          correct_order: [ "item-1", "item-2", "item-3" ]
        }.to_json
      }
    }

    exercise = Exercise.order(:id).last
    assert_redirected_to exercise_url(exercise)
    assert_equal "words", exercise.object["item_type"]
    assert_equal [ "item-1", "item-2", "item-3" ], exercise.object["correct_order"]
    assert_equal "Evaporação", exercise.object["items"].find { |item| item["id"] == "item-1" }["label"]
  end

  test "teacher creates a memory game with server-generated pair IDs" do
    teacher = Teacher.create!(name: "Professora Memória", username: "profmemoria", email: "memoria@example.com", password: "secret123")
    post login_url, params: { role: "teacher", username: teacher.username, password: "secret123" }

    post exercises_url, params: {
      exercise: {
        title: "Animais",
        exercise_type: "memory_game",
        object: {
          instructions: "Combine os nomes.",
          pair_type: "word_word",
          pairs: [
            { id: "forged-id", left: { type: "word", content: "DOG" }, right: { type: "word", content: "CACHORRO" } },
            { id: "forged-id", left: { type: "word", content: "CAT" }, right: { type: "word", content: "GATO" } }
          ]
        }.to_json
      }
    }

    exercise = Exercise.order(:id).last
    assert_redirected_to exercise_url(exercise)
    assert_equal "word_word", exercise.object.fetch("pair_type")
    assert_equal 2, exercise.object.fetch("pairs").length
    pair_ids = exercise.object.fetch("pairs").pluck("id")
    assert_equal 2, pair_ids.uniq.length
    assert_not_includes pair_ids, "forged-id"
    follow_redirect!
    assert_response :success
    assert_select ".memory-board-preview .memory-card", count: 4
    assert_select ".memory-pair-summary li", count: 2
    assert_includes response.body, "CACHORRO"
  end

  test "teacher cannot save a memory game with fewer than two complete pairs" do
    teacher = Teacher.create!(name: "Professora Memória 2", username: "profmemoria2", email: "memoria2@example.com", password: "secret123")
    post login_url, params: { role: "teacher", username: teacher.username, password: "secret123" }

    assert_no_difference("Exercise.count") do
      post exercises_url, params: {
        exercise: {
          title: "Jogo incompleto",
          exercise_type: "memory_game",
          object: {
            instructions: "Combine.",
            pair_type: "word_word",
            pairs: [ { left: { type: "word", content: "DOG" }, right: { type: "word", content: "CACHORRO" } } ]
          }.to_json
        }
      }
    end

    assert_response :unprocessable_entity
    assert_select ".errors li", text: "Adicione pelo menos dois pares."
  end

  test "student memory game hides pair IDs, persists the shuffled board, and awards XP only once" do
    _teacher, student, exercise, activity_exercise = create_student_memory_game(points: 11)
    post login_url, params: { role: "student", username: student.username, password: "secret123" }

    assert_difference("ExerciseAttempt.count") do
      post exercise_attempts_url, params: { exercise_attempt: { activity_exercise_id: activity_exercise.id } }
    end
    attempt = ExerciseAttempt.order(:id).last
    assert_redirected_to exercise_url(exercise, activity_exercise_id: activity_exercise.id, memory_game_attempt_id: attempt.id)
    original_deck = attempt.correct.fetch("deck")
    follow_redirect!
    assert_response :success
    assert_select "button.memory-card[data-memory-game-target='card']", count: 4
    assert_select "strong[data-memory-game-target='finalXp']"
    assert_not_includes response.body, "DOG"
    assert_not_includes response.body, "pair_id"

    first_pair = original_deck.group_by { |card| card.fetch("pair_id") }.values.first
    post memory_game_turn_exercise_attempt_url(attempt), params: { operation: "reveal", card_id: first_pair[0].fetch("id") }, as: :json
    assert_response :success
    revealed_content = first_pair[0].dig("element", "content")
    assert_equal revealed_content, JSON.parse(response.body).dig("data", "card", "content")
    get exercise_url(exercise, activity_exercise_id: activity_exercise.id, memory_game_attempt_id: attempt.id)
    assert_response :success
    assert_includes response.body, revealed_content
    assert_not_includes response.body, "pair_id"

    complete_memory_attempt(attempt, pair_count: 2)
    assert_equal 11, attempt.reload.score
    assert_equal true, attempt.correct.fetch("xp_award_claimed")
    assert_equal 4, attempt.correct.fetch("deck").length
    assert_equal original_deck, attempt.correct.fetch("deck")
    assert_equal 11, student.reload.student_stat.xp
    get exercise_url(exercise, activity_exercise_id: activity_exercise.id, memory_game_attempt_id: attempt.id)
    assert_response :success
    assert_includes response.body, "XP concedido nesta partida: 11"
    delete exercise_attempt_url(attempt)
    assert_redirected_to exercise_attempts_url
    assert_not attempt.reload.active?

    assert_difference("ExerciseAttempt.count") do
      post exercise_attempts_url, params: { exercise_attempt: { activity_exercise_id: activity_exercise.id } }
    end
    replay = ExerciseAttempt.order(:id).last
    complete_memory_attempt(replay, pair_count: 2)

    assert_equal 11, replay.reload.score
    assert_equal false, replay.correct.fetch("xp_award_claimed")
    assert_equal 11, student.reload.student_stat.xp
    get exercise_url(exercise, activity_exercise_id: activity_exercise.id, memory_game_attempt_id: replay.id)
    assert_response :success
    assert_includes response.body, "XP concedido nesta partida: 0"
  end

  test "student cannot reveal a third memory card during a pending comparison" do
    _teacher, student, _exercise, activity_exercise = create_student_memory_game(points: 8)
    post login_url, params: { role: "student", username: student.username, password: "secret123" }
    post exercise_attempts_url, params: { exercise_attempt: { activity_exercise_id: activity_exercise.id } }
    attempt = ExerciseAttempt.order(:id).last
    pairs = attempt.correct.fetch("deck").group_by { |card| card.fetch("pair_id") }.values

    [ pairs[0][0], pairs[1][0] ].each do |card|
      post memory_game_turn_exercise_attempt_url(attempt), params: { operation: "reveal", card_id: card.fetch("id") }, as: :json
      assert_response :success
    end
    post memory_game_turn_exercise_attempt_url(attempt), params: { operation: "reset" }, as: :json

    assert_response :unprocessable_entity
    assert_includes JSON.parse(response.body).dig("errors", 0, "message"), "Aguarde"
    assert_equal 1, attempt.reload.answer.fetch("attempts")
  end

  test "teacher uploads memory game images and students receive each image only when revealed" do
    teacher = Teacher.create!(name: "Professora Imagens", username: "profimagens", email: "imagens@example.com", password: "secret123")
    school_class = teacher.school_classes.create!(name: "Vocabulário", active: true)
    activity = school_class.activities.create!(title: "Animais", published: true)
    student = Student.create!(name: "Aluno Imagens", username: "alunoimagens", email: "alunoimagens@example.com", password: "secret123")
    school_class.class_students.create!(student:, active: true)
    post login_url, params: { role: "teacher", username: teacher.username, password: "secret123" }
    png_data = Base64.decode64("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jM2kAAAAASUVORK5CYII=")

    uploads = {}
    Tempfile.create([ "dog", ".png" ]) do |file|
      file.binmode
      file.write(png_data)
      file.rewind
      uploads["pair-one-right"] = Rack::Test::UploadedFile.new(file.path, "image/png", true, original_filename: "dog.png")
      Tempfile.create([ "cat", ".png" ]) do |second_file|
        second_file.binmode
        second_file.write(png_data)
        second_file.rewind
        uploads["pair-two-right"] = Rack::Test::UploadedFile.new(second_file.path, "image/png", true, original_filename: "cat.png")
        post exercises_url, params: {
          exercise: {
            title: "Animals",
            exercise_type: "memory_game",
            object: {
              instructions: "Combine cada palavra com a imagem.",
              pair_type: "word_image",
              pairs: [
                { left: { type: "word", content: "DOG" }, right: { type: "image", upload_key: "pair-one-right" } },
                { left: { type: "word", content: "CAT" }, right: { type: "image", upload_key: "pair-two-right" } }
              ]
            }.to_json,
            memory_images: uploads
          }
        }
      end
    end

    assert_response :redirect, response.body[/<ul>(.*?)<\/ul>/m, 1]
    exercise = Exercise.order(:id).last
    assert_redirected_to exercise_url(exercise)
    assert_equal 2, exercise.memory_images_attachments.count
    assert exercise.object.fetch("pairs").all? { |pair| pair.dig("right", "blob_id").present? }
    follow_redirect!
    assert_response :success
    assert_select ".memory-board-preview img", count: 2

    activity_exercise = activity.activity_exercises.create!(exercise:, position: 1, points: 9)
    delete logout_url
    post login_url, params: { role: "student", username: student.username, password: "secret123" }
    post exercise_attempts_url, params: { exercise_attempt: { activity_exercise_id: activity_exercise.id } }
    attempt = ExerciseAttempt.order(:id).last
    image_card = attempt.correct.fetch("deck").find { |card| card.dig("element", "type") == "image" }

    get exercise_url(exercise, activity_exercise_id: activity_exercise.id, memory_game_attempt_id: attempt.id)
    assert_response :success
    assert_not_includes response.body, "active_storage/blobs/redirect"
    post memory_game_turn_exercise_attempt_url(attempt), params: { operation: "reveal", card_id: image_card.fetch("id") }, as: :json

    revealed_card = JSON.parse(response.body).dig("data", "card")
    assert_response :success
    assert_equal "image", revealed_card.fetch("type")
    assert_not revealed_card.key?("blob_id")
    assert_not revealed_card.key?("pair_id")
    get revealed_card.fetch("url")
    assert_response :redirect
    follow_redirect!
    assert_response :success
    assert_equal "image/png", response.media_type
    assert_equal png_data, response.body
  end

  test "teacher previews a crossword without saving and persists the generated layout on create" do
    teacher = Teacher.create!(name: "Professora Crossword", username: "profcross", email: "cross@example.com", password: "secret123")
    post login_url, params: { role: "teacher", username: teacher.username, password: "secret123" }
    words = [ { word: "APPLE", clue: "A red fruit" }, { word: "PEAR", clue: "Another fruit" }, { word: "SCHOOL", clue: "A place to learn" } ]

    assert_no_difference("Exercise.count") do
      post crossword_preview_exercises_url, params: { instructions: "Complete the crossword", words:, seed: 17 }, as: :json
    end

    assert_response :success
    preview = JSON.parse(response.body).dig("data", "object")
    assert_equal %w[APPLE PEAR SCHOOL], preview.fetch("words").map { |entry| entry.fetch("normalized") }.sort
    assert_equal 17, preview.fetch("layout_seed")

    assert_difference("Exercise.count") do
      post exercises_url, params: {
        exercise: {
          title: "Crossword test",
          exercise_type: "crossword",
          object: { instructions: "Complete the crossword", words:, layout_seed: 17, grid: { cells: [ [ "TAMPERED" ] ] } }.to_json
        }
      }
    end

    exercise = Exercise.order(:id).last
    assert_redirected_to exercise_url(exercise)
    assert_equal preview, exercise.object
    assert_equal 3, exercise.object.fetch("words").length
    assert_equal exercise.object.fetch("grid").fetch("rows"), exercise.object.fetch("grid").fetch("cells").length
  end

  test "crossword preview reports words that cannot fit within the grid limit" do
    teacher = Teacher.create!(name: "Professora Crossword 2", username: "profcross2", email: "cross2@example.com", password: "secret123")
    post login_url, params: { role: "teacher", username: teacher.username, password: "secret123" }
    long_word = "A" * (Exercises::CrosswordBuilder::MAX_GRID_SIZE + 1)

    post crossword_preview_exercises_url, params: {
      instructions: "Complete the crossword",
      words: [ { word: long_word, clue: "Too long" }, { word: "DOG", clue: "Animal" } ],
      seed: 5
    }, as: :json

    assert_response :unprocessable_entity
    assert_includes JSON.parse(response.body).fetch("unplaced_words"), long_word
  end

  test "server does not persist a crossword with words that cannot be positioned" do
    teacher = Teacher.create!(name: "Professora Crossword inválido", username: "profcrossinvalid", email: "crossinvalid@example.com", password: "secret123")
    post login_url, params: { role: "teacher", username: teacher.username, password: "secret123" }
    long_word = "A" * (Exercises::CrosswordBuilder::MAX_GRID_SIZE + 1)

    assert_no_difference("Exercise.count") do
      post exercises_url, params: {
        exercise: {
          title: "Grade inválida",
          exercise_type: "crossword",
          object: { instructions: "Complete", words: [ { word: long_word, clue: "Too long" }, { word: "DOG", clue: "Animal" } ], layout_seed: 5 }.to_json
        }
      }
    end

    assert_response :unprocessable_entity
    assert_select ".errors li", text: /Não foi possível posicionar/
  end

  test "student sees a crossword mask and clues without answer words" do
    _teacher, student, exercise, activity_exercise = create_student_crossword(points: 10)
    stored_layout = exercise.object.deep_dup
    post login_url, params: { role: "student", username: student.username, password: "secret123" }

    get exercise_url(exercise, activity_exercise_id: activity_exercise.id)

    assert_response :success
    assert_select "table.crossword-answer-grid"
    assert_select "input[data-crossword-player-target='cell']"
    assert_select "h2", text: "Horizontal"
    assert_select "h2", text: "Vertical"
    assert_includes response.body, "A red fruit"
    assert_not_includes response.body, "APPLE"
    assert_not_includes response.body, "PEAR"
    assert_not_includes response.body, "normalized"
    get exercise_url(exercise, activity_exercise_id: activity_exercise.id)
    assert_response :success
    assert_equal stored_layout, exercise.reload.object
  end

  test "crossword attempts use server scoring and award proportional XP" do
    _teacher, student, exercise, activity_exercise = create_student_crossword(points: 11)
    post login_url, params: { role: "student", username: student.username, password: "secret123" }
    entry = exercise.object.fetch("words").find { |word| word.fetch("id") == "word-1" }
    cells = {}
    entry.fetch("normalized").chars.each_with_index do |letter, index|
      row = entry.fetch("row") + (entry.fetch("direction") == "down" ? index : 0)
      column = entry.fetch("column") + (entry.fetch("direction") == "across" ? index : 0)
      cells["#{row}-#{column}"] = letter
    end

    assert_difference("ExerciseAttempt.count") do
      post exercise_attempts_url, params: {
        exercise_attempt: {
          activity_exercise_id: activity_exercise.id,
          answer: { cells: }.to_json,
          score: 11_000,
          correct: { words: [ "FORGED ANSWER KEY" ] }.to_json
        }
      }
    end

    attempt = ExerciseAttempt.order(:id).last
    assert_redirected_to exercise_attempt_url(attempt)
    assert_equal 5, attempt.score
    assert_equal student.id, attempt.student_id
    assert_equal 1, attempt.correct.fetch("statuses").values.count(true)
    assert_equal true, attempt.correct.fetch("xp_award_claimed")
    assert_equal 5, student.reload.student_stat.xp

    get exercise_attempt_url(attempt)
    assert_response :success
    assert_includes response.body, "1 de 2 palavras corretas"
    assert_includes response.body, "XP concedido nesta tentativa: 5"
    assert_not_includes response.body, "APPLE"
    assert_not_includes response.body, "PEAR"
    get edit_exercise_attempt_url(attempt)
    assert_redirected_to root_url
  end

  test "crossword retries keep history but award XP only once, including after soft delete" do
    _teacher, student, exercise, activity_exercise = create_student_crossword(points: 9)
    post login_url, params: { role: "student", username: student.username, password: "secret123" }
    layout = exercise.object.deep_stringify_keys
    cells = layout.fetch("grid").fetch("cells").each_with_index.flat_map do |row, row_index|
      row.each_with_index.filter_map do |letter, column_index|
        [ "#{row_index}-#{column_index}", letter ] if letter.present?
      end
    end.to_h
    submission_params = { exercise_attempt: { activity_exercise_id: activity_exercise.id, answer: { cells: }.to_json } }

    post exercise_attempts_url, params: submission_params
    assert_match %r{/exercise_attempts/\d+\z}, URI(response.location).path, flash[:alert]
    first_attempt = ExerciseAttempt.order(:id).last
    assert_equal 9, first_attempt.score
    assert_equal true, first_attempt.correct.fetch("xp_award_claimed")
    assert_equal 9, student.reload.student_stat.xp

    first_attempt.update!(active: false)
    post exercise_attempts_url, params: submission_params
    second_attempt = ExerciseAttempt.order(:id).last

    assert_equal 2, ExerciseAttempt.where(student:, activity_exercise:).count
    assert_equal 9, second_attempt.score
    assert_equal false, second_attempt.correct.fetch("xp_award_claimed")
    assert_equal 9, student.reload.student_stat.xp

    get exercise_attempt_url(second_attempt)
    assert_response :success
    assert_includes response.body, "XP concedido nesta tentativa: 0"
    assert_not_includes response.body, "APPLE"
    assert_not_includes response.body, "PEAR"
  end

  test "student cannot submit a crossword through an inactive exercise link" do
    _teacher, student, _exercise, activity_exercise = create_student_crossword(points: 9)
    activity_exercise.update!(active: false)
    post login_url, params: { role: "student", username: student.username, password: "secret123" }

    assert_no_difference("ExerciseAttempt.count") do
      post exercise_attempts_url, params: {
        exercise_attempt: {
          activity_exercise_id: activity_exercise.id,
          answer: { cells: {} }.to_json,
          score: 9,
          correct: { forged: true }.to_json
        }
      }
    end

    assert_redirected_to root_url
  end

  test "teacher sees active students in the class" do
    teacher = Teacher.create!(name: "Professora 3", username: "prof3", email: "prof3@example.com", password: "secret123")
    school_class = teacher.school_classes.create!(name: "Ciências")
    active_student = Student.create!(name: "Aluno ativo", username: "ativo", email: "ativo@example.com", password: "secret123")
    inactive_student = Student.create!(name: "Aluno saiu", username: "saiu", email: "saiu@example.com", password: "secret123")
    school_class.class_students.create!(student: active_student, active: true)
    school_class.class_students.create!(student: inactive_student, active: false)
    post login_url, params: { role: "teacher", username: teacher.username, password: "secret123" }

    get school_class_url(school_class)

    assert_select "li", text: /Aluno ativo/
    assert_select "li", text: /Aluno saiu/, count: 0
  end

  private

  def create_student_crossword(points:)
    teacher = Teacher.create!(name: "Professora Crossword #{points}", username: "crossowner#{points}", email: "crossowner#{points}@example.com", password: "secret123")
    school_class = teacher.school_classes.create!(name: "Ciências", active: true)
    activity = school_class.activities.create!(title: "Animais", published: true)
    student = Student.create!(name: "Aluno Crossword #{points}", username: "crossstudent#{points}", email: "crossstudent#{points}@example.com", password: "secret123")
    school_class.class_students.create!(student:, active: true)
    generated = Exercises::CrosswordBuilder.call(
      instructions: "Complete a cruzadinha",
      seed: 17,
      words: [
        { word: "APPLE", clue: "A red fruit" },
        { word: "PEAR", clue: "Another fruit" }
      ]
    )
    exercise = teacher.exercises.create!(title: "Animais australianos", exercise_type: :crossword, object: generated.object)
    activity_exercise = activity.activity_exercises.create!(exercise:, position: 1, points:)
    [ teacher, student, exercise, activity_exercise ]
  end

  def create_student_memory_game(points:)
    teacher = Teacher.create!(name: "Professora Memória #{points}", username: "memoryowner#{points}", email: "memoryowner#{points}@example.com", password: "secret123")
    school_class = teacher.school_classes.create!(name: "Idiomas", active: true)
    activity = school_class.activities.create!(title: "Vocabulário", published: true)
    student = Student.create!(name: "Aluno Memória #{points}", username: "memorystudent#{points}", email: "memorystudent#{points}@example.com", password: "secret123")
    school_class.class_students.create!(student:, active: true)
    game = Exercises::MemoryGameBuilder.call(object: {
      instructions: "Combine os pares.",
      pair_type: "word_word",
      pairs: [
        { left: { type: "word", content: "DOG" }, right: { type: "word", content: "CACHORRO" } },
        { left: { type: "word", content: "CAT" }, right: { type: "word", content: "GATO" } }
      ]
    })
    exercise = teacher.exercises.create!(title: "Animais", exercise_type: :memory_game, object: game.object)
    activity_exercise = activity.activity_exercises.create!(exercise:, position: 1, points:)
    [ teacher, student, exercise, activity_exercise ]
  end

  def complete_memory_attempt(attempt, pair_count:)
    answer = attempt.reload.answer.to_h
    matched_card_ids = Array(answer["matched_card_ids"])
    selected_card_id = answer["selected_card_id"]
    attempt.correct.fetch("deck").group_by { |card| card.fetch("pair_id") }.values.first(pair_count).each do |cards|
      cards.each do |card|
        next if matched_card_ids.include?(card.fetch("id")) || selected_card_id == card.fetch("id")

        post memory_game_turn_exercise_attempt_url(attempt), params: { operation: "reveal", card_id: card.fetch("id") }, as: :json
        assert_response :success
      end
      assert_equal true, attempt.reload.answer.to_h["matched_card_ids"].include?(cards[0].fetch("id"))
    end
  end
end
