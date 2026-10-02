class TeachersController < ApplicationController
  before_action :set_teacher, only: %i[show edit update destroy]

  def index
    authorize Teacher
    @teachers = Teacher.active.where(id: current_teacher.id).order(:name)
  end

  def show; authorize @teacher; end

  def new
    @teacher = Teacher.new
    authorize @teacher
  end

  def create
    @teacher = Teacher.new(teacher_params)
    authorize @teacher
    return redirect_to @teacher if @teacher.save

    render :new, status: :unprocessable_entity
  end

  def edit; authorize @teacher; end

  def update
    authorize @teacher
    return redirect_to @teacher if @teacher.update(teacher_params)

    render :edit, status: :unprocessable_entity
  end

  def destroy
    authorize @teacher
    @teacher.update!(active: false)
    redirect_to teachers_path, notice: "Professor desativado."
  end

  private

  def set_teacher
    @teacher = Teacher.active.find(params[:id])
  end

  def teacher_params
    params.require(:teacher).permit(:username, :email, :password, :password_confirmation, :name)
  end
end
