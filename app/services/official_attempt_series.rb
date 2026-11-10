# Prepara séries semanais a partir das tentativas oficiais (primeira tentativa válida por aluno e vínculo).
#
# Só usa dados que têm data real: o created_at da tentativa oficial. No jogo da memória,
# essa data pode anteceder a conclusão da partida. Matrícula, publicação e
# conclusão de aula não têm histórico, então nenhuma data é inferida para elas; os vínculos,
# aulas, turmas e alunos considerados são os atualmente elegíveis segundo o ResultsDashboard.
# Tentativas oficiais posteriormente desativadas continuam contando, como em ActivityResults.
#
# Semanas: segunda a domingo, no fuso da aplicação (Time.zone). Todas as séries compartilham o
# mesmo eixo contínuo, da primeira à última semana com tentativa oficial, e semanas vazias
# aparecem com contagens 0 e médias nil (nunca 0% de nota).
#
# Significado das métricas de cada semana (Week):
# - attempts_count: tentativas oficiais criadas na semana (cada vínculo por aluno conta uma vez).
# - distinct_students_count: alunos distintos com ao menos uma tentativa oficial na semana.
#   Não é taxa de participação, pois não há histórico de matrículas.
# - average: média simples dos percentuais oficiais das tentativas da semana (nil sem notas).
# - cumulative_average: média simples de todos os percentuais oficiais da primeira semana até
#   esta, em conjunto (não é a média das médias semanais). Semanas vazias repetem o último valor
#   acumulado; antes da primeira nota é nil. A média por tentativa pode diferir da média
#   das médias individuais exibida no dashboard do professor.
# - cumulative_attempts_count: total acumulado de tentativas oficiais.
class OfficialAttemptSeries
  Week = Struct.new(
    :week_start, :attempts_count, :cumulative_attempts_count, :distinct_students_count,
    :rated_count, :average, :cumulative_average,
    keyword_init: true
  )
  ClassSeries = Struct.new(:school_class, :weeks, keyword_init: true)
  Result = Struct.new(:weeks, :classes, keyword_init: true)

  Point = Struct.new(:class_id, :student_id, :week_start, :percentage)

  def self.call(user:, school_classes:, student: nil, activity: nil, activity_exercise: nil)
    new(user:, school_classes:, student:, activity:, activity_exercise:).call
  end

  def initialize(user:, school_classes:, student: nil, activity: nil, activity_exercise: nil)
    @user = user
    @school_classes = Array(school_classes)
    @student = student
    @activity = activity
    @activity_exercise = activity_exercise
    validate!
  end

  def call
    points_by_class = @school_classes.to_h { |school_class| [ school_class.id, points_for(school_class) ] }
    all_points = points_by_class.values.flatten
    axis = week_axis(all_points)

    Result.new(
      weeks: build_weeks(all_points, axis),
      classes: @school_classes.map do |school_class|
        ClassSeries.new(school_class:, weeks: build_weeks(points_by_class.fetch(school_class.id), axis))
      end
    )
  end

  private

  def teacher?
    @user.is_a?(Teacher)
  end

  def validate!
    raise ArgumentError, "Usuário inválido" unless teacher? || @user.is_a?(Student)

    if teacher?
      unless @school_classes.all? { |school_class| school_class.active? && school_class.teacher_id == @user.id }
        raise ArgumentError, "Turma não pertence ao professor"
      end
    else
      raise ArgumentError, "Aluno só pode consultar os próprios dados" if @student && @student.id != @user.id

      enrolled_ids = ClassStudent.active.where(student_id: @user.id, class_id: @school_classes.map(&:id)).pluck(:class_id)
      unless @school_classes.all? { |school_class| school_class.active? && enrolled_ids.include?(school_class.id) }
        raise ArgumentError, "Turma sem matrícula ativa do aluno"
      end
    end

    class_ids = @school_classes.map(&:id)
    if @activity && (!@activity.is_a?(Activity) || !@activity.persisted? ||
        !Activity.active.where(id: @activity.id, class_id: class_ids).exists?)
      raise ArgumentError, "Aula inválida para as turmas autorizadas"
    end
    if @activity_exercise
      links = ActivityExercise.active.joins(:activity, :exercise)
        .where(activities: { active: true, class_id: class_ids }, exercises: { active: true })
      links = links.where(activity_id: @activity.id) if @activity
      unless @activity_exercise.is_a?(ActivityExercise) && @activity_exercise.persisted? &&
          links.exists?(id: @activity_exercise.id)
        raise ArgumentError, "Vínculo inválido para as turmas ou aula autorizadas"
      end
    end
  end

  def points_for(school_class)
    data = ResultsDashboard.call(user: @user, school_class:)
    if @student && data.fetch(:students).none? { |student| student.id == @student.id }
      raise ArgumentError, "Aluno sem matrícula ativa na turma"
    end

    data.fetch(:activities).flat_map do |activity_result|
      next [] if @activity && activity_result.fetch(:activity).id != @activity.id

      activity_result.fetch(:exercises).flat_map do |exercise_result|
        next [] if @activity_exercise && exercise_result.fetch(:activity_exercise).id != @activity_exercise.id

        exercise_result.fetch(:official_by_student).filter_map do |student_id, attempt|
          next if @student && student_id != @student.id

          Point.new(
            school_class.id,
            student_id,
            attempt.created_at.in_time_zone.to_date.beginning_of_week,
            exercise_result.fetch(:percentage_by_student)[student_id]
          )
        end
      end
    end
  end

  def week_axis(points)
    return [] if points.empty?

    first, last = points.map(&:week_start).minmax
    (first..last).step(7).to_a
  end

  def build_weeks(points, axis)
    by_week = points.group_by(&:week_start)
    cumulative_attempts = 0
    cumulative_sum = 0.0
    cumulative_rated = 0

    axis.map do |week_start|
      week_points = by_week.fetch(week_start, [])
      percentages = week_points.filter_map(&:percentage)
      cumulative_attempts += week_points.length
      cumulative_sum += percentages.sum
      cumulative_rated += percentages.length

      Week.new(
        week_start:,
        attempts_count: week_points.length,
        cumulative_attempts_count: cumulative_attempts,
        distinct_students_count: week_points.map(&:student_id).uniq.length,
        rated_count: percentages.length,
        average: percentages.empty? ? nil : percentages.sum / percentages.length,
        cumulative_average: cumulative_rated.zero? ? nil : cumulative_sum / cumulative_rated
      )
    end
  end
end
