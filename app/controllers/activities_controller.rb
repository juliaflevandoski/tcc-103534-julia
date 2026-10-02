class ActivitiesController < ApplicationController
  before_action :set_activity, only: %i[show edit update destroy]

  def index
    return redirect_to school_classes_path if current_student

    authorize Activity
    @activities = current_teacher.activities.active.includes(:school_class, :teacher).order(:title)
  end

  def show
    authorize @activity
    @activity_exercises = @activity.activity_exercises.active.ordered.includes(:exercise)
    return unless current_teacher

    @available_exercises = current_teacher.exercises.active.order(:title)
    @activity_exercise = @activity.activity_exercises.build(position: next_position, points: 0)
  end

  def new
    @activity = Activity.new
    authorize @activity
    load_options
  end

  def create
    @activity = current_teacher.activities.build(activity_params)
    authorize @activity
    return redirect_to @activity if @activity.save

    load_options
    render :new, status: :unprocessable_entity
  end

  def edit
    authorize @activity
    load_options
    load_exercise_options
  end

  def update
    authorize @activity
    return redirect_to @activity if @activity.update(activity_params)

    load_options
    render :edit, status: :unprocessable_entity
  end

  def destroy
    authorize @activity
    @activity.update!(active: false)
    redirect_to activities_path, notice: "Aula desativada."
  end

  private

  def set_activity
    @activity = Activity.active.find(params[:id])
  end

  def load_options
    @school_classes = current_teacher.school_classes.active.order(:name)
  end

  def load_exercise_options
    @activity_exercises = @activity.activity_exercises.active.ordered.includes(:exercise)
    @available_exercises = current_teacher.exercises.active.order(:title)
    @activity_exercise = @activity.activity_exercises.build(position: next_position, points: 0)
  end

  def activity_params
    params.require(:activity).permit(:class_id, :title, :published)
  end

  def next_position
    @activity.activity_exercises.active.maximum(:position).to_i + 1
  end
end
