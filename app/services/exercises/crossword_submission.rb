module Exercises
  class CrosswordSubmission
    Result = Struct.new(:attempt, :xp_awarded, keyword_init: true)

    def self.call(activity_exercise:, student:, answer:, time_spent: nil)
      activity_exercise.exercise.validate!
      AttemptValidity.ensure_response!(exercise: activity_exercise.exercise, answer:)
      grade = CrosswordGrader.call(
        layout: activity_exercise.exercise.object,
        answer:,
        points: activity_exercise.points
      )
      attempt = ExerciseAttempt.new(
        student:,
        activity_exercise:,
        answer:,
        correct: grade.correct_snapshot,
        score: grade.score,
        time_spent:
      )
      xp_awarded = false

      ExerciseAttempt.transaction do
        student_stat = StudentStat.find_or_create_by!(student:)
        student_stat.with_lock do
          prior_attempt = ExerciseAttempt.where(
            student_id: student.id,
            activity_exercise_id: activity_exercise.id
          ).exists?
          attempt.correct = grade.correct_snapshot.merge("xp_award_claimed" => !prior_attempt)
          attempt.save!
          if !prior_attempt && grade.score.positive?
            student_stat.update!(xp: student_stat.xp + grade.score)
            xp_awarded = true
          end
        end
      end

      Result.new(attempt:, xp_awarded:)
    end
  end
end
