require "test_helper"

class StudentOrderingAttemptTest < ActionDispatch::IntegrationTest
  test "student orders items and receives proportional score and the expected sequence" do
    _teacher, student, exercise, activity_exercise = create_student_ordering(points: 10)
    post login_url, params: { role: "student", username: student.username, password: "secret123" }

    get exercise_url(exercise, activity_exercise_id: activity_exercise.id)

    assert_response :success
    assert_select "form[data-controller='ordering-player'][data-ordering-player-expected-ids-value]"
    assert_select "ol.ordering-player-list > li[data-ordering-player-target='item']", count: 4
    assert_select "input[name='exercise_attempt[ordered_ids][]']", count: 4
    assert_select "button[aria-label='Mover item para cima']", count: 4
    assert_not_includes response.body, "correct_order"

    assert_difference("ExerciseAttempt.count") do
      post exercise_attempts_url, params: {
        exercise_attempt: {
          activity_exercise_id: activity_exercise.id,
          ordered_ids: %w[item-1 item-3 item-2 item-4],
          correct: { positions: [] },
          score: 99
        }
      }
    end

    attempt = ExerciseAttempt.order(:id).last
    assert_redirected_to exercise_attempt_url(attempt)
    assert_equal 5, attempt.score
    assert_equal 5, student.reload.student_stat.xp
    assert_equal %w[item-1 item-3 item-2 item-4], attempt.answer.fetch("ordered_ids")
    assert_equal [ true, false, false, true ], attempt.correct.fetch("positions").pluck("correct")

    follow_redirect!
    assert_response :success
    assert_select ".attempt-result-count strong", text: "2 de 4 itens corretos"
    assert_select "li.attempt-question-card", count: 4
    assert_select ".result-status--incorrect", count: 2
    assert_select "ol.ordering-feedback-list li", count: 4
    assert_includes response.body, "Sequência correta:"
    assert_select "a", text: "Tentar novamente"

    patch exercise_attempt_url(attempt), params: { exercise_attempt: { correct: { positions: [] }, score: 99 } }
    assert_redirected_to root_url
    assert_equal 5, attempt.reload.score
    assert_equal [ true, false, false, true ], attempt.correct.fetch("positions").pluck("correct")
  end

  test "multiple sentence player renders separate ID-based lists with submission initially disabled" do
    exercise = Struct.new(:title).new("Frases embaralhadas")
    activity_exercise = Struct.new(:id) { def persisted? = false }.new(17)
    sentences = [
      { "id" => "sentence-one", "items" => [ { "id" => "word-one-a", "label" => "Olá," }, { "id" => "word-one-b", "label" => "Olá," } ] },
      { "id" => "sentence-two", "items" => [ { "id" => "word-two-a", "label" => "mundo!" }, { "id" => "word-two-b", "label" => "mundo?" } ] }
    ]

    html = ApplicationController.renderer.render(
      partial: "exercises/ordering_multiple_player",
      locals: { exercise:, activity_exercise:, instructions: "Organize cada frase.", sentences: }
    )
    document = Nokogiri::HTML.fragment(html)
    sentence_nodes = document.css("[data-ordering-multiple-player-target='sentence']")

    assert_equal 2, sentence_nodes.length
    assert_equal [ "word-one-a", "word-one-b" ], sentence_nodes[0].css("[data-item-id]").map { |item| item["data-item-id"] }
    assert_equal [ "word-two-a", "word-two-b" ], sentence_nodes[1].css("[data-item-id]").map { |item| item["data-item-id"] }
    assert_equal [ "Olá,", "Olá," ], sentence_nodes[0].css(".ordering-player-label").map(&:text)
    assert_equal 1, document.css("form[action='/exercise_attempts']").length
    assert_equal "17", document.at_css("input[name='exercise_attempt[activity_exercise_id]']")["value"]
    assert_equal 1, document.css("button[type='submit'][disabled]").length
    assert_includes document.text, "O envio ainda não está disponível."
    assert_not_includes html, "correct_order"
  end

  test "multiple sentence submission validates completeness, grades positions, and persists the server snapshot" do
    _teacher, student, _exercise, activity_exercise = create_student_multiple_sentence_ordering(points: 100)
    sentences = [
      { "id" => "sentence-two", "ordered_ids" => %w[e h f g] },
      { "id" => "sentence-one", "ordered_ids" => %w[c b a d] }
    ]

    assert_difference("ExerciseAttempt.count") do
      @submission = Exercises::OrderingSubmission.call(activity_exercise:, student:, sentences:)
    end

    attempt = @submission.attempt
    assert_equal 62, attempt.score
    assert_equal %w[sentence-one sentence-two], attempt.answer.fetch("sentences").pluck("id")
    assert_equal [ true, true, true, true ], attempt.correct.fetch("sentences").first.fetch("positions").pluck("correct")
    assert_equal [ true, false, false, false ], attempt.correct.fetch("sentences").last.fetch("positions").pluck("correct")
    assert_equal 5, attempt.correct.fetch("positions_correct")
    assert_equal 8, attempt.correct.fetch("total_positions")
    assert_equal 100, attempt.correct.fetch("points_possible")
    assert_equal false, attempt.correct.fetch("correct")
    assert_equal 62, student.reload.student_stat.xp
  end

  test "student submits multiple sentences through the real route and first valid score stays official" do
    _teacher, student, _exercise, activity_exercise = create_student_multiple_sentence_ordering(points: 100)
    activity_exercise.activity.update!(published: true)

    outsider = Student.create!(
      name: "Aluno fora da turma",
      username: "phrases-outsider-#{SecureRandom.hex(6)}",
      email: "phrases-outsider-#{SecureRandom.hex(6)}@example.com",
      password: "secret123"
    )
    post login_url, params: { role: "student", username: outsider.username, password: "secret123" }
    get exercise_url(activity_exercise.exercise, activity_exercise_id: activity_exercise.id)
    assert_redirected_to root_url

    post login_url, params: { role: "student", username: student.username, password: "secret123" }

    get exercise_url(activity_exercise.exercise, activity_exercise_id: activity_exercise.id)

    assert_response :success
    assert_select "form[data-controller='ordering-multiple-player']"
    assert_select "input[name='exercise_attempt[sentences_json]']"
    assert_select "button[type='submit'][disabled]"
    assert_select "form input[name='exercise_attempt[ordered_ids][]']", count: 0

    partial_sentences = [
      { "id" => "sentence-two", "ordered_ids" => %w[e h f g] },
      { "id" => "sentence-one", "ordered_ids" => %w[c b a d] }
    ]
    attempts_before = ExerciseAttempt.count
    post exercise_attempts_url, params: {
      exercise_attempt: {
        activity_exercise_id: activity_exercise.id,
        sentences_json: partial_sentences.to_json,
        score: 1000,
        correct: { correct: true }
      }
    }
    assert_response :redirect
    assert_equal attempts_before + 1, ExerciseAttempt.count,
      "Expected a saved attempt; redirect=#{response.location.inspect}, flash=#{flash.to_hash.inspect}"

    first_attempt = ExerciseAttempt.order(:id).last
    assert_redirected_to exercise_attempt_url(first_attempt)
    assert_equal 62, first_attempt.score
    assert_equal partial_sentences.map { |sentence| sentence.fetch("id") }.sort, first_attempt.answer.fetch("sentences").map { |sentence| sentence.fetch("id") }.sort
    assert_equal 62, student.reload.student_stat.xp
    follow_redirect!
    assert_response :success
    assert_includes response.body, "Percentual proporcional"
    assert_includes response.body, "62.5%"
    assert_includes response.body, "Palavra enviada:"
    assert_equal first_attempt, ActivityResults.official_attempt(activity_exercise:, student:)

    perfect_sentences = [
      { "id" => "sentence-one", "ordered_ids" => %w[a b c d] },
      { "id" => "sentence-two", "ordered_ids" => %w[e f g h] }
    ]
    post exercise_attempts_url, params: {
      exercise_attempt: { activity_exercise_id: activity_exercise.id, sentences_json: perfect_sentences.to_json }
    }
    later_attempt = ExerciseAttempt.order(:id).last

    assert_equal 100, later_attempt.score
    assert_equal first_attempt, ActivityResults.official_attempt(activity_exercise:, student:)
    assert_equal 62, student.reload.student_stat.xp
  end

  test "multiple sentence submissions reject incomplete or forged structures before persistence" do
    _teacher, student, _exercise, activity_exercise = create_student_multiple_sentence_ordering(points: 100)
    complete = [
      { "id" => "sentence-one", "ordered_ids" => %w[a b c d] },
      { "id" => "sentence-two", "ordered_ids" => %w[e f g h] }
    ]
    invalid_responses = [
      nil,
      "not-an-array",
      complete.first(1),
      [ complete.first, complete.first ],
      [ complete.first.merge("id" => "missing-sentence"), complete.last ],
      [ complete.first.merge("id" => nil), complete.last ],
      [ complete.first, complete.last.merge("id" => "sentence-one") ],
      [ complete.first.merge("ordered_ids" => "a b c d"), complete.last ],
      [ complete.first.merge("extra" => "field"), complete.last ],
      [ complete.first.merge("ordered_ids" => %w[a b c]), complete.last ],
      [ complete.first.merge("ordered_ids" => %w[a b c c]), complete.last ],
      [ complete.first.merge("ordered_ids" => %w[e b c d]), complete.last ],
      [ complete.first.merge("ordered_ids" => %w[a b c unknown]), complete.last ]
    ]

    invalid_responses.each do |sentences|
      assert_no_difference("ExerciseAttempt.count") do
        assert_raises(Exercises::AttemptValidity::BlankResponse) do
          Exercises::OrderingSubmission.call(activity_exercise:, student:, sentences:)
        end
      end
    end
    assert_not StudentStat.exists?(student_id: student.id)
  end

  test "multiple sentence student payload keeps sentence and word IDs without correct orders" do
    object = {
      "sentences" => [
        { "id" => "sentence-one", "items" => [ { "id" => "word-one-a", "label" => "Olá," }, { "id" => "word-one-b", "label" => "Olá," } ], "correct_order" => %w[word-one-a word-one-b] },
        { "id" => "sentence-two", "items" => [ { "id" => "word-two-a", "label" => "mundo!" }, { "id" => "word-two-b", "label" => "mundo?" } ], "correct_order" => %w[word-two-a word-two-b] }
      ]
    }

    payload = ExercisesController.new.send(:ordering_sentences_for_student, object)

    assert_equal %w[sentence-one sentence-two], payload.pluck("id").sort
    assert_equal %w[word-one-a word-one-b], payload.first.fetch("items").pluck("id").sort
    assert_equal %w[word-two-a word-two-b], payload.last.fetch("items").pluck("id").sort
    assert payload.all? { |sentence| sentence.keys.sort == %w[id items] }
    assert_equal [ "Olá,", "Olá," ], payload.first.fetch("items").pluck("label")
  end

  test "retry preserves history and awards XP only once even after soft delete" do
    _teacher, student, _exercise, activity_exercise = create_student_ordering(points: 10)
    post login_url, params: { role: "student", username: student.username, password: "secret123" }
    ordered_ids = %w[item-1 item-2 item-3 item-4]

    post exercise_attempts_url, params: { exercise_attempt: { activity_exercise_id: activity_exercise.id, ordered_ids: } }
    first_attempt = ExerciseAttempt.order(:id).last
    assert_equal 10, first_attempt.score
    assert_equal 10, student.reload.student_stat.xp

    first_attempt.update!(active: false)
    post exercise_attempts_url, params: { exercise_attempt: { activity_exercise_id: activity_exercise.id, ordered_ids: } }
    second_attempt = ExerciseAttempt.order(:id).last

    assert_equal 2, ExerciseAttempt.where(student:, activity_exercise:).count
    assert_equal 10, second_attempt.score
    assert_equal false, second_attempt.correct.fetch("xp_award_claimed")
    assert_equal 10, student.reload.student_stat.xp
  end

  test "server rejects missing duplicate and unknown ordering IDs" do
    _teacher, student, exercise, activity_exercise = create_student_ordering(points: 10)
    post login_url, params: { role: "student", username: student.username, password: "secret123" }

    [ %w[item-1 item-2 item-3], %w[item-1 item-1 item-3 item-4], %w[item-1 item-2 item-3 unknown] ].each do |ordered_ids|
      assert_no_difference("ExerciseAttempt.count") do
        post exercise_attempts_url, params: {
          exercise_attempt: { activity_exercise_id: activity_exercise.id, ordered_ids: }
        }
      end
      assert_response :unprocessable_entity
      assert_includes response.body, "Preencha todas as respostas obrigatórias antes de enviar a atividade."
    end

    assert_not StudentStat.exists?(student_id: student.id)
    assert_nil ActivityResults.official_attempt(activity_exercise:, student:)
  end

  test "student cannot submit ordering from an unrelated class" do
    _teacher, _enrolled_student, _exercise, activity_exercise = create_student_ordering(points: 10)
    student = Student.create!(name: "Outro aluno", username: "otherordering", email: "otherordering@example.com", password: "secret123")
    post login_url, params: { role: "student", username: student.username, password: "secret123" }

    assert_no_difference("ExerciseAttempt.count") do
      post exercise_attempts_url, params: {
        exercise_attempt: { activity_exercise_id: activity_exercise.id, ordered_ids: %w[item-1 item-2] }
      }
    end

    assert_redirected_to root_url
  end

  private

  def create_student_multiple_sentence_ordering(points:)
    teacher = Teacher.create!(name: "Professor Frases", username: "phrases-#{SecureRandom.hex(6)}", email: "phrases-#{SecureRandom.hex(6)}@example.com", password: "secret123")
    school_class = teacher.school_classes.create!(name: "Frases", active: true)
    activity = school_class.activities.create!(title: "Aula de frases")
    student = Student.create!(name: "Aluno Frases", username: "phrases-student-#{SecureRandom.hex(6)}", email: "phrases-student-#{SecureRandom.hex(6)}@example.com", password: "secret123")
    school_class.class_students.create!(student:, active: true)
    exercise = teacher.exercises.create!(
      title: "Frases embaralhadas",
      exercise_type: :ordering,
      object: {
        "format" => "multiple_sentences",
        "instructions" => "Organize as frases.",
        "sentences" => [
          { "id" => "sentence-one", "items" => [ { "id" => "a", "label" => "I" }, { "id" => "b", "label" => "think" }, { "id" => "c", "label" => "I" }, { "id" => "d", "label" => "can." } ], "correct_order" => %w[a b c d] },
          { "id" => "sentence-two", "items" => [ { "id" => "e", "label" => "We" }, { "id" => "f", "label" => "will" }, { "id" => "g", "label" => "go" }, { "id" => "h", "label" => "now." } ], "correct_order" => %w[e f g h] }
        ]
      }
    )
    activity_exercise = activity.activity_exercises.create!(exercise:, position: 1, points:)
    [ teacher, student, exercise, activity_exercise ]
  end

  def create_student_ordering(points:)
    teacher = Teacher.create!(name: "Professor Ordenação", username: "orderingteacher", email: "orderingteacher@example.com", password: "secret123")
    school_class = teacher.school_classes.create!(name: "Ciências", active: true)
    activity = school_class.activities.create!(title: "Ordem do universo", published: true)
    student = Student.create!(name: "Aluno Ordenação", username: "orderingstudent", email: "orderingstudent@example.com", password: "secret123")
    school_class.class_students.create!(student:, active: true)
    exercise = teacher.exercises.create!(
      title: "Organize os conceitos",
      exercise_type: :ordering,
      object: {
        "instructions" => "Organize do menor para o maior.",
        "item_type" => "words",
        "items" => [
          { "id" => "item-1", "label" => "Estrela" },
          { "id" => "item-2", "label" => "Planeta" },
          { "id" => "item-3", "label" => "Sistema solar" },
          { "id" => "item-4", "label" => "Galáxia" }
        ],
        "correct_order" => %w[item-1 item-2 item-3 item-4]
      }
    )
    activity_exercise = activity.activity_exercises.create!(exercise:, position: 1, points:)
    [ teacher, student, exercise, activity_exercise ]
  end
end
