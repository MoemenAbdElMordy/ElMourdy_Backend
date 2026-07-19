class ExamAttempt < ApplicationRecord
  enum :result_status, { passed: 0, risk: 1, failed: 2 }, validate: { allow_nil: true }
  enum :status, { in_progress: 0, submitted: 1, expired: 2 }, validate: true

  belongs_to :exam
  belongs_to :student_profile
  has_many :exam_answers, dependent: :restrict_with_error

  validates :attempt_number, numericality: { only_integer: true, greater_than: 0 },
    uniqueness: { scope: %i[exam_id student_profile_id] }
  validates :started_at, presence: true
  validates :percent, numericality: { in: 0..100 }, allow_nil: true
  validates :score_points, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
  validates :max_points, numericality: { greater_than: 0 }, allow_nil: true
  validate :submitted_state_is_complete

  scope :recent, -> { order(started_at: :desc) }

  private

  def submitted_state_is_complete
    return unless submitted?
    return if submitted_at.present? && percent.present? && result_status.present?

    errors.add(:status, "requires submission time, percentage, and result")
  end
end
