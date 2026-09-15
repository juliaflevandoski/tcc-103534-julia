class ActivitiesController < ApplicationController
  before_action :set_activity, only: %i[show edit update destroy]

  def index
    @activities = Activity.active.includes(:school_class, :teacher).order(:title)
  end

  def show; end

  def new
    @activity = Activity.new
    load_options
  end

  def create
    @activity = Activity.new(activity_params)
    return redirect_to @activity if @activity.save

    load_options
    render :new, status: :unprocessable_entity
  end

  def edit
    load_options
  end

  def update
    return redirect_to @activity if @activity.update(activity_params)

    load_options
    render :edit, status: :unprocessable_entity
  end

  def destroy
    @activity.update!(active: false)
    redirect_to activities_path, notice: "Aula desativada."
  end

  private

  def set_activity
    @activity = Activity.active.find(params[:id])
  end

  def load_options
    @school_classes = SchoolClass.active.includes(:teacher).order(:name)
    @teachers = Teacher.active.order(:name)
  end

  def activity_params
    params.require(:activity).permit(:class_id, :teacher_id, :title, :published)
  end
end
