class ClassStudentsController < ApplicationController
  before_action :set_class_student, only: %i[show edit update destroy]

  def index
    authorize ClassStudent
    @class_students = ClassStudent.active.joins(:school_class).where(classes: { teacher_id: current_teacher.id, active: true }).includes(:student, :school_class).order(:id)
  end

  def show; authorize @class_student; end

  def new
    @class_student = ClassStudent.new
    authorize @class_student
    load_options
  end

  def create
    authorize ClassStudent, :create?
    permitted = class_student_params
    school_class = current_teacher.school_classes.active.find(permitted[:class_id])
    student = Student.active.find(permitted[:student_id])
    @class_student = school_class.class_students.build(student:)
    authorize @class_student, :create?
    return redirect_to @class_student if @class_student.save

    load_options
    render :new, status: :unprocessable_entity
  rescue ActiveRecord::RecordNotFound
    redirect_to root_path, alert: "Turma ou aluno inválido."
  end

  def edit
    authorize @class_student
    load_options
  end

  def update
    authorize @class_student
    permitted = class_student_params
    school_class = current_teacher.school_classes.active.find(permitted[:class_id])
    student = Student.active.find(permitted[:student_id])
    @class_student.assign_attributes(school_class:, student:)
    authorize @class_student
    return redirect_to @class_student if @class_student.save

    load_options
    render :edit, status: :unprocessable_entity
  rescue ActiveRecord::RecordNotFound
    redirect_to root_path, alert: "Turma ou aluno inválido."
  end

  def destroy
    authorize @class_student
    @class_student.update!(active: false)
    redirect_to class_students_path, notice: "Matrícula desativada."
  end

  private

  def set_class_student
    @class_student = ClassStudent.active.find(params[:id])
  end

  def load_options
    @students = Student.active.order(:name)
    @school_classes = current_teacher.school_classes.active.order(:name)
  end

  def class_student_params
    params.require(:class_student).permit(:student_id, :class_id)
  end
end
