# Be sure to restart your server when you modify this file.

# Avoid CORS issues when API is called from the frontend app.
# Handle Cross-Origin Resource Sharing (CORS) in order to accept cross-origin Ajax requests.

# Read more: https://github.com/cyu/rack-cors

Rails.application.config.middleware.insert_before 0, Rack::Cors do
  allow do
    default_origins = Rails.env.production? ? "https://mourdy.com,https://www.mourdy.com" :
      "http://localhost:5173,http://127.0.0.1:5173"
    configured_origins = ENV.fetch("FRONTEND_ORIGINS", ENV.fetch("FRONTEND_ORIGIN", default_origins))
      .split(",").map(&:strip).reject(&:blank?)
    origins(*configured_origins)

    resource "*",
      headers: :any,
      methods: %i[get post put patch delete options head]
  end
end
