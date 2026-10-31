class ActivitiesController < ApplicationController
  before_action :set_activity, only: %i[show edit update destroy]

  def index
    return redirect_to school_classes_path if current_student

    authorize Activity
    @activities = current_teacher.activities.active.includes(:school_class, :teacher).order(:title)
  end

  def show
    authorize @activity
    @activity_exercises = @activity.activity_exercises.active.joins(:exercise).merge(Exercise.active).ordered.includes(:exercise)
    @lesson_completed = ActivityResults.lesson_completed?(activity: @activity, student: current_student) if current_student
    return unless current_teacher

    @available_exercises = current_teacher.exercises.active
                                          .where.not(id: @activity.activity_exercises.active.select(:exercise_id))
                                          .order(:title)
    @activity_exercise = @activity.activity_exercises.build(position: next_position, points: 0, exercise_id: preselected_exercise_id)
  end

  def new
    @activity = Activity.new(class_id: source_school_class&.id)
    authorize @activity
    load_options
  end

  def create
    authorize Activity, :create?
    @activity = current_teacher.activities.build(activity_params)
    authorize @activity
    @activity.class_id = nil unless owned_active_class?(@activity.class_id)
    return redirect_to @activity if @activity.save

    load_options
    render :new, status: :unprocessable_entity
  end

  def edit
    authorize @activity
    load_options
  end

  def update
    authorize @activity
    @activity.assign_attributes(activity_params)
    if allowed_class_change?
      return redirect_to @activity if @activity.save
    else
      @activity.errors.add(:class_id, "inválida")
    end

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

  def activity_params
    params.require(:activity).permit(:class_id, :title, :published)
  end

  # Conveniência visual: ignora silenciosamente turmas inexistentes, inativas ou de outros professores.
  def source_school_class
    return unless current_teacher && params[:class_id].present?

    current_teacher.school_classes.active.find_by(id: params[:class_id])
  end

  def owned_active_class?(class_id)
    class_id.present? && current_teacher.school_classes.active.exists?(id: class_id)
  end

  # Mantém a turma atual ou aceita apenas outra turma ativa do próprio professor.
  def allowed_class_change?
    !@activity.class_id_changed? || owned_active_class?(@activity.class_id)
  end

  def next_position
    @activity_exercises.size + 1
  end

  # Conveniência visual: só pré-seleciona exercício ativo do professor ainda não associado à aula.
  def preselected_exercise_id
    return if params[:exercise_id].blank?

    exercise = @available_exercises.find_by(id: params[:exercise_id])
    return if exercise.nil? || @activity.activity_exercises.active.exists?(exercise_id: exercise.id)

    exercise.id
  end
end
