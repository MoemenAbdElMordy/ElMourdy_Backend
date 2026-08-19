class ApiRootController < ActionController::API
  def show
    response.set_header("X-Robots-Tag", "noindex, nofollow")
    render json: { service: "ElMourdy API", status: "ok" }
  end
end
