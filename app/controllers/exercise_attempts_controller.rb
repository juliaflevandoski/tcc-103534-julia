class ExerciseAttemptsController < ApplicationController
  before_action :set_exercise_attempt, only: %i[show edit update destroy memory_game_turn]

  def index
    authorize ExerciseAttempt
    attempts = ExerciseAttempt.active
    attempts = if current_teacher
      attempts.joins(activity_exercise: :activity).where(activities: { teacher_id: current_teacher.id })
    else
      attempts.where(student_id: current_student.id)
    end
    @exercise_attempts = attempts.includes(:student, :activity_exercise).order(created_at: :desc)
  end

  def show; authorize @exercise_attempt; end

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
    @activity_exercise.exercise.validate!
    game = Exercises::MemoryGamePlay.start(
      object: @activity_exercise.exercise.object,
      points: @activity_exercise.points,
      attached_image_blob_ids: @activity_exercise.exercise.memory_images_attachments.pluck(:blob_id)
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
    redirect_to exercise_path(@activity_exercise.exercise, activity_exercise_id: @activity_exercise.id), alert: error.message
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
    redirect_to exercise_path(@activity_exercise.exercise, activity_exercise_id: @activity_exercise.id), alert: error.message
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
    permitted = params.require(:exercise_attempt).permit(:activity_exercise_id, ordered_ids: [])
    @activity_exercise = ActivityExercise.active.includes(:activity, :exercise).find(permitted[:activity_exercise_id])
    authorize @activity_exercise, :show?
    result = Exercises::OrderingSubmission.call(
      activity_exercise: @activity_exercise,
      student: current_student,
      ordered_ids: permitted[:ordered_ids] || []
    )
    @exercise_attempt = result.attempt
    redirect_to @exercise_attempt
  rescue Exercises::AttemptValidity::BlankResponse => error
    redirect_to exercise_path(@activity_exercise.exercise, activity_exercise_id: @activity_exercise.id), alert: error.message
  rescue ActiveRecord::RecordNotFound, Pundit::NotAuthorizedError
    redirect_to root_path, alert: "Não foi possível enviar esta ordenação."
  rescue ActiveRecord::RecordInvalid
    redirect_to exercise_path(@activity_exercise.exercise, activity_exercise_id: @activity_exercise.id), alert: "Não foi possível registrar sua resposta."
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
    redirect_to exercise_path(@activity_exercise.exercise, activity_exercise_id: @activity_exercise.id), alert: error.message
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

  def set_exercise_attempt
    @exercise_attempt = ExerciseAttempt.active.find(params[:id])
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
