class TeachersController < ApplicationController
  before_action :set_teacher, only: %i[show edit update destroy]

  def index
    @teachers = Teacher.active.order(:name)
  end

  def show; end

  def new
    @teacher = Teacher.new
  end

  def create
    @teacher = Teacher.new(teacher_params)
    return redirect_to @teacher if @teacher.save

    render :new, status: :unprocessable_entity
  end

  def edit; end

  def update
    return redirect_to @teacher if @teacher.update(teacher_params)

    render :edit, status: :unprocessable_entity
  end

  def destroy
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
