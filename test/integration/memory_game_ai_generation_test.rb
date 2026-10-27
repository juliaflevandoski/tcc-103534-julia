require "test_helper"
require "base64"
require "tempfile"

class MemoryGameAiGenerationTest < ActionDispatch::IntegrationTest
  parallelize(workers: 1)

  class FakeClient
    attr_reader :calls
    attr_accessor :response

    def initialize(response)
      @response = response
      @calls = []
    end

    def call(**arguments)
      @calls << arguments
      response
    end
  end

  ApiResult = Struct.new(:data, :error_code, :message, keyword_init: true) do
    def success?
      error_code.nil?
    end
  end

  setup do
    @api_response = ApiResult.new(data: {
      "instructions" => "Combine cada palavra com sua tradução.",
      "pairs" => [
        { "left_text" => "DOG", "right_text" => "CÃO" },
        { "left_text" => "CAT", "right_text" => "GATO" }
      ]
    })
    @client = FakeClient.new(@api_response)
    @generator = Exercises::MemoryGameGenerator.new(client: @client)
    @original_generator = ExercisesController.memory_game_generator_service
    ExercisesController.memory_game_generator_service = @generator
    @teacher = Teacher.create!(
      name: "Professor Memória IA",
      username: "memory-ai-#{SecureRandom.hex(6)}",
      email: "memory-ai-#{SecureRandom.hex(6)}@example.com",
      password: "secret123"
    )
    post login_url, params: { role: "teacher", username: @teacher.username, password: "secret123" }
  end

  teardown do
    ExercisesController.memory_game_generator_service = @original_generator
  end

  test "teacher receives builder-generated word pairs without saving and can edit and save them" do
    assert_no_difference("Exercise.count") do
      post generate_memory_game_exercises_url, params: valid_params, as: :json
    end

    assert_response :success
    draft = response.parsed_body.dig("data", "draft")
    assert_equal "word_word", draft.fetch("pair_type")
    assert_equal 2, draft.fetch("pairs").length
    assert draft.fetch("pairs").all? { |pair| pair.keys.sort == %w[id left right] && pair.fetch("id").present? }
    assert Exercises::ExerciseContentValidator.call(exercise_type: "memory_game", object: draft).success?

    draft["pairs"].first["right"]["content"] = "CÃO (revisado)"
    assert_difference("Exercise.count") do
      post exercises_url, params: { exercise: { title: "Pares", exercise_type: "memory_game", object: draft.to_json } }
    end

    saved = @teacher.exercises.order(:id).last
    assert_redirected_to exercise_url(saved)
    assert_equal "CÃO (revisado)", saved.object.fetch("pairs").first.dig("right", "content")
    assert saved.object.fetch("pairs").all? { |pair| pair.fetch("id").present? }
  end

  test "image association drafts contain descriptions only and require manual uploads to save" do
    @client.response = ApiResult.new(data: {
      "instructions" => "Combine a palavra com uma imagem adicionada pelo professor.",
      "pairs" => [
        { "word" => "DOG", "image_description" => "A small brown dog" },
        { "word" => "CAT", "image_description" => "A gray cat" }
      ]
    })
    assert_no_difference("Exercise.count") do
      post generate_memory_game_exercises_url, params: valid_params.merge(pair_type: "word_image"), as: :json
    end

    assert_response :success
    draft = response.parsed_body.dig("data", "draft")
    image_elements = draft.fetch("pairs").map { |pair| pair.fetch("right") }
    assert_equal [ "A small brown dog", "A gray cat" ], image_elements.pluck("ai_description")
    image_elements.each do |element|
      assert_equal %w[ai_description type], element.keys.sort
      assert_not element.key?("blob_id")
      assert_not element.key?("url")
      assert_not element.key?("upload_key")
    end
    assert_not Exercises::MemoryGameBuilder.call(object: draft).success?
    assert_equal 1, @client.calls.length
  end

  test "AI image descriptions are saved only after the teacher manually uploads real images" do
    @client.response = ApiResult.new(data: {
      "instructions" => "Combine as palavras com as imagens adicionadas pelo professor.",
      "pairs" => [
        { "word" => "DOG", "image_description" => "A small brown dog" },
        { "word" => "CAT", "image_description" => "A gray cat" }
      ]
    })
    assert_no_difference("Exercise.count") do
      post generate_memory_game_exercises_url, params: valid_params.merge(pair_type: "word_image"), as: :json
    end
    assert_response :success
    generated_pairs = response.parsed_body.dig("data", "draft", "pairs")
    assert generated_pairs.all? { |pair| pair.dig("right", "ai_description").present? }
    png_data = Base64.decode64("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jM2kAAAAASUVORK5CYII=")
    uploads = {}
    object = {
      "instructions" => "Combine as palavras com as imagens adicionadas pelo professor.",
      "pair_type" => "word_image",
      "pairs" => generated_pairs.each_with_index.map do |pair, index|
        {
          "left" => pair.fetch("left"),
          "right" => { "type" => "image", "upload_key" => "manual-image-#{index + 1}" }
        }
      end
    }

    Tempfile.create([ "ai-memory-image-one", ".png" ]) do |first_file|
      first_file.binmode
      first_file.write(png_data)
      first_file.rewind
      uploads["manual-image-1"] = Rack::Test::UploadedFile.new(first_file.path, "image/png", true, original_filename: "dog.png")
      Tempfile.create([ "ai-memory-image-two", ".png" ]) do |second_file|
        second_file.binmode
        second_file.write(png_data)
        second_file.rewind
        uploads["manual-image-2"] = Rack::Test::UploadedFile.new(second_file.path, "image/png", true, original_filename: "cat.png")

        assert_difference("Exercise.count") do
          post exercises_url, params: {
            exercise: { title: "Animais e imagens", exercise_type: "memory_game", object: object.to_json, memory_images: uploads }
          }
        end
      end
    end

    saved = @teacher.exercises.order(:id).last
    assert_redirected_to exercise_url(saved)
    assert_equal 2, saved.memory_images_attachments.count
    image_elements = saved.object.fetch("pairs").map { |pair| pair.fetch("right") }
    assert image_elements.all? { |element| element.fetch("blob_id").positive? }
    assert image_elements.none? { |element| element.key?("ai_description") || element.key?("upload_key") }
  end

  test "memory editor keeps the existing manual image upload controls" do
    get new_exercise_url
    assert_response :success
    assert_select "dialog[data-exercise-form-target='memoryGameAiModal']"
    assert_select "button[data-action='exercise-form#openMemoryGameAiModal']"
    assert_select "input[data-memory-image][accept='image/png,image/jpeg,image/webp']"
    assert_select "input[data-exercise-form-target='memoryAiTopic'][required]", count: 0
    assert_select "button[data-action='exercise-form#addMemoryPair']", text: "Adicionar par"
  end

  test "invalid parameters are rejected before calling the API" do
    [
      valid_params.merge(topic: " "),
      valid_params.merge(difficulty: "expert"),
      valid_params.merge(pair_count: 1),
      valid_params.merge(pair_count: 21),
      valid_params.merge(pair_type: "word_sound")
    ].each do |invalid_params|
      assert_no_difference("Exercise.count") do
        post generate_memory_game_exercises_url, params: invalid_params, as: :json
      end
      assert_response :unprocessable_entity
    end
    assert_empty @client.calls
  end

  test "students and unauthenticated users cannot generate memory games" do
    delete logout_url
    post generate_memory_game_exercises_url, params: valid_params, as: :json
    assert_response :unauthorized
    assert_empty @client.calls

    student = Student.create!(
      name: "Aluno Memória IA",
      username: "memory-ai-student-#{SecureRandom.hex(6)}",
      email: "memory-ai-student-#{SecureRandom.hex(6)}@example.com",
      password: "secret123"
    )
    post login_url, params: { role: "student", username: student.username, password: "secret123" }
    post generate_memory_game_exercises_url, params: valid_params, as: :json
    assert_response :forbidden
    assert_empty @client.calls
  end

  private

  def valid_params
    { topic: "Animais", difficulty: "medium", pair_count: 2, pair_type: "word_word" }
  end
end
