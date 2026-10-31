require "test_helper"

# Pausa uma requisição dentro da sua transação de escrita, para provar a serialização.
module MemoryConcurrencySync
  class << self
    attr_accessor :entered, :release, :pause_in

    def pause(point)
      return unless pause_in == point

      self.pause_in = nil
      entered << true
      release.pop(timeout: 15)
    end
  end
end

module PausingEditHook
  def persist_memory_game_uploads!(*args, **kwargs)
    MemoryConcurrencySync.pause(:edit)
    super
  end
end

module PausingStartHook
  def start(*args, **kwargs)
    MemoryConcurrencySync.pause(:start)
    super
  end
end

ExercisesController.prepend(PausingEditHook)
Exercises::MemoryGamePlay.singleton_class.prepend(PausingStartHook)

# Sem transação de teste: as duas requisições usam conexões reais e disputam o bloqueio de escrita do SQLite.
class MemoryGameConcurrencyTest < ActionDispatch::IntegrationTest
  self.use_transactional_tests = false
  parallelize(workers: 1)

  PNG = Base64.decode64("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jM2kAAAAASUVORK5CYII=")

  setup do
    cleanup_tables
    @files = []
    MemoryConcurrencySync.entered = Queue.new
    MemoryConcurrencySync.release = Queue.new
    MemoryConcurrencySync.pause_in = nil
    @teacher = Teacher.create!(name: "Professora", username: "profconc", email: "conc@example.com", password: "secret123")
    @student = Student.create!(name: "Aluno", username: "alunoconc", email: "alunoconc@example.com", password: "secret123")
    school_class = @teacher.school_classes.create!(name: "Turma", active: true)
    school_class.class_students.create!(student: @student, active: true)
    activity = school_class.activities.create!(title: "Aula", published: true)
    @teacher_session = open_session
    @student_session = open_session
    login(@teacher_session, "teacher", @teacher)
    login(@student_session, "student", @student)
    @teacher_session.post exercises_url, params: params_for({ "k1" => upload("a"), "k2" => upload("b") },
      [ pair("DOG", { type: "image", upload_key: "k1" }), pair("CAT", { type: "image", upload_key: "k2" }) ])
    @exercise = Exercise.order(:id).last
    @link = activity.activity_exercises.create!(exercise: @exercise, position: 1, points: 10)
    @b1, @b2 = @exercise.object.fetch("pairs").map { |p| p.dig("right", "blob_id") }
  end

  teardown do
    MemoryConcurrencySync.pause_in = nil
    @files.each(&:close!)
    cleanup_tables
  end

  test "game started while the teacher's edit holds the lock reads the new JSON and no needed image is lost" do
    MemoryConcurrencySync.pause_in = :edit
    editor = Thread.new { edit_replacing_first_image }
    assert MemoryConcurrencySync.entered.pop(timeout: 15), "a edição deveria ter entrado na transação"

    starter = Thread.new { start_game }
    sleep 0.8
    assert starter.alive?, "a criação da partida deveria aguardar a transação de escrita da edição"
    MemoryConcurrencySync.release << true
    [ editor, starter ].each { |thread| assert thread.join(20), "thread não terminou" }

    attempt = ExerciseAttempt.order(:id).last
    exercise = @exercise.reload
    current_ids = exercise.object.fetch("pairs").map { |p| p.dig("right", "blob_id") }
    deck_ids = attempt.correct.fetch("deck").filter_map { |card| card.dig("element", "blob_id") }
    assert_equal current_ids.sort, deck_ids.sort
    assert_not_includes deck_ids, @b1
    assert_all_files_present(deck_ids, exercise)
  end

  test "edit started while a game is being created waits, sees the attempt and keeps its images" do
    MemoryConcurrencySync.pause_in = :start
    starter = Thread.new { start_game }
    assert MemoryConcurrencySync.entered.pop(timeout: 15), "a partida deveria ter entrado na transação"

    editor = Thread.new { edit_replacing_first_image }
    sleep 0.8
    assert editor.alive?, "a edição deveria aguardar a transação de escrita da criação da partida"
    MemoryConcurrencySync.release << true
    [ starter, editor ].each { |thread| assert thread.join(20), "thread não terminou" }

    attempt = ExerciseAttempt.order(:id).last
    deck_ids = attempt.correct.fetch("deck").filter_map { |card| card.dig("element", "blob_id") }
    assert_includes deck_ids, @b1
    assert_all_files_present(deck_ids, @exercise.reload)
  end

  private

  def edit_replacing_first_image
    @teacher_session.patch exercise_url(@exercise), params: params_for({ "n1" => upload("c") },
      [ pair("DOG", { type: "image", upload_key: "n1" }), pair("CAT", { type: "image", blob_id: @b2 }) ])
  end

  def start_game
    @student_session.post exercise_attempts_url, params: { exercise_attempt: { activity_exercise_id: @link.id } }
  end

  def assert_all_files_present(blob_ids, exercise)
    attached = exercise.memory_images_attachments.reload.map(&:blob_id)
    blob_ids.each do |blob_id|
      blob = ActiveStorage::Blob.find(blob_id)
      assert File.exist?(blob.service.path_for(blob.key)), "arquivo do blob #{blob_id} ausente"
      assert_includes attached, blob_id
    end
  end

  def login(session, role, user)
    session.post login_url, params: { role:, username: user.username, password: "secret123" }
  end

  def cleanup_tables
    [ ExerciseAttempt, ActivityExercise, Activity, ClassStudent, SchoolClass, ActiveStorage::Attachment,
      ActiveStorage::Blob, Exercise, Student, Teacher ].each(&:delete_all)
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
end
