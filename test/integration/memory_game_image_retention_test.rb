require "test_helper"

module BeforeMemorySaveHook
  class << self
    attr_accessor :callback
  end

  def save_memory_game_exercise
    BeforeMemorySaveHook.callback&.call
    super
  end
end
ExercisesController.prepend(BeforeMemorySaveHook)

class MemoryGameImageRetentionTest < ActionDispatch::IntegrationTest
  parallelize(workers: 1)

  PNG = Base64.decode64("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jM2kAAAAASUVORK5CYII=")

  setup do
    @files = []
    @teacher = Teacher.create!(name: "Professora", username: "profretencao", email: "retencao@example.com", password: "secret123")
    @student = Student.create!(name: "Aluno", username: "alunoretencao", email: "alunoretencao@example.com", password: "secret123")
    school_class = @teacher.school_classes.create!(name: "Turma", active: true)
    school_class.class_students.create!(student: @student, active: true)
    @activity = school_class.activities.create!(title: "Aula", published: true)
    login_as("teacher", @teacher)
    post exercises_url, params: params_for({ "k1" => upload("a"), "k2" => upload("b") },
      [ pair("DOG", { type: "image", upload_key: "k1" }), pair("CAT", { type: "image", upload_key: "k2" }) ])
    @exercise = Exercise.order(:id).last
    @link = @activity.activity_exercises.create!(exercise: @exercise, position: 1, points: 10)
    @old_object = @exercise.object
    @b1, @b2 = blob_ids(@exercise)
    login_as("student", @student)
    post exercise_attempts_url, params: { exercise_attempt: { activity_exercise_id: @link.id } }
    @attempt = ExerciseAttempt.order(:id).last
  end

  teardown do
    BeforeMemorySaveHook.callback = nil
    @files.each(&:close!)
  end

  test "in-progress game keeps working after the image is replaced" do
    replace_first_image

    post memory_game_turn_exercise_attempt_url(@attempt), params: { operation: "reveal", card_id: card_for(@b1)["id"] }, as: :json

    assert_response :success
    assert_equal "image", JSON.parse(response.body).dig("data", "card", "type")
    assert_old_image_retained(@b1)
    assert_not_includes blob_ids(@exercise.reload), @b1
    assert_includes @exercise.memory_images_attachments.map(&:blob_id), @b1
  end

  test "reloading an in-progress game after replacement still renders the revealed old image" do
    post memory_game_turn_exercise_attempt_url(@attempt), params: { operation: "reveal", card_id: card_for(@b1)["id"] }, as: :json
    assert_response :success
    replace_first_image

    get exercise_url(@exercise, activity_exercise_id: @link.id)

    assert_response :success
    assert_select ".memory-board img", count: 1
  end

  test "completed game stays accessible after replacement" do
    deck_ids = @attempt.correct.fetch("deck").pluck("id")
    @attempt.update_columns(answer: @attempt.answer.merge("completed" => true, "matched_card_ids" => deck_ids, "matches" => 2, "attempts" => 2))
    replace_first_image

    get exercise_url(@exercise, activity_exercise_id: @link.id, memory_game_attempt_id: @attempt.id)

    assert_response :success
    assert_select ".memory-result"
    assert_old_image_retained(@b1)
  end

  test "a new game after replacement uses only the current images" do
    replace_first_image

    post exercise_attempts_url, params: { exercise_attempt: { activity_exercise_id: @link.id } }
    new_attempt = ExerciseAttempt.order(:id).last

    assert_not_equal @attempt.id, new_attempt.id
    new_blob_ids = new_attempt.correct.fetch("deck").filter_map { |card| card.dig("element", "blob_id") }
    assert_equal blob_ids(@exercise.reload).sort, new_blob_ids.sort
    assert_not_includes new_blob_ids, @b1
    assert_includes @attempt.reload.correct.fetch("deck").filter_map { |card| card.dig("element", "blob_id") }, @b1
  end

  test "an image no attempt references is removed on the next edit" do
    replace_first_image
    assert_old_image_retained(@b1)
    path = blob_file(@b1)
    ExerciseAttempt.delete_all
    login_as("teacher", @teacher)

    patch exercise_url(@exercise), params: params_for({}, current_pairs)

    assert_response :redirect
    assert_not ActiveStorage::Blob.exists?(@b1)
    assert_not ActiveStorage::Attachment.exists?(blob_id: @b1)
    assert_not File.exist?(path)
    assert_equal blob_ids(@exercise.reload).sort, @exercise.memory_images_attachments.map(&:blob_id).sort
  end

  test "an inactive attempt still preserves its images" do
    @attempt.update!(active: false)
    replace_first_image

    assert_response :redirect
    assert_old_image_retained(@b1)
  end

  test "an attempt of an inactive link or inactive activity still preserves its images" do
    @link.update!(active: false)
    @activity.update!(published: false)
    replace_first_image

    assert_response :redirect
    assert_old_image_retained(@b1)
  end

  test "an unreadable historical reference makes the cleanup conservative" do
    @attempt.update_columns(correct: { "deck" => "garbage" })
    replace_first_image

    assert_response :redirect
    assert_old_image_retained(@b1)
    assert ActiveStorage::Blob.exists?(@b2)
  end

  test "a failing upload keeps the previous content even with historical attempts" do
    object_before = @exercise.reload.object
    files_before = stored_files

    fail_on_upload do
      assert_no_difference [ "ActiveStorage::Blob.count", "ActiveStorage::Attachment.count" ] do
        login_as("teacher", @teacher)
        patch exercise_url(@exercise), params: params_for({ "n1" => upload("c"), "n2" => upload("d") },
          [ pair("DOG", { type: "image", upload_key: "n1" }), pair("CAT", { type: "image", upload_key: "n2" }) ])
      end
    end

    assert_response :unprocessable_entity
    assert_equal object_before, @exercise.reload.object
    assert_equal files_before, stored_files
  end

  test "an attempt created right before the cleanup transaction is seen and protects its images" do
    login_as("teacher", @teacher)
    ExerciseAttempt.delete_all
    BeforeMemorySaveHook.callback = lambda do
      game = Exercises::MemoryGamePlay.start(object: @old_object, points: 10, attached_image_blob_ids: [ @b1, @b2 ])
      ExerciseAttempt.create!(student: @student, activity_exercise: @link, answer: game.fetch("answer"), correct: game.fetch("correct"), score: 0)
    end

    replace_first_image(login: false)

    assert_response :redirect
    assert_old_image_retained(@b1)
  end

  test "references service collects image blob ids and reports malformed data as incomplete" do
    result = Exercises::MemoryImageReferences.call(@exercise)
    assert result.complete?
    assert_equal [ @b1, @b2 ].to_set, result.blob_ids

    [ { "deck" => "x" }, {}, { "deck" => [ { "element" => { "type" => "image", "blob_id" => "7" } } ] },
      { "deck" => [ { "element" => { "type" => "image" } } ] }, { "deck" => [ "bad" ] } ].each do |correct|
      @attempt.update_columns(correct:)
      assert_not Exercises::MemoryImageReferences.call(@exercise).complete?, correct.inspect
    end
  end

  private

  def replace_first_image(login: true)
    login_as("teacher", @teacher) if login
    patch exercise_url(@exercise), params: params_for({ "n1" => upload("c") },
      [ pair("DOG", { type: "image", upload_key: "n1" }), pair("CAT", { type: "image", blob_id: @b2 }) ])
    login_as("student", @student) if login
  end

  def current_pairs
    @exercise.reload.object.fetch("pairs").map { |p| pair(p.dig("left", "content"), p.fetch("right").symbolize_keys) }
  end

  def assert_old_image_retained(blob_id)
    assert ActiveStorage::Blob.exists?(blob_id)
    assert ActiveStorage::Attachment.exists?(blob_id:, record_type: "Exercise", record_id: @exercise.id)
    assert File.exist?(blob_file(blob_id))
  end

  def blob_file(blob_id)
    blob = ActiveStorage::Blob.find(blob_id)
    blob.service.path_for(blob.key)
  end

  def card_for(blob_id)
    @attempt.reload.correct.fetch("deck").find { |card| card.dig("element", "blob_id") == blob_id }
  end

  def blob_ids(exercise)
    exercise.object.fetch("pairs").filter_map { |p| p.dig("right", "blob_id") }
  end

  def upload(name)
    file = Tempfile.new([ name, ".png" ])
    file.binmode
    file.write(PNG + name.b)
    file.flush
    @files << file
    Rack::Test::UploadedFile.new(file.path, "image/png", true, original_filename: "#{name}.png")
  end

  def pair(word, image)
    { left: { type: "word", content: word }, right: image }
  end

  def params_for(uploads, pairs)
    { exercise: { title: "Memória", exercise_type: "memory_game", memory_images: uploads,
                  object: { instructions: "Combine.", pair_type: "word_image", pairs: }.to_json } }
  end

  def login_as(role, user)
    delete logout_url
    post login_url, params: { role:, username: user.username, password: "secret123" }
  end

  def stored_files
    Dir.glob(File.join(ActiveStorage::Blob.service.root, "**", "*")).select { |path| File.file?(path) }.sort
  end

  def fail_on_upload
    service_class = ActiveStorage::Service::DiskService
    original = service_class.instance_method(:upload)
    calls = 0
    service_class.send(:define_method, :upload) do |*args, **kwargs, &block|
      calls += 1
      raise IOError, "boom" if calls >= 2

      original.bind_call(self, *args, **kwargs, &block)
    end
    yield
  ensure
    service_class.send(:define_method, :upload, original)
  end
end
