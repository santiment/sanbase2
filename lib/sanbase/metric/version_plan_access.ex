defmodule Sanbase.Metric.VersionPlanAccess do
  @moduledoc ~s"""
  Lets one plan use one metric version (a `Sanbase.Metric.VersionAlias` row) on one
  product. A version is available to a plan only if it has a matching row - see
  `Sanbase.Billing.Plan.MetricVersionAccess`.

    * `product` - the surface the request comes through: "SANAPI" for apikey
      requests, "SANBASE" for the web app.
    * `plan` - a standard plan name ("PRO", "BUSINESS_MAX", ...), or "ANY" for every
      plan, including no subscription (FREE). Custom plans and bundles are matched by
      the standard plan they are based on; the other plans (Institutional, ...) only
      by "ANY".
    * `billing_interval` - "any", "month" or "year".
    * `include_trial` - whether a trialing subscription counts.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias Sanbase.Metric.VersionAlias

  @type t :: %__MODULE__{}

  @products ["SANAPI", "SANBASE"]
  @any_plan "ANY"
  @plans [@any_plan, "FREE", "BASIC", "PRO", "PRO_PLUS", "MAX", "BUSINESS_PRO", "BUSINESS_MAX"]
  @billing_intervals ["any", "month", "year"]

  @doc "The products a row can belong to."
  @spec products() :: [String.t()]
  def products(), do: @products

  @doc "The plan names a row can have. \"ANY\" matches every plan."
  @spec plans() :: [String.t()]
  def plans(), do: @plans

  @spec billing_intervals() :: [String.t()]
  def billing_intervals(), do: @billing_intervals

  schema "metric_version_plan_access" do
    belongs_to(:version_alias, VersionAlias)

    field(:product, :string)
    field(:plan, :string)
    field(:billing_interval, :string, default: "any")
    field(:include_trial, :boolean, default: true)

    timestamps()
  end

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(%__MODULE__{} = plan_access, attrs) do
    plan_access
    |> cast(attrs, [:version_alias_id, :product, :plan, :billing_interval, :include_trial])
    |> update_change(:plan, &normalize_plan/1)
    |> validate_required([:version_alias_id, :product, :plan, :billing_interval])
    |> validate_inclusion(:product, @products)
    |> validate_inclusion(:billing_interval, @billing_intervals)
    |> validate_inclusion(:plan, @plans)
    |> validate_exposed()
    |> foreign_key_constraint(:version_alias_id)
    |> unique_constraint([:version_alias_id, :product, :plan, :billing_interval],
      name: :metric_version_plan_access_unique_index,
      error_key: :plan,
      message: "already has access to this version"
    )
  end

  @doc "Whether the row lets this plan use the version on this product."
  @spec matches?(t(), String.t(), String.t(), String.t() | nil, boolean()) :: boolean()
  def matches?(%__MODULE__{} = row, product, plan, interval, trialing?) do
    row.product == product and
      row.plan in [@any_plan, plan] and
      row.billing_interval in ["any", interval] and
      (row.include_trial or not trialing?)
  end

  defp normalize_plan(nil), do: nil
  defp normalize_plan(plan), do: plan |> String.trim() |> String.upcase()

  # A row for a product the version is not exposed in would never match.
  defp validate_exposed(changeset) do
    with id when is_integer(id) <- get_field(changeset, :version_alias_id),
         product when product in @products <- get_field(changeset, :product),
         %VersionAlias{} = version_alias <- Sanbase.Repo.get(VersionAlias, id),
         false <- VersionAlias.exposed_in?(version_alias, product) do
      add_error(
        changeset,
        :product,
        "#{version_alias.version_name} is not exposed in #{product} (exposed_in: #{version_alias.exposed_in})"
      )
    else
      _ -> changeset
    end
  end
end
