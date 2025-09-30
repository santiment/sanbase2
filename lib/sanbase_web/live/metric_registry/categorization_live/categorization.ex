defmodule SanbaseWeb.Categorization_live.Index do
  use SanbaseWeb, :live_view

  alias Sanbase.Metric.Category.MetricCategoryMapping

  def mount(_params, _session, socket) do
    list = MetricCategoryMapping.list_all()

    {:ok,
     socket
     |> assign(
       page_title: "Metric Categorization",
       list: list
     )}
  end

  # Display the data from the
  def render(assigns) do
    ~H"""
    """
  end
end
