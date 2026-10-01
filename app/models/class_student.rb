class ClassStudent < ApplicationRecord
  self.table_name = "classes_students"

  include ActiveRecordScope

  belongs_to :student
  belongs_to :school_class, foreign_key: :class_id

  validates :student_id, uniqueness: { scope: :class_id }
end
