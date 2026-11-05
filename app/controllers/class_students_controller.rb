class ClassStudentsController < ApplicationController
  before_action :set_class_student, only: %i[show edit update destroy]

  def index
    authorize ClassStudent
    scope = ClassStudent.active.joins(:school_class).where(classes: { teacher_id: current_teacher.id, active: true })
    if params.key?(:class_id)
      school_class = context_school_class
      return redirect_to school_classes_path, alert: "Turma inválida ou sem permissão de acesso." unless school_class

      scope = scope.where(class_id: school_class.id)
    end
    @class_students = scope.includes(:student, :school_class).order(:id)
  end

  def show; authorize @class_student; end

  def new
    @class_student = ClassStudent.new(class_id: context_school_class&.id)
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
    return redirect_to saved_class_student_path if @class_student.save

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
    return redirect_to saved_class_student_path if @class_student.save

    load_options
    render :edit, status: :unprocessable_entity
  rescue ActiveRecord::RecordNotFound
    redirect_to root_path, alert: "Turma ou aluno inválido."
  end

  def destroy
    authorize @class_student
    @class_student.update!(active: false)
    redirect_to class_students_path(class_id: (@class_student.class_id if context_school_class)), notice: "Matrícula desativada."
  end

  private

  # Só aceita um identificador escalar numérico e apenas entre as turmas ativas do professor.
  def context_school_class
    return @context_school_class if defined?(@context_school_class)

    raw_id = params[:class_id]
    @context_school_class =
      if current_teacher && raw_id.is_a?(String) && raw_id.match?(/\A\d+\z/)
        current_teacher.school_classes.active.find_by(id: raw_id)
      end
  end
  helper_method :context_school_class

  # Com contexto válido, acompanha a turma em que a matrícula foi efetivamente salva.
  def saved_class_student_path
    class_student_path(@class_student, class_id: (@class_student.class_id if context_school_class))
  end

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
