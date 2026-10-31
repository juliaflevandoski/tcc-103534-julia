class ActivityExercisesController < ApplicationController
  before_action :set_activity_exercise, only: %i[show edit update destroy]

  def index
    authorize ActivityExercise
    @activity_exercises = ActivityExercise.active
      .joins(:activity).where(activities: { teacher_id: current_teacher.id })
      .includes(:activity, :exercise).ordered
  end

  def show; authorize @activity_exercise; end

  def new
    @activity_exercise = ActivityExercise.new
    authorize @activity_exercise
    load_options
  end

  def create
    authorize ActivityExercise
    @activity = current_teacher.activities.active.find(activity_exercise_params[:activity_id])
    exercise = current_teacher.exercises.active.find(activity_exercise_params[:exercise_id])
    @activity_exercise = @activity.activity_exercises.build(activity_exercise_params.except(:activity_id, :position))
    @activity_exercise.exercise = exercise
    authorize @activity_exercise
    return redirect_to @activity if ActivityExercises::Append.call(@activity_exercise)

    redirect_to @activity, alert: @activity_exercise.errors.full_messages.to_sentence
  rescue ActiveRecord::RecordNotFound
    redirect_to activities_path, alert: "Aula ou exercício inválido."
  end

  def reorder
    authorize Activity, :create?
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
    @activity_exercise.assign_attributes(authorized_update_params)
    return redirect_to @activity_exercise if @activity_exercise.save

    load_options
    render :edit, status: :unprocessable_entity
  rescue ActiveRecord::RecordNotFound
    redirect_to activities_path, alert: "Aula ou exercício inválido."
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

  # Destinos alterados precisam ser aula e exercício ativos do professor autenticado.
  def authorized_update_params
    permitted = activity_exercise_params
    if permitted.key?(:activity_id) && permitted[:activity_id].to_s != @activity_exercise.activity_id.to_s
      permitted[:activity_id] = current_teacher.activities.active.find(permitted[:activity_id]).id
    end
    if permitted.key?(:exercise_id) && permitted[:exercise_id].to_s != @activity_exercise.exercise_id.to_s
      permitted[:exercise_id] = current_teacher.exercises.active.find(permitted[:exercise_id]).id
    end
    permitted
  end

  def activity_exercise_params
    params.require(:activity_exercise).permit(:activity_id, :exercise_id, :position, :points)
  end
end
