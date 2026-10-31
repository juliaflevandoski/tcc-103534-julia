class Teacher < ApplicationRecord
  include ActiveRecordScope
  has_secure_password
  include AccountCredentials

  PASSWORD_RESET_EXPIRATION = 2.hours

  has_many :school_classes, dependent: :restrict_with_exception
  has_many :activities, dependent: :restrict_with_exception
  has_many :exercises, dependent: :restrict_with_exception
  has_many :class_posts, dependent: :restrict_with_exception
  has_many :class_post_comments, as: :author, dependent: :restrict_with_exception

  validates :username, :email, :name, presence: true
  validates :username, uniqueness: true

  def password_reset_expired?
    password_reset_sent_at.blank? || password_reset_sent_at < PASSWORD_RESET_EXPIRATION.ago
  end
end
