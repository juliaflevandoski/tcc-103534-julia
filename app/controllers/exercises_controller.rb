class ExercisesController < ApplicationController
  before_action :set_exercise, only: %i[show edit update destroy]

  def index
    @exercises = Exercise.active.includes(:teacher).order(:title)
  end

  def show; end

  def new
    @exercise = Exercise.new(object: {})
    load_options
  end

  def create
    @exercise = Exercise.new(exercise_params)
    return redirect_to @exercise if @exercise.save

    load_options
    render :new, status: :unprocessable_entity
  end

  def edit
    load_options
  end

  def update
    return redirect_to @exercise if @exercise.update(exercise_params)

    load_options
    render :edit, status: :unprocessable_entity
  end

  def destroy
    @exercise.update!(active: false)
    redirect_to exercises_path, notice: "Exercício desativado."
  end

  private

  def set_exercise
    @exercise = Exercise.active.find(params[:id])
  end

  def load_options
    @teachers = Teacher.active.order(:name)
  end

  def exercise_params
    permitted = params.require(:exercise).permit(:teacher_id, :exercise_type, :title, :description, :object)
    permitted[:object] = JSON.parse(permitted[:object]) if permitted[:object].is_a?(String)
    permitted
  rescue JSON::ParserError
    params.require(:exercise).permit(:teacher_id, :exercise_type, :title, :description).merge(object: {})
  end
end
