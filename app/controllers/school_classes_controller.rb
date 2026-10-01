class SchoolClassesController < ApplicationController
  before_action :set_school_class, only: %i[show edit update destroy leave]

  def index
    authorize SchoolClass
    @school_classes = if current_teacher
      current_teacher.school_classes.active.includes(:teacher).order(:name)
    else
      current_student.school_classes.joins(:class_students).where(classes_students: { student_id: current_student.id, active: true }).active.includes(:teacher).order(:name)
    end
  end

  def show
    authorize @school_class
    @class_students = @school_class.class_students.active.includes(:student).order(:id)
    @activities = @school_class.activities.active.includes(activity_exercises: :exercise).then do |activities|
      current_teacher ? activities : activities.published
    end
    return unless current_teacher

    @available_exercises = current_teacher.exercises.active.order(:title)
  end

  def new
    @school_class = SchoolClass.new
    authorize @school_class
  end

  def create
    @school_class = current_teacher.school_classes.build(school_class_params)
    authorize @school_class
    return redirect_to @school_class if @school_class.save

    render :new, status: :unprocessable_entity
  end

  def edit; authorize @school_class; end

  def update
    authorize @school_class
    return redirect_to @school_class if @school_class.update(school_class_params)

    render :edit, status: :unprocessable_entity
  end

  def destroy
    authorize @school_class
    @school_class.update!(active: false)
    redirect_to school_classes_path, notice: "Turma desativada."
  end

  def join
    authorize SchoolClass, :join?
    school_class = SchoolClass.active.find_by(access_code: params[:access_code])
    if school_class && ClassStudent.find_or_initialize_by(student: current_student, school_class: school_class).update(active: true)
      redirect_to school_classes_path, notice: "Você entrou na turma."
    else
      redirect_to school_classes_path, alert: "Código de turma inválido."
    end
  end

  def leave
    authorize @school_class
    membership = @school_class.class_students.active.find_by(student: current_student)
    if membership
      authorize membership, :destroy?
      membership.update!(active: false)
    end
    redirect_to school_classes_path, notice: "Você saiu da turma."
  end

  private

  def set_school_class
    @school_class = SchoolClass.active.find(params[:id])
  end

  def school_class_params
    params.require(:school_class).permit(:name, :description, :xp_points)
  end
end
