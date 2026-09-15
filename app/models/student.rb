class Student < ApplicationRecord
  include ActiveRecordScope
  has_secure_password

  has_many :class_students, dependent: :restrict_with_exception
  has_many :school_classes, through: :class_students
  has_many :exercise_attempts, dependent: :restrict_with_exception
  has_one :student_stat, dependent: :restrict_with_exception

  validates :username, :email, :name, presence: true
  validates :username, :email, uniqueness: true
end
