defmodule SanbaseWeb.AdminSharedComponents do
  @moduledoc """
  Shared UI components used across multiple admin LiveView pages.

  These components extract common patterns found in the admin panel:
  - Action buttons (phx-click buttons with optional count badges)
  - Filter checkboxes
  - Approval button groups (approve/decline/undo)
  - Status badges
  - Page headers with user details
  - Back navigation links
  - Date displays (created/updated)
  """
  use Phoenix.Component

  alias SanbaseWeb.CoreComponents

  # ---------------------------------------------------------------------------
  # Action Button — replaces 3 duplicated `phx_click_button` components
  # Used in: MetricRegistryIndexLive, MetricRegistrySyncLive, MetricRegistrySyncRunsLive
  # ---------------------------------------------------------------------------

  attr :phx_click, :string, required: true
  attr :text, :string, required: true
  attr :count, :integer, default: nil
  attr :class, :string, default: "bg-white hover:bg-gray-100 text-gray-900"
  attr :phx_disable_with, :string, default: nil
  attr :rest, :global

  def action_button(assigns) do
    ~H"""
    <button
      type="button"
      phx-click={@phx_click}
      class={[
        "border border-gray-200 font-medium rounded-lg text-sm px-5 py-2.5 text-center inline-flex items-center gap-x-2",
        @class
      ]}
      phx-disable-with={@phx_disable_with}
      {@rest}
    >
      {@text}
      <span :if={@count && @count > 0} class="text-gray-400">({@count})</span>
    </button>
    """
  end

  # ---------------------------------------------------------------------------
  # Filter Checkbox — replaces 4 near-identical filter checkboxes
  # Used in: MetricRegistryIndexLive (not_deprecated, unverified, not_synced, without_docs)
  # ---------------------------------------------------------------------------

  attr :id, :string, required: true
  attr :name, :string, required: true
  attr :label, :string, required: true

  def filter_checkbox(assigns) do
    ~H"""
    <div class="flex items-center mb-4">
      <label for={@id} class="cursor-pointer ms-2 text-sm font-medium text-gray-900">
        <input
          id={@id}
          name={@name}
          type="checkbox"
          class="w-4 h-4 text-blue-600 bg-gray-100 border-gray-300 rounded"
        /> {@label}
      </label>
    </div>
    """
  end

  # ---------------------------------------------------------------------------
  # Approval Buttons — shared approve/decline/undo pattern
  # Used in: MonitoredTwitterHandleLive, SuggestEcosystemLabelsChangeAdminLive,
  #          SuggestGithubOrganizationsAdminLive
  # ---------------------------------------------------------------------------

  attr :form, :any, required: true
  attr :row_id, :any, required: true
  attr :status, :string, required: true
  attr :phx_submit, :string, default: "update_status"
  slot :extra_fields

  def approval_buttons(assigns) do
    ~H"""
    <.form
      for={@form}
      phx-submit={@phx_submit}
      class="flex flex-col lg:flex-row space-y-2 lg:space-y-0 md:space-x-2"
    >
      <input type="hidden" name="record_id" value={@row_id} />
      {render_slot(@extra_fields)}
      <.approval_button
        name="status"
        value="approved"
        text="Approve"
        disabled={@status != "pending_approval"}
        colors="bg-green-600 hover:bg-green-800"
      />
      <.approval_button
        name="status"
        value="declined"
        text="Decline"
        disabled={@status != "pending_approval"}
        colors="bg-red-600 hover:bg-red-800"
      />
      <.approval_button
        name="status"
        value="undo"
        text={undo_text(@status)}
        disabled={@status == "pending_approval"}
        colors="bg-yellow-400 hover:bg-yellow-800"
      />
    </.form>
    """
  end

  attr :name, :string, required: true
  attr :value, :string, required: true
  attr :text, :string, required: true
  attr :disabled, :boolean, required: true
  attr :colors, :string, required: true

  def approval_button(assigns) do
    ~H"""
    <button
      name={@name}
      value={@value}
      class={[
        "phx-submit-loading:opacity-75 rounded-lg my-1 py-2 px-3 text-sm font-semibold leading-6 text-white",
        if(@disabled, do: "bg-gray-300", else: @colors)
      ]}
      disabled={@disabled}
    >
      {@text}
    </button>
    """
  end

  defp undo_text("approved"), do: "Undo Approval"
  defp undo_text("declined"), do: "Undo Refusal"
  defp undo_text(_), do: "Undo"

  # ---------------------------------------------------------------------------
  # Status Badge — formatted status display
  # Consolidates AdminFormsComponents.status
  # ---------------------------------------------------------------------------

  attr :status, :string, required: true

  def status_badge(assigns) do
    ~H"""
    <p class={status_color(@status)}>
      {@status |> String.replace("_", " ") |> String.upcase()}
    </p>
    """
  end

  defp status_color("approved"), do: "text-green-600"
  defp status_color("declined"), do: "text-red-600"
  defp status_color("pending_approval"), do: "text-yellow-600"
  defp status_color(_), do: "text-gray-600"

  # ---------------------------------------------------------------------------
  # Page Header — title + user details pattern used across metric registry pages
  # ---------------------------------------------------------------------------

  attr :title, :string, required: true
  attr :current_user, :map, required: true
  attr :current_user_role_names, :list, required: true
  attr :subtitle, :string, default: nil
  attr :trim_role_prefix, :string, default: nil

  def page_header(assigns) do
    ~H"""
    <h1 class="text-blue-700 text-2xl mb-4">
      {@title}
    </h1>
    <div :if={@subtitle} class="text-gray-400 text-sm py-2">
      {@subtitle}
    </div>
    <div class="my-2 flex flex-row space-x-2">
      <span class="text-blue-800 font-bold">
        {@current_user.email}
      </span>
      <span>|</span>
      <span class="text-gray-700">
        {format_roles(@current_user_role_names, @trim_role_prefix)}
      </span>
    </div>
    """
  end

  defp format_roles(role_names, nil), do: Enum.join(role_names, ", ")

  defp format_roles(role_names, prefix) do
    role_names
    |> Enum.map(&String.trim_leading(&1, prefix))
    |> Enum.join(", ")
  end

  # ---------------------------------------------------------------------------
  # Navigation Button — unified link button for admin navigation
  # Consolidates available_metrics_button and link_button
  # ---------------------------------------------------------------------------

  attr :text, :string, required: true
  attr :href, :string, required: true
  attr :icon, :string, default: nil
  attr :disabled, :boolean, default: false
  attr :target, :string, default: "_self"

  def nav_button(assigns) do
    ~H"""
    <.link
      href={@href}
      target={@target}
      class={[
        if(@disabled,
          do: "pointer-events-none bg-gray-100 text-gray-400",
          else: "bg-white hover:bg-gray-100 text-gray-900"
        ),
        "border border-gray-200 font-medium rounded-lg text-sm px-5 py-2.5 text-center inline-flex items-center gap-x-2"
      ]}
    >
      <CoreComponents.icon :if={@icon} name={@icon} class="text-gray-500" />
      {@text}
    </.link>
    """
  end

  # ---------------------------------------------------------------------------
  # Dates Display — created/updated timestamps
  # Used in: MetricRegistryIndexLive, MetricRegistryChangeSuggestionsLive
  # ---------------------------------------------------------------------------

  attr :inserted_at, :any, required: true
  attr :updated_at, :any, required: true
  attr :compact, :boolean, default: false

  def dates_display(assigns) do
    inserted_duration =
      Sanbase.DateTimeUtils.rough_duration_since(assigns.inserted_at, abbreviate: true)

    updated_duration =
      Sanbase.DateTimeUtils.rough_duration_since(assigns.updated_at, abbreviate: true)

    assigns =
      assign(assigns, inserted_duration: inserted_duration, updated_duration: updated_duration)

    ~H"""
    <div class="flex flex-col gap-1">
      <div class="flex items-center gap-1.5 text-nowrap">
        <CoreComponents.icon name="hero-plus-circle" class="w-4 h-4 text-green-600" />
        <span class="text-gray-700 text-sm">{@inserted_duration} ago</span>
      </div>
      <div :if={@inserted_at != @updated_at} class="flex items-center gap-1.5 text-nowrap">
        <CoreComponents.icon name="hero-pencil-square" class="w-4 h-4 text-amber-600" />
        <span class="text-gray-700 text-sm">{@updated_duration} ago</span>
      </div>
    </div>
    """
  end
end
