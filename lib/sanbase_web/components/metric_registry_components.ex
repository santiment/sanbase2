defmodule SanbaseWeb.MetricRegistryComponents do
  use Phoenix.Component

  attr :current_user, :map, required: true
  attr :current_user_role_names, :list, required: true

  def user_details(assigns) do
    ~H"""
    <div class="my-2 flex flex-row space-x-2">
      <span class="text-blue-800 font-bold">
        {@current_user.email}
      </span>
      <span>|</span>
      <span class="text-gray-700 ">
        {@current_user_role_names
        |> Enum.map(&String.trim_leading(&1, "Metric Registry "))
        |> Enum.join(", ")}
      </span>
    </div>
    """
  end
end
