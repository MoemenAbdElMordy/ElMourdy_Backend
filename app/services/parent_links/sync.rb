module ParentLinks
  class Sync < ApplicationService
    def self.call(parent_profile:, at: Time.current)
      new(parent_profile:, at:).call
    end

    def initialize(parent_profile:, at:)
      @parent_profile = parent_profile
      @at = at
    end

    def call
      StudentParentLink.transaction do
        @parent_profile.lock!
        matching_students.find_each.map do |student|
          StudentParentLink.find_or_create_by!(
            parent_profile: @parent_profile,
            student_profile: student
          ) do |link|
            link.relation = :other
            link.status = :active
            link.linked_at = @at
          end
        end
      end
    end

    private

    def matching_students
      StudentProfile.where(parent_phone_e164: @parent_profile.verified_parent_phone_e164)
    end
  end
end
