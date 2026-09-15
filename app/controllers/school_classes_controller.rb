class SchoolClassesController < ApplicationController
  before_action :set_school_class, only: %i[show edit update destroy]

  def index
    @school_classes = SchoolClass.active.includes(:teacher).order(:name)
  end

  def show; end

  def new
    @school_class = SchoolClass.new
    @teachers = Teacher.active.order(:name)
  end

  def create
    @school_class = SchoolClass.new(school_class_params)
    return redirect_to @school_class if @school_class.save

    @teachers = Teacher.active.order(:name)
    render :new, status: :unprocessable_entity
  end

  def edit
    @teachers = Teacher.active.order(:name)
  end

  def update
    return redirect_to @school_class if @school_class.update(school_class_params)

    @teachers = Teacher.active.order(:name)
    render :edit, status: :unprocessable_entity
  end

  def destroy
    @school_class.update!(active: false)
    redirect_to school_classes_path, notice: "Turma desativada."
  end

  private

  def set_school_class
    @school_class = SchoolClass.active.find(params[:id])
  end

  def school_class_params
    params.require(:school_class).permit(:teacher_id, :name, :description, :xp_points)
  end
end
