class ExercisesController < ApplicationController
  before_action :set_exercise, only: %i[show edit update destroy]

  def index
    authorize Exercise
    @exercises = current_teacher.exercises.active.includes(:teacher).order(:title)
  end

  def show
    authorize @exercise
    if current_student && (@exercise.crossword? || @exercise.memory_game?)
      @activity_exercise = ActivityExercise.active.find_by!(id: params[:activity_exercise_id], exercise_id: @exercise.id)
      authorize @activity_exercise, :show?
    end

    if current_student && @exercise.crossword?
      @crossword_payload = crossword_student_payload(@exercise.object)
    elsif current_student && @exercise.memory_game?
      @memory_game_attempt = load_memory_game_attempt
      @memory_game_payload = memory_game_student_payload(@memory_game_attempt) if @memory_game_attempt
    elsif current_teacher && @exercise.memory_game?
      @memory_game_preview_deck = Exercises::MemoryGamePlay.start(object: @exercise.object).fetch("correct").fetch("deck")
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

  def create
    attributes = exercise_params
    @exercise = current_teacher.exercises.build(attributes)
    authorize @exercise
    return render :new, status: :unprocessable_entity unless prepare_crossword_object!(attributes[:object])
    if @exercise.memory_game?
      return render :new, status: :unprocessable_entity unless prepare_memory_game_object!(attributes[:object])
      return render :new, status: :unprocessable_entity unless @exercise.save

      persist_memory_game_uploads!
      return redirect_to @exercise
    end

    return redirect_to @exercise if @exercise.save

    render :new, status: :unprocessable_entity
  end

  def edit
    authorize @exercise
  end

  def update
    authorize @exercise
    attributes = exercise_params
    @exercise.assign_attributes(attributes)
    return render :edit, status: :unprocessable_entity unless prepare_crossword_object!(attributes[:object])
    if @exercise.memory_game?
      return render :edit, status: :unprocessable_entity unless prepare_memory_game_object!(attributes[:object])
      return render :edit, status: :unprocessable_entity unless @exercise.save

      persist_memory_game_uploads!
      return redirect_to @exercise
    end
    return redirect_to @exercise if @exercise.save

    render :edit, status: :unprocessable_entity
  end

  def destroy
    authorize @exercise
    @exercise.update!(active: false)
    redirect_to exercises_path, notice: "Exercício desativado."
  end

  private

  def set_exercise
    @exercise = Exercise.active.find(params[:id])
  end

  def exercise_params
    raw_params = params.require(:exercise)
    uploads = raw_params[:memory_images]
    @memory_upload_params = uploads.respond_to?(:to_unsafe_h) ? uploads.to_unsafe_h : uploads.to_h if uploads.present?
    @memory_upload_params ||= {}
    permitted = raw_params.permit(:exercise_type, :title, :description, :object)
    permitted[:object] = JSON.parse(permitted[:object]) if permitted[:object].is_a?(String)
    permitted[:object] = permitted[:object].to_unsafe_h if permitted[:object].is_a?(ActionController::Parameters)
    permitted
  rescue JSON::ParserError
    raw_params.permit(:exercise_type, :title, :description).merge(object: {})
  end

  def prepare_memory_game_object!(submitted_object)
    result = Exercises::MemoryGameBuilder.call(object: submitted_object)
    result.errors.each { |message| @exercise.errors.add(:base, message) }
    @exercise.errors.add(:title, "não pode ficar em branco") if @exercise.title.blank?
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
    result.success? && @exercise.errors.empty?
  end

  def persist_memory_game_uploads!
    uploaded_blob_ids = @memory_game_uploads.to_h do |upload_key, upload|
      upload.tempfile.rewind
      blob = ActiveStorage::Blob.create_and_upload!(
        io: upload.tempfile,
        filename: upload.original_filename,
        content_type: @memory_game_upload_content_types.fetch(upload_key)
      )
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
    @exercise.memory_images_attachments.each do |attachment|
      attachment.purge unless used_blob_ids.include?(attachment.blob_id)
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

    source = if submitted_object.is_a?(String)
      JSON.parse(submitted_object)
    elsif submitted_object.respond_to?(:to_json)
      JSON.parse(submitted_object.to_json)
    else
      {}
    end.deep_stringify_keys
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
      @exercise.errors.add(:title, "não pode ficar em branco")
      @exercise.object = source
      return false
    end

    @exercise.object = result.object
    true
  end

  def crossword_student_payload(object)
    layout = object.deep_stringify_keys
    cells = layout.fetch("grid").fetch("cells")
    {
      instructions: layout["instructions"],
      grid_mask: cells.map { |row| row.map(&:present?) },
      entries: layout.fetch("words").map do |entry|
        entry.slice("id", "clue", "number", "row", "column", "direction").merge("length" => entry.fetch("normalized").length)
          .symbolize_keys
      end
    }
  end
end
