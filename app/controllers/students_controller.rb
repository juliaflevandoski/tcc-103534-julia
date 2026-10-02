class StudentsController < ApplicationController
  before_action :set_student, only: %i[show edit update destroy]

  def index
    authorize Student
    @students = Student.active.where(id: current_student.id).order(:name)
  end

  def show; authorize @student; end

  def new
    @student = Student.new
    authorize @student
  end

  def create
    @student = Student.new(student_params)
    authorize @student
    return redirect_to @student if @student.save

    render :new, status: :unprocessable_entity
  end

  def edit; authorize @student; end

  def update
    authorize @student
    return redirect_to @student if @student.update(student_params)

    render :edit, status: :unprocessable_entity
  end

  def destroy
    authorize @student
    @student.update!(active: false)
    redirect_to students_path, notice: "Aluno desativado."
  end

  private

  def set_student
    @student = Student.active.find(params[:id])
  end

  def student_params
    params.require(:student).permit(:username, :email, :password, :password_confirmation, :name)
  end
end
