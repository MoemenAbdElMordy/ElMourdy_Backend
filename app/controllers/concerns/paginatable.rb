module Paginatable
  DEFAULT_PER_PAGE = 20
  MAX_PER_PAGE = 100

  private

  def paginate(scope)
    page = [ params.fetch(:page, 1).to_i, 1 ].max
    per_page = params.fetch(:per_page, DEFAULT_PER_PAGE).to_i.clamp(1, MAX_PER_PAGE)
    count = scope.except(:limit, :offset, :order).count
    total_count = count.is_a?(Hash) ? count.length : count
    total_pages = total_count.zero? ? 0 : (total_count.to_f / per_page).ceil
    records = scope.limit(per_page).offset((page - 1) * per_page)

    [ records, {
      current_page: page,
      per_page: per_page,
      total_count: total_count,
      total_pages: total_pages,
      next_page: page < total_pages ? page + 1 : nil,
      previous_page: page > 1 ? page - 1 : nil
    } ]
  end
end
