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

  attr :phx_click, :string, required: true
  attr :text, :string, required: true
  attr :count, :integer, default: nil
  attr :class, :string, default: "bg-base-100 border-base-300 hover:bg-base-200"
  attr :phx_disable_with, :string, default: nil
  attr :rest, :global

  def action_button(assigns) do
    ~H"""
    <button
      type="button"
      phx-click={@phx_click}
      class={["btn btn-sm", @class]}
      phx-disable-with={@phx_disable_with}
      {@rest}
    >
      {@text}
      <span :if={@count && @count > 0} class="badge badge-sm badge-ghost">{@count}</span>
    </button>
    """
  end

  attr :id, :string, required: true
  attr :name, :string, required: true
  attr :label, :string, required: true
  attr :checked, :boolean, default: false

  def filter_checkbox(assigns) do
    ~H"""
    <label for={@id} class="label cursor-pointer gap-2 mb-2">
      <input
        id={@id}
        name={@name}
        type="checkbox"
        checked={@checked}
        class="checkbox checkbox-sm checkbox-primary"
      />
      <span class="label-text">{@label}</span>
    </label>
    """
  end

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
      class="flex flex-col lg:flex-row gap-2"
    >
      <input type="hidden" name="record_id" value={@row_id} />
      {render_slot(@extra_fields)}
      <.approval_button
        name="status"
        value="approved"
        text="Approve"
        disabled={@status != "pending_approval"}
        variant="btn-success"
      />
      <.approval_button
        name="status"
        value="declined"
        text="Decline"
        disabled={@status != "pending_approval"}
        variant="btn-error"
      />
      <.approval_button
        name="status"
        value="undo"
        text={undo_text(@status)}
        disabled={@status == "pending_approval"}
        variant="btn-warning"
      />
    </.form>
    """
  end

  attr :name, :string, required: true
  attr :value, :string, required: true
  attr :text, :string, required: true
  attr :disabled, :boolean, required: true
  attr :variant, :string, required: true

  def approval_button(assigns) do
    ~H"""
    <button
      name={@name}
      value={@value}
      class={["btn btn-sm phx-submit-loading:opacity-75", @variant]}
      disabled={@disabled}
    >
      {@text}
    </button>
    """
  end

  @doc """
  Label for the Undo button, based on current record status.
  """
  def undo_text("approved"), do: "Undo Approval"
  def undo_text("declined"), do: "Undo Refusal"
  def undo_text(_), do: "Undo"

  attr :status, :string, required: true

  def status_badge(assigns) do
    ~H"""
    <span class={["badge", status_variant(@status)]}>
      {@status |> String.replace("_", " ") |> String.upcase()}
    </span>
    """
  end

  defp status_variant("approved"), do: "badge-success"
  defp status_variant("declined"), do: "badge-error"
  defp status_variant("pending_approval"), do: "badge-warning"
  defp status_variant(_), do: "badge-ghost"

  attr :current_user, :map, required: true
  attr :current_user_role_names, :list, required: true
  attr :trim_role_prefix, :string, default: nil

  def user_details(assigns) do
    ~H"""
    <div class="my-2 flex flex-row gap-2">
      <span class="text-primary font-bold">
        {@current_user.email}
      </span>
      <span class="text-base-content/40">|</span>
      <span class="text-base-content/70">
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

  attr :title, :string, required: true
  attr :current_user, :map, required: true
  attr :current_user_role_names, :list, required: true
  attr :trim_role_prefix, :string, default: nil

  def page_header(assigns) do
    ~H"""
    <h1 class="text-primary text-2xl mb-4">
      {@title}
    </h1>
    <.user_details
      current_user={@current_user}
      current_user_role_names={@current_user_role_names}
      trim_role_prefix={@trim_role_prefix}
    />
    """
  end

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
      rel={if @target == "_blank", do: "noopener noreferrer"}
      class={[
        "btn btn-sm",
        if(@disabled,
          do: "btn-disabled",
          else: "bg-base-100 border-base-300 hover:bg-base-200"
        )
      ]}
    >
      <CoreComponents.icon :if={@icon} name={@icon} />
      {@text}
    </.link>
    """
  end

  attr :inserted_at, :any, required: true
  attr :updated_at, :any, required: true
  attr :compact, :boolean, default: false

  def dates_display(assigns) do
    inserted_duration =
      assigns.inserted_at &&
        Sanbase.Utils.DateTime.rough_duration_since(assigns.inserted_at, abbreviate: true)

    updated_duration =
      assigns.updated_at &&
        Sanbase.Utils.DateTime.rough_duration_since(assigns.updated_at, abbreviate: true)

    show_updated? =
      assigns.inserted_at && assigns.updated_at &&
        assigns.inserted_at != assigns.updated_at

    assigns =
      assign(assigns,
        inserted_duration: inserted_duration,
        updated_duration: updated_duration,
        show_updated?: show_updated?
      )

    ~H"""
    <div class="flex flex-col gap-1">
      <div :if={@inserted_duration} class="flex items-center gap-1.5 text-nowrap">
        <CoreComponents.icon name="hero-plus-circle" class="w-4 h-4 text-success" />
        <span class="text-base-content/70 text-sm">{@inserted_duration} ago</span>
      </div>
      <div :if={@show_updated?} class="flex items-center gap-1.5 text-nowrap">
        <CoreComponents.icon name="hero-pencil-square" class="w-4 h-4 text-warning" />
        <span class="text-base-content/70 text-sm">{@updated_duration} ago</span>
      </div>
    </div>
    """
  end
end
