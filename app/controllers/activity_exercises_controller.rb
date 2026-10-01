class ActivityExercisesController < ApplicationController
  before_action :set_activity_exercise, only: %i[show edit update destroy]

  def index
    authorize ActivityExercise
    @activity_exercises = ActivityExercise.active.includes(:activity, :exercise).ordered
  end

  def show; authorize @activity_exercise; end

  def new
    @activity_exercise = ActivityExercise.new
    authorize @activity_exercise
    load_options
  end

  def create
    @activity = current_teacher.activities.active.find(activity_exercise_params[:activity_id])
    exercise = current_teacher.exercises.active.find(activity_exercise_params[:exercise_id])
    @activity_exercise = @activity.activity_exercises.build(activity_exercise_params.except(:activity_id, :position))
    @activity_exercise.exercise = exercise
    @activity_exercise.position = @activity.activity_exercises.active.maximum(:position).to_i + 1
    authorize @activity_exercise
    return redirect_to @activity if @activity_exercise.save

    redirect_to @activity, alert: @activity_exercise.errors.full_messages.to_sentence
  rescue ActiveRecord::RecordNotFound
    redirect_to activities_path, alert: "Aula ou exercício inválido."
  end

  def reorder
    activity = current_teacher.activities.active.find(params[:activity_id])
    authorize activity, :update?
    success = ActivityExercises::Reorder.call(activity:, ordered_ids: params[:ordered_ids])

    respond_to do |format|
      format.json { render json: { data: success ? { positions: "updated" } : nil, errors: success ? [] : [ { message: "Ordem inválida" } ] }, status: success ? :ok : :unprocessable_entity }
      format.html { redirect_to activity_path(activity), alert: success ? nil : "Não foi possível reordenar os exercícios." }
    end
  rescue ActiveRecord::RecordNotFound
    render json: { data: nil, errors: [ { message: "Aula inválida" } ] }, status: :not_found
  end

  def edit
    authorize @activity_exercise
    load_options
  end

  def update
    authorize @activity_exercise
    return redirect_to @activity_exercise if @activity_exercise.update(activity_exercise_params)

    load_options
    render :edit, status: :unprocessable_entity
  end

  def destroy
    authorize @activity_exercise
    activity = @activity_exercise.activity
    @activity_exercise.update!(active: false)
    redirect_to activity, notice: "Exercício removido da aula."
  end

  private

  def set_activity_exercise
    @activity_exercise = ActivityExercise.active.find(params[:id])
  end

  def load_options
    @activities = current_teacher.activities.active.order(:title)
    @exercises = current_teacher.exercises.active.order(:title)
  end

  def activity_exercise_params
    params.require(:activity_exercise).permit(:activity_id, :exercise_id, :position, :points)
  end
end
