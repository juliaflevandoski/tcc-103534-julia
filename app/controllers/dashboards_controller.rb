class DashboardsController < ApplicationController
  def show
    authorize :dashboard
    return show_student if current_student

    @school_classes = current_teacher.school_classes.active.order(:name, :id).to_a
    if params[:school_class_id].present?
      @selected_school_class = @school_classes.find { |school_class| school_class.id.to_s == params[:school_class_id].to_s }
      return redirect_to root_path, alert: "Turma inválida." if @selected_school_class.nil?
    else
      @selected_school_class = @school_classes.first
    end

    return unless @selected_school_class

    # Uma consulta por tabela, restrita às turmas do professor; o Stimulus reaproveita estes dados sem novas requisições.
    all_activities = Activity.active.where(class_id: @school_classes.map(&:id)).order(:created_at, :id).to_a
    all_links = ActivityExercise.active
      .joins(:exercise)
      .where(exercises: { active: true }, activity_id: all_activities.map(&:id))
      .includes(:exercise, :activity)
      .order(:activity_id, :position, :id).to_a

    @activities = all_activities.select { |activity| activity.class_id == @selected_school_class.id }
    if params[:activity_id].present?
      @selected_activity = @activities.find { |activity| activity.id.to_s == params[:activity_id].to_s }
      return redirect_to root_path, alert: "Aula inválida." if @selected_activity.nil?
    end

    activity_ids = (@selected_activity ? [ @selected_activity ] : @activities).map(&:id)
    @activity_exercises = all_links.select { |link| activity_ids.include?(link.activity_id) }
    if params[:activity_exercise_id].present?
      @selected_activity_exercise = @activity_exercises.find { |link| link.id.to_s == params[:activity_exercise_id].to_s }
      return redirect_to root_path, alert: "Exercício inválido." if @selected_activity_exercise.nil?
    end

    all_students = ClassStudent.active.joins(:student)
      .where(class_id: @school_classes.map(&:id), students: { active: true })
      .includes(:student).to_a
      .sort_by { |enrollment| [ enrollment.student.name.to_s.downcase, enrollment.student_id ] }
    @students = all_students.select { |enrollment| enrollment.class_id == @selected_school_class.id }.map(&:student)
    if params[:student_id].present?
      @selected_student = @students.find { |student| student.id.to_s == params[:student_id].to_s }
      return redirect_to root_path, alert: "Aluno inválido." if @selected_student.nil?
    end

    @filter_options = @school_classes.to_h do |school_class|
      class_activities = all_activities.select { |activity| activity.class_id == school_class.id }
      class_links = all_links.select { |link| class_activities.any? { |activity| activity.id == link.activity_id } }
      [ school_class.id, {
        students: all_students.select { |enrollment| enrollment.class_id == school_class.id }.map { |enrollment| { id: enrollment.student_id, label: enrollment.student.name } },
        activities: class_activities.map { |activity| { id: activity.id, label: activity.published? ? activity.title : "#{activity.title} (rascunho)" } },
        exercises: class_links.map { |link| { id: link.id, activityId: link.activity_id, label: "#{link.exercise.title} — #{link.activity.title}" } }
      } ]
    end

    @dashboard = TeacherDashboard.call(teacher: current_teacher, school_class: @selected_school_class, activity: @selected_activity, activity_exercise: @selected_activity_exercise, student: @selected_student)
  end

  private

  # O aluno só enxerga turmas ativas com matrícula ativa; nenhum ID de aluno vem da requisição.
  def show_student
    @school_classes = current_student.school_classes.active.joins(:class_students)
      .where(classes_students: { student_id: current_student.id, active: true }).distinct.order(:name, :id).to_a
    if params[:school_class_id].present?
      @selected_school_class = @school_classes.find { |school_class| school_class.id.to_s == params[:school_class_id].to_s }
      return redirect_to root_path, alert: "Turma inválida." if @selected_school_class.nil?
    end

    @dashboard = StudentDashboard.call(student: current_student, school_classes: @selected_school_class ? [ @selected_school_class ] : @school_classes)
    @level_info = StudentLevel.call(current_student.student_stat&.xp)
    @series = OfficialAttemptSeries.call(user: current_student, school_classes: @selected_school_class ? [ @selected_school_class ] : @school_classes)
    render :student
  end
end
