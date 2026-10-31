class ClassPost < ApplicationRecord
  include ActiveRecordScope

  MAX_BODY_LENGTH = 2000

  belongs_to :school_class, foreign_key: :class_id
  belongs_to :teacher
  has_many :comments, class_name: "ClassPostComment", dependent: :restrict_with_exception

  before_validation :copy_teacher_from_class, on: :create

  normalizes :body, with: ->(body) { body.strip }

  validates :body, presence: true, length: { maximum: MAX_BODY_LENGTH }
  validate :teacher_must_be_class_teacher

  scope :recent_first, -> { order(created_at: :desc, id: :desc) }

  private

  def copy_teacher_from_class
    self.teacher ||= school_class&.teacher
  end

  def teacher_must_be_class_teacher
    return if school_class.nil? || teacher.nil? || teacher_id == school_class.teacher_id

    errors.add(:teacher, :not_class_teacher)
  end
end
