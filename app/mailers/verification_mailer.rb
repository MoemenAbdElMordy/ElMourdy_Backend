class VerificationMailer < ApplicationMailer
  def registration_code
    @user = params.fetch(:user)
    @code = params.fetch(:code)
    @expires_in_minutes = params.fetch(:expires_in_minutes)

    mail(to: @user.email, subject: "Your ElMourdy verification code")
  end
end
