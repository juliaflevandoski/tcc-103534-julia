require "test_helper"

class MemoryGameAccessibilityTest < ActionDispatch::IntegrationTest
  setup do
    suffix = SecureRandom.hex(6)
    @teacher = Teacher.create!(name: "Professor", username: "memory-teacher-#{suffix}", email: "teacher-#{suffix}@example.com", password: "secret123")
    @student = Student.create!(name: "Aluno", username: "memory-student-#{suffix}", email: "student-#{suffix}@example.com", password: "secret123")
    school_class = @teacher.school_classes.create!(name: "Turma acessível", active: true)
    school_class.class_students.create!(student: @student, active: true)
    @activity = school_class.activities.create!(title: "Aula acessível", published: true)
  end

  test "hidden word cards do not expose content and found cards retain their word" do
    exercise, link = create_memory_game(
      "word_word",
      [
        [ { type: "word", content: "Cachorro" }, { type: "word", content: "Dog" } ],
        [ { type: "word", content: "Gato" }, { type: "word", content: "Cat" } ]
      ]
    )
    attempt = start_game(link)
    get exercise_url(exercise, activity_exercise_id: link.id, memory_game_attempt_id: attempt.id)

    assert_select "button.memory-card[aria-label='Carta virada para baixo']", count: 4
    assert_not_includes response.body, "Cachorro"

    cards = attempt.correct.fetch("deck").group_by { |card| card.fetch("pair_id") }.values.first
    reveal(attempt, cards.first)
    get exercise_url(exercise, activity_exercise_id: link.id, memory_game_attempt_id: attempt.id)
    assert_select "button.memory-card[aria-label='Carta revelada: #{cards.first.dig("element", "content")}']", count: 1

    reveal(attempt, cards.last)
    get exercise_url(exercise, activity_exercise_id: link.id, memory_game_attempt_id: attempt.id)
    cards.each do |card|
      assert_select "button.memory-card.is-found[aria-label='Par encontrado: #{card.dig("element", "content")}']", count: 1
    end
    assert_equal 0, attempt.reload.score
  end

  test "image cards use available descriptions and otherwise keep a generic name" do
    image_data = Base64.decode64("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jM2kAAAAASUVORK5CYII=")
    exercise = @teacher.exercises.create!(
      title: "Imagens",
      exercise_type: :memory_game,
      object: {
        "instructions" => "Encontre os pares.",
        "pair_type" => "word_word",
        "pairs" => [
          { "id" => "pair-1", "left" => { "type" => "word", "content" => "A" }, "right" => { "type" => "word", "content" => "B" } },
          { "id" => "pair-2", "left" => { "type" => "word", "content" => "C" }, "right" => { "type" => "word", "content" => "D" } }
        ]
      }
    )
    blob_ids = 4.times.map do |index|
      Tempfile.create([ "memory-accessibility-#{index}", ".png" ]) do |file|
        file.binmode
        file.write(image_data)
        file.rewind
        exercise.memory_images.attach(io: file, filename: "image-#{index}.png", content_type: "image/png")
      end
      exercise.memory_images_attachments.reload.last.blob_id
    end
    exercise.update!(
      object: {
        "instructions" => "Encontre os pares.",
        "pair_type" => "image_image",
        "pairs" => [
          { "id" => "pair-1", "left" => { "type" => "image", "blob_id" => blob_ids[0] }, "right" => { "type" => "image", "blob_id" => blob_ids[1] } },
          { "id" => "pair-2", "left" => { "type" => "image", "blob_id" => blob_ids[2] }, "right" => { "type" => "image", "blob_id" => blob_ids[3] } }
        ]
      }
    )
    link = @activity.activity_exercises.create!(exercise:, position: 1, points: 8)
    attempt = start_game(link)
    image_card = attempt.correct.fetch("deck").find { |card| card.dig("element", "type") == "image" }
    correct = attempt.correct.deep_dup
    image_card_in_deck = correct.fetch("deck").find { |card| card.fetch("id") == image_card.fetch("id") }
    image_card_in_deck.fetch("element")["ai_description"] = "Um cachorro marrom"
    attempt.update_column(:correct, correct)

    post memory_game_turn_exercise_attempt_url(attempt), params: { operation: "reveal", card_id: image_card.fetch("id") }, as: :json

    assert_response :success
    assert_equal "Um cachorro marrom", JSON.parse(response.body).dig("data", "card", "description")
    get exercise_url(exercise, activity_exercise_id: link.id, memory_game_attempt_id: attempt.id)
    assert_select "button.memory-card[aria-label='Imagem revelada: Um cachorro marrom'] img[alt='Um cachorro marrom']", count: 1

    no_description = attempt.correct.fetch("deck").find do |card|
      card.dig("element", "type") == "image" &&
        card.fetch("id") != image_card.fetch("id") &&
        card.fetch("pair_id") != image_card.fetch("pair_id")
    end
    post memory_game_turn_exercise_attempt_url(attempt), params: { operation: "reveal", card_id: no_description.fetch("id") }, as: :json

    assert_response :success
    assert_nil JSON.parse(response.body).dig("data", "card", "description")
    get exercise_url(exercise, activity_exercise_id: link.id, memory_game_attempt_id: attempt.id)
    image_labels = css_select("button.memory-card img").map { |image| image.parent["aria-label"] }
    assert_equal [ "Carta revelada: imagem", "Imagem revelada: Um cachorro marrom" ].sort, image_labels.sort
    assert_select "button.memory-card img[alt='']", count: 1
    assert_select "button.memory-card img[alt='Um cachorro marrom']", count: 1
  end

  private

  def create_memory_game(pair_type, pairs)
    exercise = @teacher.exercises.create!(
      title: "Palavras",
      exercise_type: :memory_game,
      object: { "instructions" => "Encontre os pares.", "pair_type" => pair_type, "pairs" => pairs.map.with_index { |(left, right), index| { "id" => "pair-#{index + 1}", "left" => left, "right" => right } } }
    )
    link = @activity.activity_exercises.create!(exercise:, position: 1, points: 8)
    [ exercise, link ]
  end

  def start_game(link)
    post login_url, params: { role: "student", username: @student.username, password: "secret123" }
    post exercise_attempts_url, params: { exercise_attempt: { activity_exercise_id: link.id } }
    ExerciseAttempt.order(:id).last
  end

  def reveal(attempt, card)
    post memory_game_turn_exercise_attempt_url(attempt), params: { operation: "reveal", card_id: card.fetch("id") }, as: :json
    assert_response :success
  end
end
