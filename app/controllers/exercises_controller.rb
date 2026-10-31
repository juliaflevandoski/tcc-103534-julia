class ExercisesController < ApplicationController
  include StudentPlayerContext

  INVALID_TYPE_MESSAGE = "Tipo de exercício inválido.".freeze
  INVALID_CONTENT_MESSAGE = "Conteúdo do exercício inválido.".freeze
  MEMORY_STORAGE_ERROR_MESSAGE = "Não foi possível salvar as imagens. Tente novamente.".freeze
  MEMORY_STORAGE_FAILURES = [ ActiveStorage::Error, ActiveRecord::ActiveRecordError, SystemCallError, IOError ].freeze

  class_attribute :quiz_generator_service, default: Exercises::QuizGenerator
  class_attribute :fill_blanks_generator_service, default: Exercises::FillBlanksGenerator
  class_attribute :ordering_generator_service, default: Exercises::OrderingGenerator
  class_attribute :crossword_generator_service, default: Exercises::CrosswordGenerator
  class_attribute :memory_game_generator_service, default: Exercises::MemoryGameGenerator

  skip_before_action :require_authentication, only: %i[generate_quiz generate_fill_blanks generate_ordering generate_crossword generate_memory_game]
  before_action :require_teacher_for_quiz_generation, only: :generate_quiz
  before_action :require_teacher_for_fill_blanks_generation, only: :generate_fill_blanks
  before_action :require_teacher_for_ordering_generation, only: :generate_ordering
  before_action :require_teacher_for_crossword_generation, only: :generate_crossword
  before_action :require_teacher_for_memory_game_generation, only: :generate_memory_game
  before_action :set_exercise, only: %i[show edit update destroy]
  before_action :set_source_activity, only: %i[new create show edit update]

  def index
    authorize Exercise
    @exercises = current_teacher.exercises.active.includes(:teacher).order(:title)
  end

  def show
    authorize @exercise
    @already_in_source_activity = @source_activity&.activity_exercises&.active&.exists?(exercise_id: @exercise.id)
    if current_student && (@exercise.quiz? || @exercise.fill_blanks? || @exercise.ordering? || @exercise.crossword? || @exercise.memory_game?)
      @activity_exercise = ActivityExercise.active.find_by!(id: params[:activity_exercise_id], exercise_id: @exercise.id)
      authorize @activity_exercise, :show?
      unless @exercise.memory_game?
        attempt = ActivityResults.official_attempt(activity_exercise: @activity_exercise, student: current_student)
        @previous_official_attempt = attempt if attempt && policy(attempt).show?
      end
    end

    if current_student && @exercise.ordering?
      ordering = @exercise.object.deep_stringify_keys
      @ordering_instructions = ordering.fetch("instructions", "")
      if ordering["format"] == "multiple_sentences"
        @ordering_sentences = ordering_sentences_for_student(ordering)
      else
        @ordering_items = Array(ordering["items"]).shuffle
      end
    elsif current_student && @exercise.crossword?
      @crossword_payload = crossword_student_payload(@exercise.object)
    elsif current_student && @exercise.memory_game?
      @memory_game_attempt = load_memory_game_attempt
      @memory_game_payload = memory_game_student_payload(@memory_game_attempt) if @memory_game_attempt
      candidate = ActivityExercises::NextExercise.call(activity_exercise: @activity_exercise)
      @next_activity_exercise = candidate if candidate && policy(candidate).show?
    elsif current_teacher && @exercise.memory_game?
      @memory_game_preview_deck = Exercises::MemoryGamePlay.start(
        object: @exercise.object,
        attached_image_blob_ids: @exercise.memory_images_attachments.pluck(:blob_id)
      ).fetch("correct").fetch("deck")
    end
  end

  def new
    @exercise = Exercise.new(object: {})
    authorize @exercise
  end

  def crossword_preview
    authorize Exercise, :create?
    preview_params = params.permit(:instructions, :seed, words: %i[word clue])
    result = Exercises::CrosswordBuilder.call(
      words: preview_params[:words],
      instructions: preview_params[:instructions],
      seed: preview_params[:seed]
    )

    if result.success?
      render json: { data: { object: result.object }, errors: [] }, status: :ok
    else
      render json: {
        data: nil,
        errors: result.errors.map { |message| { field: "words", message: } },
        unplaced_words: result.unplaced_words
      }, status: :unprocessable_entity
    end
  end

  def generate_quiz
    authorize Exercise, :create?
    generation_params = params.permit(:topic, :difficulty, :question_count, :refinement, question_types: [])
    result = self.class.quiz_generator_service.call(
      topic: generation_params[:topic],
      difficulty: generation_params[:difficulty],
      question_count: generation_params[:question_count],
      question_types: generation_params[:question_types] || [],
      refinement: generation_params[:refinement],
      previous_draft: previous_draft_param
    )

    if result.success?
      render json: { data: { quiz: result.quiz }, errors: [] }, status: :ok
    else
      render json: { data: nil, errors: [ { field: "generation", message: result.message } ] },
        status: quiz_generation_status(result.error_code)
    end
  rescue Pundit::NotAuthorizedError
    render json: { data: nil, errors: [ { field: "base", message: "Somente professores podem gerar quizzes." } ] },
      status: :forbidden
  rescue StandardError => error
    Rails.logger.error("Quiz AI generation failed: #{error.class}")
    render json: { data: nil, errors: [ { field: "generation", message: "Não foi possível gerar o quiz agora. Tente novamente." } ] },
      status: :internal_server_error
  end

  def generate_fill_blanks
    authorize Exercise, :create?
    generation_params = params.except(:exercise).permit(:topic, :difficulty, :blank_count, :refinement)
    result = self.class.fill_blanks_generator_service.call(
      topic: generation_params[:topic],
      difficulty: generation_params[:difficulty],
      blank_count: generation_params[:blank_count],
      refinement: generation_params[:refinement],
      previous_draft: previous_draft_param
    )

    if result.success?
      render json: { data: { draft: result.draft }, errors: [] }, status: :ok
    else
      render json: { data: nil, errors: [ { field: "generation", message: result.message } ] },
        status: quiz_generation_status(result.error_code)
    end
  rescue Pundit::NotAuthorizedError
    render json: { data: nil, errors: [ { field: "base", message: "Somente professores podem gerar exercícios." } ] },
      status: :forbidden
  rescue StandardError => error
    internal_frame = error.backtrace&.find { |frame| frame.include?("app/") || frame.include?("app\\") }
    error_name = error.name if error.respond_to?(:name)
    Rails.logger.error("AI fill blanks generation failed: #{error.class}##{error_name} at #{internal_frame}")
    render json: { data: nil, errors: [ { field: "generation", message: "Não foi possível gerar o exercício agora. Tente novamente." } ] },
      status: :internal_server_error
  end

  def generate_ordering
    authorize Exercise, :create?
    generation_params = params.permit(:topic, :difficulty, :format, :sentence_count, :item_count, :item_type, :refinement)
    result = self.class.ordering_generator_service.call(
      topic: generation_params[:topic],
      difficulty: generation_params[:difficulty],
      format: generation_params[:format],
      sentence_count: generation_params[:sentence_count],
      item_count: generation_params[:item_count],
      item_type: generation_params[:item_type],
      refinement: generation_params[:refinement],
      previous_draft: previous_draft_param
    )

    if result.success?
      render json: { data: { draft: result.draft }, errors: [] }, status: :ok
    else
      render json: { data: nil, errors: [ { field: "generation", message: result.message } ] },
        status: quiz_generation_status(result.error_code)
    end
  rescue Pundit::NotAuthorizedError
    render json: { data: nil, errors: [ { field: "base", message: "Somente professores podem gerar exercícios." } ] },
      status: :forbidden
  rescue StandardError => error
    Rails.logger.error("AI ordering generation failed: #{error.class}")
    render json: { data: nil, errors: [ { field: "generation", message: "Não foi possível gerar o exercício agora. Tente novamente." } ] },
      status: :internal_server_error
  end

  def generate_crossword
    authorize Exercise, :create?
    generation_params = params.permit(:topic, :difficulty, :word_count, :refinement)
    result = self.class.crossword_generator_service.call(
      topic: generation_params[:topic],
      difficulty: generation_params[:difficulty],
      word_count: generation_params[:word_count],
      refinement: generation_params[:refinement],
      previous_draft: previous_draft_param
    )

    if result.success?
      render json: { data: { draft: result.draft }, errors: [] }, status: :ok
    else
      render json: { data: nil, errors: [ { field: "generation", message: result.message } ] },
        status: quiz_generation_status(result.error_code)
    end
  rescue Pundit::NotAuthorizedError
    render json: { data: nil, errors: [ { field: "base", message: "Somente professores podem gerar exercícios." } ] },
      status: :forbidden
  rescue StandardError => error
    Rails.logger.error("AI crossword generation failed: #{error.class}")
    render json: { data: nil, errors: [ { field: "generation", message: "Não foi possível gerar o exercício agora. Tente novamente." } ] },
      status: :internal_server_error
  end

  def generate_memory_game
    authorize Exercise, :create?
    generation_params = params.permit(:topic, :difficulty, :pair_count, :pair_type, :refinement)
    result = self.class.memory_game_generator_service.call(
      topic: generation_params[:topic],
      difficulty: generation_params[:difficulty],
      pair_count: generation_params[:pair_count],
      pair_type: generation_params[:pair_type],
      refinement: generation_params[:refinement],
      previous_draft: previous_draft_param
    )

    if result.success?
      render json: { data: { draft: result.draft }, errors: [] }, status: :ok
    else
      render json: { data: nil, errors: [ { field: "generation", message: result.message } ] },
        status: quiz_generation_status(result.error_code)
    end
  rescue Pundit::NotAuthorizedError
    render json: { data: nil, errors: [ { field: "base", message: "Somente professores podem gerar exercícios." } ] },
      status: :forbidden
  rescue StandardError => error
    Rails.logger.error("AI memory game generation failed: #{error.class}")
    render json: { data: nil, errors: [ { field: "generation", message: "Não foi possível gerar o exercício agora. Tente novamente." } ] },
      status: :internal_server_error
  end

  def create
    authorize Exercise, :create?
    attributes = exercise_params
    @exercise = current_teacher.exercises.build(attributes)
    authorize @exercise
    return render_input_errors(:new) if @input_errors.any?
    return render :new, status: :unprocessable_entity unless prepare_crossword_object!(attributes[:object])
    if @exercise.memory_game?
      return render :new, status: :unprocessable_entity unless prepare_memory_game_object!(attributes[:object])
      return render :new, status: :unprocessable_entity unless save_memory_game_exercise

      return redirect_to created_exercise_path
    end

    return redirect_to created_exercise_path if @exercise.save

    render :new, status: :unprocessable_entity
  end

  def edit
    authorize @exercise
  end

  def update
    authorize @exercise
    attributes = exercise_params
    @exercise.assign_attributes(attributes)
    return render_input_errors(:edit) if @input_errors.any?
    return render :edit, status: :unprocessable_entity unless prepare_crossword_object!(attributes[:object])
    if @exercise.memory_game?
      return render :edit, status: :unprocessable_entity unless prepare_memory_game_object!(attributes[:object])
      return render :edit, status: :unprocessable_entity unless save_memory_game_exercise

      return redirect_to created_exercise_path
    end
    return redirect_to created_exercise_path if @exercise.save

    render :edit, status: :unprocessable_entity
  end

  def destroy
    authorize @exercise
    @exercise.update!(active: false)
    redirect_to exercises_path, notice: "Exercício desativado."
  end

  private

  def require_teacher_for_quiz_generation
    return if current_teacher

    message = current_student ? "Somente professores podem gerar quizzes." : "Faça login como professor para gerar quizzes."
    render json: { data: nil, errors: [ { field: "base", message: } ] },
      status: current_student ? :forbidden : :unauthorized
  end

  def require_teacher_for_fill_blanks_generation
    return if current_teacher

    message = current_student ? "Somente professores podem gerar exercícios." : "Faça login como professor para gerar exercícios."
    render json: { data: nil, errors: [ { field: "base", message: } ] },
      status: current_student ? :forbidden : :unauthorized
  end

  def require_teacher_for_ordering_generation
    return if current_teacher

    message = current_student ? "Somente professores podem gerar exercícios." : "Faça login como professor para gerar exercícios."
    render json: { data: nil, errors: [ { field: "base", message: } ] },
      status: current_student ? :forbidden : :unauthorized
  end

  def require_teacher_for_crossword_generation
    return if current_teacher

    message = current_student ? "Somente professores podem gerar exercícios." : "Faça login como professor para gerar exercícios."
    render json: { data: nil, errors: [ { field: "base", message: } ] },
      status: current_student ? :forbidden : :unauthorized
  end

  def require_teacher_for_memory_game_generation
    return if current_teacher

    message = current_student ? "Somente professores podem gerar exercícios." : "Faça login como professor para gerar exercícios."
    render json: { data: nil, errors: [ { field: "base", message: } ] },
      status: current_student ? :forbidden : :unauthorized
  end

  def previous_draft_param
    request.request_parameters["previous_draft"]
  end

  def quiz_generation_status(error_code)
    case error_code
    when :invalid_input then :unprocessable_entity
    when :timeout then :gateway_timeout
    when :rate_limited then :too_many_requests
    when :service_unavailable then :service_unavailable
    else :bad_gateway
    end
  end

  def set_exercise
    @exercise = Exercise.active.find(params[:id])
  end

  # Contexto opcional: só vale para aulas ativas do professor autenticado.
  def set_source_activity
    return unless current_teacher && params[:activity_id].present?

    @source_activity = current_teacher.activities.active.find_by(id: params[:activity_id])
  end

  def created_exercise_path
    @source_activity ? exercise_path(@exercise, activity_id: @source_activity.id) : exercise_path(@exercise)
  end

  def exercise_params
    raw_params = params.require(:exercise)
    uploads = raw_params[:memory_images]
    @memory_upload_params = uploads.respond_to?(:to_unsafe_h) ? uploads.to_unsafe_h : uploads.to_h if uploads.present?
    @memory_upload_params ||= {}
    @input_errors = []
    permitted = raw_params.permit(:exercise_type, :title, :description, :object)
    reject_invalid_exercise_type!(permitted)
    if permitted[:object].is_a?(String)
      begin
        permitted[:object] = JSON.parse(permitted[:object])
      rescue JSON::ParserError
        @input_errors << INVALID_CONTENT_MESSAGE
        permitted[:object] = {}
      end
    end
    permitted[:object] = permitted[:object].to_unsafe_h if permitted[:object].is_a?(ActionController::Parameters)
    permitted
  end

  # O enum lança ArgumentError ao receber um valor desconhecido; o tipo é descartado para o formulário ser reexibido.
  def reject_invalid_exercise_type!(permitted)
    type = permitted[:exercise_type]
    return if type.blank? || Exercise.exercise_types.key?(type.to_s)

    @input_errors << INVALID_TYPE_MESSAGE
    permitted.delete(:exercise_type)
  end

  def render_input_errors(template)
    @input_errors.each { |message| @exercise.errors.add(:base, message) }
    render template, status: :unprocessable_entity
  end

  def prepare_memory_game_object!(submitted_object)
    submitted_object = submitted_object.to_unsafe_h if submitted_object.is_a?(ActionController::Parameters)
    unless submitted_object.is_a?(Hash)
      @exercise.errors.add(:base, INVALID_CONTENT_MESSAGE)
      @exercise.errors.add(:base, Exercise::TITLE_BLANK_MESSAGE) if @exercise.title.blank?
      return false
    end

    result = Exercises::MemoryGameBuilder.call(object: submitted_object)
    result.errors.each { |message| @exercise.errors.add(:base, message) }
    @exercise.errors.add(:base, Exercise::TITLE_BLANK_MESSAGE) if @exercise.title.blank?
    @exercise.errors.add(:base, "Informe as instruções do jogo.") if result.object["instructions"].blank?

    @memory_game_uploads = {}
    @memory_game_upload_content_types = {}
    result.object.fetch("pairs").each_with_index do |pair, pair_index|
      %w[left right].each do |side|
        element = pair.fetch(side)
        if element["type"] == "word"
          next
        elsif element["upload_key"]
          upload_key = element.fetch("upload_key")
          upload = @memory_upload_params[upload_key]
          unless upload
            @exercise.errors.add(:base, "Par #{pair_index + 1}: selecione a imagem indicada.")
            next
          end

          validation = Exercises::MemoryGameImageValidator.call(upload)
          validation.errors.each { |message| @exercise.errors.add(:base, "Par #{pair_index + 1}: #{message}") }
          @memory_game_uploads[upload_key] = upload if validation.success?
          @memory_game_upload_content_types[upload_key] = validation.content_type if validation.success?
        elsif !@exercise.memory_images_attachments.exists?(blob_id: element["blob_id"])
          @exercise.errors.add(:base, "Par #{pair_index + 1}: selecione uma imagem válida.")
        end
      end
    end

    @exercise.object = result.object
    @exercise.memory_upload_keys = @memory_game_uploads.keys
    result.success? && @exercise.errors.empty?
  end

  def persist_memory_game_uploads!
    uploaded_blob_ids = @memory_game_uploads.to_h do |upload_key, upload|
      upload.tempfile.rewind
      blob = ActiveStorage::Blob.build_after_unfurling(
        io: upload.tempfile,
        filename: upload.original_filename,
        content_type: @memory_game_upload_content_types.fetch(upload_key)
      )
      # Registrado antes do envio para que um arquivo parcial também seja removido em caso de falha.
      @new_memory_blobs << blob
      upload.tempfile.rewind
      blob.upload_without_unfurling(upload.tempfile)
      blob.save!
      @exercise.memory_images.attach(blob)
      [ upload_key, blob.id ]
    end
    object = @exercise.object.deep_dup
    object.fetch("pairs").each do |pair|
      %w[left right].each do |side|
        element = pair.fetch(side)
        next unless element["upload_key"]

        pair[side] = { "type" => "image", "blob_id" => uploaded_blob_ids.fetch(element.fetch("upload_key")) }
      end
    end
    @exercise.update!(object:)

    used_blob_ids = object.fetch("pairs").flat_map { |pair| pair.values.filter_map { |element| element["blob_id"] } }
    detach_unreferenced_memory_images(used_blob_ids)
  end

  # Roda dentro da transação, que já detém o bloqueio de escrita do SQLite: uma partida criada antes é vista aqui
  # e uma criada depois lê o JSON novo, então nenhuma tentativa pode passar a depender de um blob removido.
  # Só os registros são removidos neste ponto; os arquivos físicos são apagados após o commit.
  def detach_unreferenced_memory_images(used_blob_ids)
    references = Exercises::MemoryImageReferences.call(@exercise)
    return unless references.complete?

    protected_ids = references.blob_ids | used_blob_ids.to_set
    removed = []
    ActiveRecord::Base.transaction(requires_new: true) do
      ActiveStorage::Attachment.where(record: @exercise, name: "memory_images").includes(:blob).each do |attachment|
        next if protected_ids.include?(attachment.blob_id)

        blob = attachment.blob
        attachment.delete
        next if ActiveStorage::Attachment.exists?(blob_id: blob.id)

        blob.destroy!
        removed << blob
      end
    end
    @removed_memory_blobs.concat(removed)
    @exercise.memory_images_attachments.reset
  rescue StandardError => error
    Rails.logger.error("Memory game stale image detach failed: #{error.class}")
  end

  # Salva o exercício, os blobs e os anexos em uma única transação. Os arquivos novos só existem fora do banco,
  # então são apagados do storage se qualquer etapa falhar; os antigos só são removidos após o commit.
  def save_memory_game_exercise
    @new_memory_blobs = []
    @removed_memory_blobs = []
    saved = false
    ActiveRecord::Base.transaction do
      saved = @exercise.save
      raise ActiveRecord::Rollback unless saved

      persist_memory_game_uploads!
    end
    return false unless saved

    delete_removed_memory_files
    true
  rescue *MEMORY_STORAGE_FAILURES => error
    Rails.logger.error("Memory game image storage failed: #{error.class}")
    discard_new_memory_blobs
    @exercise.memory_images_attachments.reset
    @exercise.errors.add(:base, MEMORY_STORAGE_ERROR_MESSAGE)
    false
  end

  def discard_new_memory_blobs
    @new_memory_blobs.each do |blob|
      blob.service.delete(blob.key)
    rescue StandardError => error
      Rails.logger.error("Memory game orphan file cleanup failed: #{error.class}")
    end
  end

  def delete_removed_memory_files
    @removed_memory_blobs.each do |blob|
      blob.delete
    rescue StandardError => error
      Rails.logger.error("Memory game stale image cleanup failed: #{error.class}")
    end
  end

  def load_memory_game_attempt
    attempts = ExerciseAttempt.active.where(
      student_id: current_student.id,
      activity_exercise_id: @activity_exercise.id
    ).order(id: :desc)
    attempt = if params[:memory_game_attempt_id].present?
      attempts.find(params[:memory_game_attempt_id])
    else
      attempts.detect { |candidate| !candidate.answer.to_h["completed"] }
    end
    authorize attempt if attempt
    attempt
  end

  def memory_game_student_payload(attempt)
    answer = attempt.answer.to_h
    correct = attempt.correct.to_h
    exposed_ids = Array(answer["matched_card_ids"]) + Array(answer["pending_reset_ids"])
    exposed_ids << answer["selected_card_id"] if answer["selected_card_id"].present?
    revealed_cards = Array(correct["deck"]).filter_map do |card|
      serialize_memory_game_card(card) if exposed_ids.include?(card["id"])
    end
    {
      card_ids: Array(correct["deck"]).pluck("id"),
      revealed_cards:,
      matched_card_ids: Array(answer["matched_card_ids"]),
      selected_card_id: answer["selected_card_id"],
      pending_reset_ids: Array(answer["pending_reset_ids"]),
      attempts: answer.fetch("attempts", 0),
      matches: answer.fetch("matches", 0),
      errors: answer.fetch("errors", 0),
      score: attempt.score
    }
  end

  def serialize_memory_game_card(card)
    element = card.fetch("element")
    return { "id" => card.fetch("id") }.merge(element.slice("type", "content")) if element["type"] == "word"

    blob_id = element.fetch("blob_id")
    attachment = @exercise.memory_images_attachments.find_by!(blob_id:)
    { "id" => card.fetch("id"), "type" => "image", "url" => rails_blob_path(attachment.blob, only_path: true) }
  end

  def prepare_crossword_object!(submitted_object)
    return true unless @exercise.crossword?

    submitted_object = submitted_object.to_unsafe_h if submitted_object.is_a?(ActionController::Parameters)
    unless submitted_object.is_a?(Hash)
      @exercise.errors.add(:base, INVALID_CONTENT_MESSAGE)
      @exercise.errors.add(:base, Exercise::TITLE_BLANK_MESSAGE) if @exercise.title.blank?
      return false
    end

    source = JSON.parse(submitted_object.to_json).deep_stringify_keys
    result = Exercises::CrosswordBuilder.call(
      words: source["words"],
      instructions: source["instructions"],
      seed: source["layout_seed"]
    )
    unless result.success?
      @exercise.object = source
      messages = result.errors.dup
      messages << "Não foi possível posicionar: #{result.unplaced_words.join(', ')}." if result.unplaced_words.any?
      messages.each { |message| @exercise.errors.add(:base, message) }
      return false
    end

    if @exercise.title.blank?
      @exercise.errors.add(:base, Exercise::TITLE_BLANK_MESSAGE)
      @exercise.object = source
      return false
    end

    @exercise.object = result.object
    true
  end
end
