class ClassPostComment < ApplicationRecord
  include ActiveRecordScope

  MAX_BODY_LENGTH = 500
  AUTHOR_TYPES = %w[Teacher Student].freeze

  belongs_to :class_post
  belongs_to :author, polymorphic: true

  normalizes :body, with: ->(body) { body.strip }

  validates :body, presence: true, length: { maximum: MAX_BODY_LENGTH }
  validates :author_type, inclusion: { in: AUTHOR_TYPES }

  scope :chronological, -> { order(:created_at, :id) }
end
