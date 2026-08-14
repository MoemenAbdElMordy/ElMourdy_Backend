class ApplicationMailer < ActionMailer::Base
  default from: -> { "#{ENV.fetch('MAIL_FROM_NAME', 'ElMourdy')} <#{ENV.fetch('MAIL_FROM_ADDRESS', 'noreply@mourdy.com')}>" }
  layout "mailer"
end
