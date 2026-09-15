class ClassStudentsController < ApplicationController
  before_action :set_class_student, only: %i[show edit update destroy]

  def index
    @class_students = ClassStudent.active.includes(:student, :school_class).order(:id)
  end

  def show; end

  def new
    @class_student = ClassStudent.new
    load_options
  end

  def create
    @class_student = ClassStudent.new(class_student_params)
    return redirect_to @class_student if @class_student.save

    load_options
    render :new, status: :unprocessable_entity
  end

  def edit
    load_options
  end

  def update
    return redirect_to @class_student if @class_student.update(class_student_params)

    load_options
    render :edit, status: :unprocessable_entity
  end

  def destroy
    @class_student.update!(active: false)
    redirect_to class_students_path, notice: "Matrícula desativada."
  end

  private

  def set_class_student
    @class_student = ClassStudent.active.find(params[:id])
  end

  def load_options
    @students = Student.active.order(:name)
    @school_classes = SchoolClass.active.order(:name)
  end

  def class_student_params
    params.require(:class_student).permit(:student_id, :class_id)
  end
end
