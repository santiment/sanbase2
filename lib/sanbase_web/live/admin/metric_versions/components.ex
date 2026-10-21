defmodule SanbaseWeb.Admin.MetricVersionsLive.Components do
  @moduledoc "Labels and components shared by the metric version admin pages."

  use Phoenix.Component

  alias Sanbase.Metric.VersionAlias
  alias Sanbase.Metric.VersionPlanAccess

  @product_labels %{"SANAPI" => "SanAPI", "SANBASE" => "Sanbase"}
  @product_descriptions %{"SANAPI" => "apikey requests", "SANBASE" => "the web app"}
  @exposure_labels %{
    "all" => "SanAPI and Sanbase",
    "api_only" => "SanAPI only",
    "sanbase_only" => "Sanbase only"
  }
  @interval_labels %{"any" => "Any billing", "month" => "Monthly only", "year" => "Yearly only"}

  # Full class names, so Tailwind finds them. Warning and error are left out - the
  # pages use them for versions that need attention.
  @scope_colors [
    "badge-primary",
    "badge-secondary",
    "badge-accent",
    "badge-info",
    "badge-success",
    "badge-neutral"
  ]

  def product_label(product), do: Map.get(@product_labels, product, product)
  def product_description(product), do: Map.get(@product_descriptions, product)
  def exposure_label(exposed_in), do: Map.get(@exposure_labels, exposed_in, exposed_in)

  def exposure_options() do
    Enum.map(VersionAlias.exposures() |> Enum.sort(), &{exposure_label(&1), &1})
  end

  def interval_options() do
    Enum.map(VersionPlanAccess.billing_intervals(), &{Map.fetch!(@interval_labels, &1), &1})
  end

  @doc ~s|"BUSINESS_MAX" -> "Business Max", "ANY" -> "All plans"|
  def plan_label(plan) do
    if plan == VersionPlanAccess.any_plan() do
      "All plans"
    else
      plan |> String.split("_") |> Enum.map_join(" ", &String.capitalize/1)
    end
  end

  @doc ~s|A plan access entry as people read it: "Business Max (yearly, no trial)".|
  def access_label(%{plan: plan, billing_interval: interval, accessible_if_trial: trial?}) do
    qualifiers =
      [interval != "any" && "#{interval}ly", not trial? && "no trial"]
      |> Enum.filter(& &1)

    case qualifiers do
      [] -> plan_label(plan)
      _ -> "#{plan_label(plan)} (#{Enum.join(qualifiers, ", ")})"
    end
  end

  def default_version?(%VersionAlias{version_num: num}),
    do: num == Sanbase.Metric.default_version()

  def experimental?(%VersionAlias{version_num: num}), do: num =~ "Experimental"

  @doc """
  The scope as a badge. The color comes from a hash of the name, so every scope -
  also one added later - gets the same color everywhere without a list of scopes.
  """
  attr(:scope, :string, required: true)

  def scope_badge(assigns) do
    assigns =
      assign(
        assigns,
        :color,
        Enum.at(@scope_colors, :erlang.phash2(assigns.scope, length(@scope_colors)))
      )

    ~H"""
    <span class={["badge badge-soft badge-sm", @color]}>{@scope}</span>
    """
  end

  @doc "Who can use the version on the product, for the version list."
  attr(:version, VersionAlias, required: true)
  attr(:product, :string, required: true)

  def access_summary(assigns) do
    entries = Enum.filter(assigns.version.plan_access, &(&1.product == assigns.product))
    assigns = assign(assigns, :entries, entries)

    ~H"""
    <%= cond do %>
      <% not VersionAlias.exposed_in?(@version, @product) -> %>
        <span class="text-base-content/40 text-sm">Not exposed</span>
      <% default_version?(@version) -> %>
        <span
          class="badge badge-ghost badge-sm"
          title="The default version - every plan can always use it."
        >
          All plans
        </span>
      <% experimental?(@version) -> %>
        <span class="text-sm text-base-content/60">Alpha users</span>
      <% @entries == [] -> %>
        <span class="badge badge-warning badge-sm">No plans</span>
      <% true -> %>
        <div class="flex flex-wrap gap-1">
          <span :for={entry <- sort_entries(@entries)} class="badge badge-ghost badge-sm">
            {access_label(entry)}
          </span>
        </div>
    <% end %>
    """
  end

  @doc "Orders entries like the plans are sold: \"All plans\" first, then cheapest first."
  def sort_entries(entries) do
    Enum.sort_by(entries, fn entry ->
      order = [VersionPlanAccess.any_plan() | VersionPlanAccess.plans(entry.product)]
      {Enum.find_index(order, &(&1 == entry.plan)) || length(order), entry.plan}
    end)
  end
end
