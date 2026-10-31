require "test_helper"

class MemoryGameUploadIntegrityTest < ActionDispatch::IntegrationTest
  parallelize(workers: 1)

  PNG = Base64.decode64("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jM2kAAAAASUVORK5CYII=")
  STORAGE_ERROR = "Não foi possível salvar as imagens. Tente novamente.".freeze

  setup do
    @teacher = Teacher.create!(name: "Professora Upload", username: "profupload", email: "upload@example.com", password: "secret123")
    post login_url, params: { role: "teacher", username: @teacher.username, password: "secret123" }
    @files = []
  end

  teardown do
    @files.each(&:close!)
  end

  test "normal creation stores both images and references only attached blobs" do
    post exercises_url, params: memory_params(
      "k1" => upload("a"), "k2" => upload("b")
    ) { |uploads| image_pairs(uploads.keys) }

    exercise = Exercise.order(:id).last
    assert_redirected_to exercise_url(exercise)
    assert_equal 2, exercise.memory_images_attachments.count
    assert_equal exercise.memory_images_attachments.map(&:blob_id).sort, referenced_blob_ids(exercise).sort
    assert exercise.valid?
  end

  test "creation failing on the second upload leaves no exercise, blob, attachment or file" do
    files_before = stored_files

    fail_on_upload(2) do
      assert_no_difference [ "Exercise.count", "ActiveStorage::Blob.count", "ActiveStorage::Attachment.count" ] do
        post exercises_url, params: memory_params("k1" => upload("a"), "k2" => upload("b")) { |uploads| image_pairs(uploads.keys) }
      end
    end

    assert_response :unprocessable_entity
    assert_includes response.body, STORAGE_ERROR
    assert_not_includes response.body, "boom"
    assert_equal files_before, stored_files
  end

  test "creation failure keeps what the teacher typed in the form" do
    files_before = stored_files
    fail_on_upload(1) do
      post exercises_url, params: memory_params("k1" => upload("a"), "k2" => upload("b")) { |uploads| image_pairs(uploads.keys) }
    end

    assert_response :unprocessable_entity
    assert_select "input[name='exercise[title]'][value='Memória com imagens']"
    assert_equal files_before, stored_files
  end

  test "edit failing on the second upload preserves the previous content and attachments" do
    exercise = create_memory_exercise
    object_before = exercise.reload.object
    blob_ids_before = exercise.memory_images_attachments.map(&:blob_id).sort
    files_before = stored_files

    fail_on_upload(2) do
      assert_no_difference [ "ActiveStorage::Blob.count", "ActiveStorage::Attachment.count" ] do
        patch exercise_url(exercise), params: memory_params("n1" => upload("c"), "n2" => upload("d")) { |uploads| image_pairs(uploads.keys) }
      end
    end

    assert_response :unprocessable_entity
    assert_includes response.body, STORAGE_ERROR
    exercise.reload
    assert_equal object_before, exercise.object
    assert_equal blob_ids_before, exercise.memory_images_attachments.map(&:blob_id).sort
    assert_equal files_before, stored_files
    assert exercise.valid?
  end

  test "edit replacing one image removes the old file only after saving and keeps the other" do
    exercise = create_memory_exercise
    kept_id, replaced_id = referenced_blob_ids(exercise)
    replaced_blob = ActiveStorage::Blob.find(replaced_id)
    replaced_path = blob_path(replaced_blob)
    assert File.exist?(replaced_path)

    patch exercise_url(exercise), params: memory_params("n1" => upload("c")) { |uploads|
      [ pair("DOG", { type: "image", blob_id: kept_id }), pair("CAT", { type: "image", upload_key: uploads.keys.first }) ]
    }

    assert_redirected_to exercise_url(exercise)
    exercise.reload
    ids = referenced_blob_ids(exercise)
    assert_includes ids, kept_id
    assert_not_includes ids, replaced_id
    assert_equal ids.sort, exercise.memory_images_attachments.map(&:blob_id).sort
    assert_not ActiveStorage::Blob.exists?(replaced_id)
    assert_not File.exist?(replaced_path)
    assert File.exist?(blob_path(ActiveStorage::Blob.find(kept_id)))
    assert exercise.valid?
  end

  test "edit removing an image pair removes the unused attachment" do
    post exercises_url, params: memory_params("k1" => upload("a"), "k2" => upload("b"), "k3" => upload("c")) { |uploads|
      uploads.keys.zip(%w[DOG CAT BIRD]).map { |key, word| pair(word, { type: "image", upload_key: key }) }
    }
    exercise = Exercise.order(:id).last
    first_id, second_id, removed_id = referenced_blob_ids(exercise)

    patch exercise_url(exercise), params: memory_params({}) {
      [ pair("DOG", { type: "image", blob_id: first_id }), pair("CAT", { type: "image", blob_id: second_id }) ]
    }

    assert_redirected_to exercise_url(exercise)
    exercise.reload
    assert_equal [ first_id, second_id ].sort, exercise.memory_images_attachments.map(&:blob_id).sort
    assert_equal [ first_id, second_id ], referenced_blob_ids(exercise)
    assert_not ActiveStorage::Blob.exists?(removed_id)
  end

  private

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

  def image_pairs(keys)
    keys.zip(%w[DOG CAT]).map { |key, word| pair(word, { type: "image", upload_key: key }) }
  end

  def memory_params(uploads)
    pairs = yield(uploads)
    { exercise: {
      title: "Memória com imagens", exercise_type: "memory_game", memory_images: uploads,
      object: { instructions: "Combine.", pair_type: "word_image", pairs: }.to_json
    } }
  end

  def create_memory_exercise
    post exercises_url, params: memory_params("k1" => upload("a"), "k2" => upload("b")) { |uploads| image_pairs(uploads.keys) }
    Exercise.order(:id).last
  end

  def referenced_blob_ids(exercise)
    exercise.object.fetch("pairs").flat_map { |p| p.values.filter_map { |element| element.is_a?(Hash) ? element["blob_id"] : nil } }
  end

  def storage_root
    ActiveStorage::Blob.service.root
  end

  def stored_files
    Dir.glob(File.join(storage_root, "**", "*")).select { |path| File.file?(path) }.sort
  end

  def blob_path(blob)
    blob.service.path_for(blob.key)
  end

  # Simula a falha do armazenamento a partir do envio de ordem n, depois de gravar os anteriores.
  def fail_on_upload(nth)
    service_class = ActiveStorage::Service::DiskService
    original = service_class.instance_method(:upload)
    calls = 0
    service_class.send(:define_method, :upload) do |*args, **kwargs, &block|
      calls += 1
      raise IOError, "boom" if calls >= nth

      original.bind_call(self, *args, **kwargs, &block)
    end
    yield
  ensure
    service_class.send(:define_method, :upload, original)
  end
end
