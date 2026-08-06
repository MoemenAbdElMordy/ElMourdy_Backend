module Api
  class DevicesController < ApplicationController
    before_action :authenticate_user!
    before_action -> { require_role!(:student) }

    def index
      render json: {
        devices: current_user.student_profile.device_registrations.active.recent.map do |device|
          serialize_device(device)
        end,
        limit: Devices::Register::MAX_ACTIVE_DEVICES
      }
    end

    def destroy
      Devices::Remove.call(
        student_profile: current_user.student_profile,
        device: requested_device,
        current_device: current_session.device_registration
      )
      head :no_content
    end

    def removal_request
      device = requested_device
      return render_current_device_error if device == current_session.device_registration

      request = existing_removal_request(device) || current_user.support_requests.create!(
        request_type: :device_removal,
        student_profile: current_user.student_profile,
        reason: removal_request_params[:reason],
        payload: { device_registration_id: device.id }
      )
      render json: { request_id: request.id, status: request.status }, status: :created
    end

    private

    def requested_device
      current_user.student_profile.device_registrations.active.find(params[:id])
    end

    def serialize_device(device)
      {
        id: device.id,
        name: device.device_name.presence || "Unknown device",
        browser: device.browser,
        os: device.os,
        ip_address: device.ip_address,
        last_seen_at: device.last_seen_at,
        created_at: device.created_at,
        current: device == current_session.device_registration,
        can_self_remove: can_self_remove?(device),
        pending_removal_request: existing_removal_request(device).present?
      }
    end

    def can_self_remove?(device)
      return false if device == current_session.device_registration

      latest = current_user.student_profile.device_registrations.maximum(:last_self_removed_at)
      latest.blank? || latest <= Devices::Remove::COOLDOWN.ago
    end

    def existing_removal_request(device)
      current_user.support_requests.device_removal.pending.detect do |request|
        request.payload&.fetch("device_registration_id", nil).to_i == device.id
      end
    end

    def removal_request_params
      params.fetch(:removal_request, {}).permit(:reason)
    end

    def render_current_device_error
      render json: {
        error: { code: "current_device", message: "The current device cannot be removed" }
      }, status: :unprocessable_entity
    end
  end
end
