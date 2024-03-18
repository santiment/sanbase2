defmodule SanbaseWeb.Admin.UserSubmissionAdminComponents do
  use Phoenix.Component

  @moduledoc ~s"""
  Components reused in the parts of the admin panel related to
  manually approvind/declining submissions sent by users.

  Such submissions include the MonitoredTwitterHandleLive and
  EcosystemLabelSubmissionsLive
  """

  attr(:status, :string, required: true)

  def status(assigns) do
    ~H"""
    <p class={status_to_color(@status)}>
      <%= @status |> String.replace("_", " ") |> String.upcase() %>
    </p>
    """
  end

  def update_status_button(assigns) do
    ~H"""
    <button
      name={@name}
      value={@value}
      class={[
        "phx-submit-loading:opacity-75 rounded-lg my-1 py-2 px-3 text-sm font-semibold leading-6 text-white",
        @class
      ]}
    >
      <%= @display_text %>
    </button>
    """
  end

  defp status_to_color("approved"), do: "text-green-600"
  defp status_to_color("declined"), do: "text-red-600"
  defp status_to_color("pending_approval"), do: "text-yellow-600"
end
