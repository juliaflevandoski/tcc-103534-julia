class ExerciseAttemptsController < ApplicationController
  include StudentPlayerContext

  before_action :set_exercise_attempt, only: %i[edit update destroy memory_game_turn]
  before_action :set_exercise_attempt_for_show, only: :show

  def index
    authorize ExerciseAttempt
    @school_classes = results_school_classes.order(:name).to_a
    @selected_school_class = @school_classes.find { |school_class| school_class.id.to_s == params[:school_class_id] } if params[:school_class_id].present?
    if params[:school_class_id].present? && @selected_school_class.nil?
      return redirect_to root_path, alert: "Turma inválida."
    end

    selected_classes = @selected_school_class ? [ @selected_school_class ] : @school_classes
    @result_sections = selected_classes.map do |school_class|
      ResultsDashboard.call(user: current_user, school_class:)
    end
    @student_stat = current_student&.student_stat
  end

  def show
    authorize @exercise_attempt
    @official_attempt = ActivityResults.official_attempt(
      activity_exercise: @exercise_attempt.activity_exercise,
      student: @exercise_attempt.student
    )
    @attempt_points_possible = ActivityResults.points_possible(attempt: @exercise_attempt)
    @attempt_percentage = ActivityResults.attempt_percentage(attempt: @exercise_attempt)
    @attempt_result_summary = attempt_result_summary
    activity = @exercise_attempt.activity_exercise.activity
    @return_to_activity = if current_teacher
      activity.active? && activity.teacher_id == current_teacher.id
    else
      activity.active? && activity.published? && activity.school_class.active? &&
        activity.school_class.class_students.active.exists?(student_id: current_student.id)
    end
    @next_activity_exercise = authorized_next_activity_exercise if current_student && @return_to_activity
  end

  def new
    @exercise_attempt = ExerciseAttempt.new(answer: {}, correct: {})
    authorize @exercise_attempt
    load_options
  end

  def create
    return create_memory_game_attempt if memory_game_submission?
    return create_crossword_attempt if crossword_submission?
    return create_quiz_attempt if quiz_submission?
    return create_fill_blanks_attempt if fill_blanks_submission?
    return create_ordering_attempt if ordering_submission?
    return redirect_to root_path, alert: "Envio de tentativa inválido." if current_student

    @exercise_attempt = ExerciseAttempt.new(exercise_attempt_params)
    authorize @exercise_attempt
    return redirect_to @exercise_attempt if @exercise_attempt.save

    load_options
    render :new, status: :unprocessable_entity
  end

  def edit
    authorize @exercise_attempt
    load_options
  end

  def update
    authorize @exercise_attempt
    return redirect_to @exercise_attempt if @exercise_attempt.update(exercise_attempt_params)

    load_options
    render :edit, status: :unprocessable_entity
  end

  def destroy
    authorize @exercise_attempt
    @exercise_attempt.update!(active: false)
    redirect_to exercise_attempts_path, notice: "Tentativa desativada."
  end

  def memory_game_turn
    authorize @exercise_attempt, :memory_game_turn?
    permitted = params.permit(:operation, :card_id)
    response_data = nil
    response_errors = nil

    @exercise_attempt.with_lock do
      result = if permitted[:operation] == "reset"
        Exercises::MemoryGamePlay.reset(answer: @exercise_attempt.answer, correct: @exercise_attempt.correct)
      elsif permitted[:operation] == "reveal"
        Exercises::MemoryGamePlay.reveal(
          answer: @exercise_attempt.answer,
          correct: @exercise_attempt.correct,
          card_id: permitted[:card_id],
          points: @exercise_attempt.correct.fetch("points", @exercise_attempt.activity_exercise.points)
        )
      else
        nil
      end

      if result.nil?
        response_errors = [ "Ação inválida." ]
        next
      end
      unless result.success?
        response_errors = result.errors
        next
      end

      score = result.comparison ? result.score : @exercise_attempt.score
      correct = result.correct
      xp_awarded = false
      time_spent = @exercise_attempt.time_spent
      if result.completed
        xp_awarded = claim_memory_game_xp!(score)
        correct = correct.merge("xp_award_claimed" => xp_awarded)
        started_at = Time.iso8601(result.answer.fetch("started_at"))
        time_spent = [ (Time.current - started_at).to_i, 0 ].max
      end

      @exercise_attempt.update!(answer: result.answer, correct:, score:, time_spent:)
      response_data = {
        card: serialize_memory_game_card(result.card),
        matched: result.matched,
        comparison: result.comparison,
        completed: result.answer.fetch("completed"),
        attempts: result.answer.fetch("attempts"),
        matches: result.answer.fetch("matches"),
        errors: result.answer.fetch("errors"),
        score: @exercise_attempt.score,
        time_spent: @exercise_attempt.time_spent,
        xp_awarded:
      }
    end

    if response_errors
      render json: { data: nil, errors: response_errors.map { |message| { field: "move", message: } } }, status: :unprocessable_entity
    else
      render json: { data: response_data, errors: [] }, status: :ok
    end
  end

  private

  def memory_game_submission?
    return false unless current_student

    activity_exercise_id = params.dig(:exercise_attempt, :activity_exercise_id)
    ActivityExercise.unscoped.joins(:exercise).exists?(
      id: activity_exercise_id,
      exercises: { exercise_type: Exercise.exercise_types.fetch("memory_game") }
    )
  end

  def create_memory_game_attempt
    permitted = params.require(:exercise_attempt).permit(:activity_exercise_id)
    @activity_exercise = ActivityExercise.active.includes(:activity, :exercise).find(permitted[:activity_exercise_id])
    authorize @activity_exercise, :show?
    # A leitura do exercício e a gravação da tentativa ficam na mesma transação de escrita. Assim, a edição de
    # imagens do professor ou enxerga esta tentativa (e preserva suas imagens) ou termina antes e esta lê o JSON novo.
    ExerciseAttempt.transaction do
      exercise = @activity_exercise.exercise.reload
      exercise.validate!
      game = Exercises::MemoryGamePlay.start(
        object: exercise.object,
        points: @activity_exercise.points,
        attached_image_blob_ids: exercise.memory_images_attachments.pluck(:blob_id)
      )
      @exercise_attempt = ExerciseAttempt.new(
        student: current_student,
        activity_exercise: @activity_exercise,
        answer: game.fetch("answer"),
        correct: game.fetch("correct"),
        score: 0
      )
      authorize @exercise_attempt
      @exercise_attempt.save!
    end
    redirect_to exercise_path(
      @activity_exercise.exercise,
      activity_exercise_id: @activity_exercise.id,
      memory_game_attempt_id: @exercise_attempt.id
    )
  rescue ActiveRecord::RecordNotFound, Pundit::NotAuthorizedError
    redirect_to root_path, alert: "Não foi possível iniciar este jogo da memória."
  rescue ActiveRecord::RecordInvalid
    redirect_to root_path, alert: "Não foi possível registrar a partida."
  end

  def crossword_submission?
    return false unless current_student

    activity_exercise_id = params.dig(:exercise_attempt, :activity_exercise_id)
    ActivityExercise.unscoped.joins(:exercise).exists?(id: activity_exercise_id, exercises: { exercise_type: Exercise.exercise_types.fetch("crossword") })
  end

  def quiz_submission?
    return false unless current_student

    activity_exercise_id = params.dig(:exercise_attempt, :activity_exercise_id)
    ActivityExercise.unscoped.joins(:exercise).exists?(
      id: activity_exercise_id,
      exercises: { exercise_type: Exercise.exercise_types.fetch("quiz") }
    )
  end

  def create_quiz_attempt
    permitted = params.require(:exercise_attempt).permit(:activity_exercise_id, answers: {})
    @activity_exercise = ActivityExercise.active.includes(:activity, :exercise).find(permitted[:activity_exercise_id])
    authorize @activity_exercise, :show?
    result = Exercises::QuizSubmission.call(
      activity_exercise: @activity_exercise,
      student: current_student,
      answers: permitted[:answers] || {}
    )
    @exercise_attempt = result.attempt
    redirect_to @exercise_attempt
  rescue Exercises::AttemptValidity::BlankResponse => error
    render_incomplete_submission(error.message, answers: permitted[:answers])
  rescue ActiveRecord::RecordNotFound, Pundit::NotAuthorizedError
    redirect_to root_path, alert: "Não foi possível enviar este Quiz."
  rescue ActiveRecord::RecordInvalid
    redirect_to exercise_path(@activity_exercise.exercise, activity_exercise_id: @activity_exercise.id), alert: "Não foi possível registrar suas respostas."
  end

  def fill_blanks_submission?
    return false unless current_student

    activity_exercise_id = params.dig(:exercise_attempt, :activity_exercise_id)
    ActivityExercise.unscoped.joins(:exercise).exists?(
      id: activity_exercise_id,
      exercises: { exercise_type: Exercise.exercise_types.fetch("fill_blanks") }
    )
  end

  def create_fill_blanks_attempt
    permitted = params.require(:exercise_attempt).permit(:activity_exercise_id, answers: {})
    @activity_exercise = ActivityExercise.active.includes(:activity, :exercise).find(permitted[:activity_exercise_id])
    authorize @activity_exercise, :show?
    result = Exercises::FillBlanksSubmission.call(
      activity_exercise: @activity_exercise,
      student: current_student,
      answers: permitted[:answers] || {}
    )
    @exercise_attempt = result.attempt
    redirect_to @exercise_attempt
  rescue Exercises::AttemptValidity::BlankResponse => error
    render_incomplete_submission(error.message, answers: permitted[:answers])
  rescue ActiveRecord::RecordNotFound, Pundit::NotAuthorizedError
    redirect_to root_path, alert: "Não foi possível enviar este exercício."
  rescue ActiveRecord::RecordInvalid
    redirect_to exercise_path(@activity_exercise.exercise, activity_exercise_id: @activity_exercise.id), alert: "Não foi possível registrar suas respostas."
  end

  def ordering_submission?
    return false unless current_student

    activity_exercise_id = params.dig(:exercise_attempt, :activity_exercise_id)
    ActivityExercise.unscoped.joins(:exercise).exists?(
      id: activity_exercise_id,
      exercises: { exercise_type: Exercise.exercise_types.fetch("ordering") }
    )
  end

  def create_ordering_attempt
    permitted = params.require(:exercise_attempt).permit(:activity_exercise_id, :sentences_json, ordered_ids: [])
    @activity_exercise = ActivityExercise.active.includes(:activity, :exercise).find(permitted[:activity_exercise_id])
    authorize @activity_exercise, :show?
    ordering = @activity_exercise.exercise.object.deep_stringify_keys
    sentences = parse_ordering_sentences(permitted[:sentences_json]) if ordering["format"] == Exercises::ExerciseContentValidator::MULTIPLE_SENTENCES_FORMAT
    result = Exercises::OrderingSubmission.call(
      activity_exercise: @activity_exercise,
      student: current_student,
      ordered_ids: permitted[:ordered_ids] || [],
      sentences:
    )
    @exercise_attempt = result.attempt
    redirect_to @exercise_attempt
  rescue Exercises::AttemptValidity::BlankResponse => error
    render_incomplete_submission(error.message, ordered_ids: permitted[:ordered_ids], sentences: sentences)
  rescue ActiveRecord::RecordNotFound, Pundit::NotAuthorizedError
    redirect_to root_path, alert: "Não foi possível enviar esta ordenação."
  rescue ActiveRecord::RecordInvalid
    redirect_to exercise_path(@activity_exercise.exercise, activity_exercise_id: @activity_exercise.id), alert: "Não foi possível registrar sua resposta."
  end

  # Reexibe o player com 422 e as respostas enviadas, sem criar tentativa nem expor o gabarito.
  def render_incomplete_submission(message, answers: nil, cells: nil, ordered_ids: nil, sentences: nil)
    @exercise = @activity_exercise.exercise
    attempt = ActivityResults.official_attempt(activity_exercise: @activity_exercise, student: current_student)
    @previous_official_attempt = attempt if attempt && policy(attempt).show?
    @prefilled_answers = answers.respond_to?(:to_h) ? answers.to_h.transform_values(&:to_s) : {}
    @prefilled_cells = cells.is_a?(Hash) ? cells : {}

    if @exercise.ordering?
      ordering = @exercise.object.deep_stringify_keys
      @ordering_instructions = ordering.fetch("instructions", "")
      if ordering["format"] == Exercises::ExerciseContentValidator::MULTIPLE_SENTENCES_FORMAT
        submitted = Array(sentences).grep(Hash).index_by { |sentence| sentence["id"] }
        @ordering_sentences = ordering_sentences_for_student(ordering).map do |sentence|
          sentence.merge("items" => restore_item_order(sentence["items"], submitted.dig(sentence["id"], "ordered_ids")))
        end
      else
        @ordering_items = restore_item_order(Array(ordering["items"]).shuffle, ordered_ids)
      end
    elsif @exercise.crossword?
      @crossword_payload = crossword_student_payload(@exercise.object)
    end

    flash.now[:alert] = message
    lookup_context.prefixes << "exercises"
    render "exercises/show", status: :unprocessable_entity
  end

  def restore_item_order(items, submitted_ids)
    known = Array(submitted_ids).filter_map { |id| items.find { |item| item["id"] == id } if id.is_a?(String) }.uniq
    known + (items - known)
  end

  def parse_ordering_sentences(serialized_sentences)
    JSON.parse(serialized_sentences)
  rescue JSON::ParserError, TypeError
    nil
  end

  def claim_memory_game_xp!(score)
    student_stat = StudentStat.find_or_create_by!(student: current_student)
    awarded = false
    student_stat.with_lock do
      prior_claim = ExerciseAttempt.where(
        student_id: current_student.id,
        activity_exercise_id: @exercise_attempt.activity_exercise_id
      ).where.not(id: @exercise_attempt.id).any? do |attempt|
        attempt.correct.to_h["xp_award_claimed"]
      end
      unless prior_claim
        student_stat.update!(xp: student_stat.xp + score) if score.positive?
        awarded = true
      end
    end
    awarded
  end

  def serialize_memory_game_card(card)
    return unless card
    return card if card["type"] == "word"

    exercise = @exercise_attempt.activity_exercise.exercise
    attachment = exercise.memory_images_attachments.find_by!(blob_id: card.fetch("blob_id"))
    { "id" => card.fetch("id"), "type" => "image", "url" => rails_blob_path(attachment.blob, only_path: true) }
  end

  def create_crossword_attempt
    permitted = params.require(:exercise_attempt).permit(:activity_exercise_id, :answer, :time_spent)
    @activity_exercise = ActivityExercise.active.find(permitted[:activity_exercise_id])
    authorize @activity_exercise, :show?

    answer = parse_crossword_answer(permitted[:answer])
    answer = sanitize_crossword_answer(@activity_exercise.exercise.object, answer)
    result = Exercises::CrosswordSubmission.call(
      activity_exercise: @activity_exercise,
      student: current_student,
      answer:,
      time_spent: permitted[:time_spent]
    )
    @exercise_attempt = result.attempt
    authorize @exercise_attempt

    redirect_to @exercise_attempt
  rescue Exercises::AttemptValidity::BlankResponse => error
    render_incomplete_submission(error.message, cells: answer&.dig("cells"))
  rescue JSON::ParserError, ActiveRecord::RecordNotFound, Pundit::NotAuthorizedError
    redirect_to root_path, alert: "Não foi possível enviar esta cruzadinha."
  rescue ActiveRecord::RecordInvalid
    redirect_to exercise_path(@activity_exercise.exercise, activity_exercise_id: @activity_exercise.id), alert: "Não foi possível registrar sua resposta."
  end

  def parse_crossword_answer(value)
    parsed = value.is_a?(String) ? JSON.parse(value) : JSON.parse(value.to_json)
    parsed.is_a?(Hash) ? parsed.deep_stringify_keys : {}
  end

  def sanitize_crossword_answer(layout, answer)
    grid = layout.deep_stringify_keys.fetch("grid").fetch("cells")
    allowed_cells = grid.each_with_index.flat_map do |row, row_index|
      row.each_with_index.filter_map { |cell, column_index| "#{row_index}-#{column_index}" if cell.present? }
    end
    submitted_cells = answer["cells"].is_a?(Hash) ? answer.fetch("cells") : {}
    cells = allowed_cells.to_h do |key|
      value = submitted_cells[key].to_s
      [ key, value.each_char.first.to_s ]
    end
    { "cells" => cells }
  end

  def authorized_next_activity_exercise
    candidate = ActivityExercises::NextExercise.call(activity_exercise: @exercise_attempt.activity_exercise)
    candidate if candidate && policy(candidate).show?
  end

  def set_exercise_attempt
    @exercise_attempt = ExerciseAttempt.active.find(params[:id])
  end

  def set_exercise_attempt_for_show
    @exercise_attempt = ExerciseAttempt.find(params[:id])
  end

  def attempt_result_summary
    exercise = @exercise_attempt.activity_exercise.exercise
    correct = @exercise_attempt.correct.to_h
    answer = @exercise_attempt.answer.to_h

    if exercise.memory_game?
      pair_ids = Array(correct["deck"]).filter_map { |card| card["pair_id"] if card.is_a?(Hash) }.uniq
      return if pair_ids.empty? || answer["matches"].nil?

      return { label: "Pares encontrados", unit_label: "pares encontrados", correct: answer["matches"].to_i, total: pair_ids.length }
    end

    statuses, unit_label = case exercise.exercise_type
    when "quiz"
      [ correct["questions"], "respostas corretas" ]
    when "fill_blanks"
      [ correct["blanks"], "lacunas corretas" ]
    when "ordering"
      if exercise.object.deep_stringify_keys["format"] == Exercises::ExerciseContentValidator::MULTIPLE_SENTENCES_FORMAT
        [ Array(correct["sentences"]).flat_map { |sentence| Array(sentence["positions"]) }, "palavras corretas" ]
      else
        [ correct["positions"], "itens corretos" ]
      end
    when "crossword"
      [ correct["statuses"]&.values, "palavras corretas" ]
    end
    statuses = statuses.is_a?(Hash) ? statuses.values : Array(statuses)
    return if statuses.empty?

    {
      label: "Respostas corretas",
      unit_label:,
      correct: statuses.count { |status| status.is_a?(Hash) ? status["correct"] == true : status == true },
      total: statuses.length
    }
  end

  def results_school_classes
    if current_teacher
      current_teacher.school_classes.active
    else
      current_student.school_classes.active.joins(:class_students)
        .where(classes_students: { student_id: current_student.id, active: true }).distinct
    end
  end

  def load_options
    @students = Student.active.order(:name)
    @activity_exercises = ActivityExercise.active.includes(:activity, :exercise).ordered
  end

  def exercise_attempt_params
    permitted = params.require(:exercise_attempt).permit(:activity_exercise_id, :answer, :time_spent)
    permitted[:answer] = JSON.parse(permitted[:answer]) if permitted[:answer].is_a?(String)
    permitted[:correct] = JSON.parse(permitted[:correct]) if permitted[:correct].is_a?(String)
    permitted
  rescue JSON::ParserError
    permitted.merge(answer: {}, correct: {})
  end
end
