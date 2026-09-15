class ExerciseAttemptsController < ApplicationController
  before_action :set_exercise_attempt, only: %i[show edit update destroy]

  def index
    @exercise_attempts = ExerciseAttempt.active.includes(:student, :activity_exercise).order(created_at: :desc)
  end

  def show; end

  def new
    @exercise_attempt = ExerciseAttempt.new(answer: {}, correct: {})
    load_options
  end

  def create
    @exercise_attempt = ExerciseAttempt.new(exercise_attempt_params)
    return redirect_to @exercise_attempt if @exercise_attempt.save

    load_options
    render :new, status: :unprocessable_entity
  end

  def edit
    load_options
  end

  def update
    return redirect_to @exercise_attempt if @exercise_attempt.update(exercise_attempt_params)

    load_options
    render :edit, status: :unprocessable_entity
  end

  def destroy
    @exercise_attempt.update!(active: false)
    redirect_to exercise_attempts_path, notice: "Tentativa desativada."
  end

  private

  def set_exercise_attempt
    @exercise_attempt = ExerciseAttempt.active.find(params[:id])
  end

  def load_options
    @students = Student.active.order(:name)
    @activity_exercises = ActivityExercise.active.includes(:activity, :exercise).ordered
  end

  def exercise_attempt_params
    permitted = params.require(:exercise_attempt).permit(:student_id, :activity_exercise_id, :answer, :correct,
                                                         :score, :time_spent)
    permitted[:answer] = JSON.parse(permitted[:answer]) if permitted[:answer].is_a?(String)
    permitted[:correct] = JSON.parse(permitted[:correct]) if permitted[:correct].is_a?(String)
    permitted
  rescue JSON::ParserError
    permitted.merge(answer: {}, correct: {})
  end
end
