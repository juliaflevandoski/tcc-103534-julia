class ActivityExercisesController < ApplicationController
  before_action :set_activity_exercise, only: %i[show edit update destroy]

  def index
    @activity_exercises = ActivityExercise.active.includes(:activity, :exercise).ordered
  end

  def show; end

  def new
    @activity_exercise = ActivityExercise.new
    load_options
  end

  def create
    @activity_exercise = ActivityExercise.new(activity_exercise_params)
    return redirect_to @activity_exercise if @activity_exercise.save

    load_options
    render :new, status: :unprocessable_entity
  end

  def edit
    load_options
  end

  def update
    return redirect_to @activity_exercise if @activity_exercise.update(activity_exercise_params)

    load_options
    render :edit, status: :unprocessable_entity
  end

  def destroy
    @activity_exercise.update!(active: false)
    redirect_to activity_exercises_path, notice: "Exercício removido da aula."
  end

  private

  def set_activity_exercise
    @activity_exercise = ActivityExercise.active.find(params[:id])
  end

  def load_options
    @activities = Activity.active.order(:title)
    @exercises = Exercise.active.order(:title)
  end

  def activity_exercise_params
    params.require(:activity_exercise).permit(:activity_id, :exercise_id, :position, :points)
  end
end
