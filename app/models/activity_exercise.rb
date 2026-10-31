class ActivityExercise < ApplicationRecord
  self.table_name = "activities_exercises"

  include ActiveRecordScope

  belongs_to :activity
  belongs_to :exercise
  has_many :exercise_attempts, dependent: :restrict_with_exception

  MAX_POINTS = 1_000_000
  # Bem abaixo do limite da coluna (2**63 - 1), deixando folga para o Append somar 1.
  MAX_POSITION = 2**31 - 1

  validates :position, :points, presence: true
  validates :position, uniqueness: { scope: :activity_id, conditions: -> { where(active: true) } }, if: :active?
  # O Rails avalia a numericidade sobre o valor bruto, então "1.5" e "abc" não viram inteiros em silêncio.
  validates :points, numericality: { only_integer: true, greater_than_or_equal_to: 0, less_than_or_equal_to: MAX_POINTS }, allow_blank: true
  validates :position, numericality: { only_integer: true, greater_than_or_equal_to: 0, less_than_or_equal_to: MAX_POSITION }, allow_blank: true
  validate :exercise_not_already_active_in_activity, if: :active?

  scope :ordered, -> { order(:position) }

  private

  def exercise_not_already_active_in_activity
    return if activity_id.blank? || exercise_id.blank?

    duplicates = self.class.active.where(activity_id:, exercise_id:)
    duplicates = duplicates.where.not(id:) if persisted?
    errors.add(:base, "Este exercício já está associado a esta aula.") if duplicates.exists?
  end
end
