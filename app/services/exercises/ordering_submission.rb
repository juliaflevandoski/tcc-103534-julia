module Exercises
  class OrderingSubmission
    Result = Struct.new(:attempt, :xp_awarded, keyword_init: true)

    def self.call(activity_exercise:, student:, ordered_ids: nil, sentences: nil)
      activity_exercise.exercise.validate!
      object = activity_exercise.exercise.object.deep_stringify_keys
      multiple_sentences = object["format"] == ExerciseContentValidator::MULTIPLE_SENTENCES_FORMAT
      answer = multiple_sentences ? { "sentences" => sentences } : { "ordered_ids" => ordered_ids }
      AttemptValidity.ensure_response!(exercise: activity_exercise.exercise, answer:)
      grade = if multiple_sentences
        OrderingGrader.call(exercise: object, sentences:, points: activity_exercise.points)
      else
        OrderingGrader.call(exercise: object, ordered_ids:, points: activity_exercise.points)
      end
      attempt = ExerciseAttempt.new(
        student:,
        activity_exercise:,
        answer: grade.answer,
        correct: grade.correct,
        score: grade.score
      )
      xp_awarded = false

      ExerciseAttempt.transaction do
        student_stat = StudentStat.find_or_create_by!(student:)
        student_stat.with_lock do
          prior_attempt = ExerciseAttempt.where(
            student_id: student.id,
            activity_exercise_id: activity_exercise.id
          ).exists?
          attempt.correct = grade.correct.merge(
            "xp_award_claimed" => !prior_attempt,
            "points_possible" => activity_exercise.points.to_i
          )
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
