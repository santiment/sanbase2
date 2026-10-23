defmodule Sanbase.Metric.VersionPlanAccess do
  @moduledoc ~s"""
  Lets one plan use one metric version (a `Sanbase.Metric.VersionAlias` row) on one
  product. A version is available to a plan only if it has a matching row - see
  `Sanbase.Billing.Plan.MetricVersionAccess`.

    * `product` - the surface the request comes through: "SANAPI" for apikey
      requests, "SANBASE" for the web app.
    * `plan` - a plan sold on the product ("PRO", "BUSINESS_MAX", ...), or "ANY" for
      every plan, including no subscription (FREE). Custom plans and bundles are
      matched by the standard plan they are based on.
    * `billing_interval` - "any", "month" or "year".
    * `accessible_if_trial` - whether a subscription still in its trial gets the version.
  """

  use Ecto.Schema
  import Ecto.Changeset
  import Ecto.Query, only: [from: 2]

  alias Ecto.Multi
  alias Sanbase.Metric.VersionAlias
  alias Sanbase.Repo

  @type t :: %__MODULE__{}

  @products ["SANAPI", "SANBASE"]
  @any_plan "ANY"

  # The plans a caller can have on each product, cheapest first. A SanAPI subscriber
  # who opens Sanbase without a Sanbase plan is matched by their SanAPI plan name, so
  # the SanAPI plans whose names Sanbase does not sell are on the Sanbase list too.
  # (SanAPI Pro and Essential answer as Sanbase PRO and BASIC.)
  @sanapi_only_plans ["BUSINESS_PRO", "BUSINESS_MAX", "INSTITUTIONAL", "ENTERPRISE"]

  @product_plans %{
    "SANAPI" => [
      "FREE",
      # Sold as Essential - `Sanbase.Billing.Plan.canonical_name/1`.
      "BASIC",
      "PRO",
      "BUSINESS_PRO",
      "BUSINESS_MAX",
      "INSTITUTIONAL",
      "ENTERPRISE"
    ],
    "SANBASE" => ["FREE", "BASIC", "PRO", "PRO_PLUS", "MAX" | @sanapi_only_plans]
  }

  @plans [@any_plan | @product_plans |> Map.values() |> List.flatten() |> Enum.uniq()]
  @billing_intervals ["any", "month", "year"]

  @doc "The products a row can belong to."
  @spec products() :: [String.t()]
  def products(), do: @products

  @doc "The plan names a row can have. \"ANY\" matches every plan."
  @spec plans() :: [String.t()]
  def plans(), do: @plans

  @doc "The plans a caller on the product can have, cheapest first, without \"ANY\"."
  @spec plans(String.t()) :: [String.t()]
  def plans(product) when product in @products, do: Map.fetch!(@product_plans, product)

  @doc "Whether the plan is a SanAPI plan that is matched by name on Sanbase."
  @spec sanapi_plan_on_sanbase?(String.t(), String.t()) :: boolean()
  def sanapi_plan_on_sanbase?(product, plan),
    do: product == "SANBASE" and plan in @sanapi_only_plans

  @doc "The plan name that matches every plan."
  @spec any_plan() :: String.t()
  def any_plan(), do: @any_plan

  @spec billing_intervals() :: [String.t()]
  def billing_intervals(), do: @billing_intervals

  schema "metric_version_plan_access" do
    belongs_to(:version_alias, VersionAlias)

    field(:product, :string)
    field(:plan, :string)
    field(:billing_interval, :string, default: "any")
    field(:accessible_if_trial, :boolean, default: true)

    timestamps()
  end

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(%__MODULE__{} = plan_access, attrs) do
    plan_access
    |> cast(attrs, [:version_alias_id, :product, :plan, :billing_interval, :accessible_if_trial])
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

  @doc """
  Whether the row lets this plan use the version on this product. An `interval` of
  `:any` matches every billing interval.
  """
  @spec matches?(t(), String.t(), String.t(), String.t() | nil | :any, boolean()) :: boolean()
  def matches?(%__MODULE__{} = row, product, plan, interval, trialing?) do
    row.product == product and
      row.plan in [@any_plan, plan] and
      (interval == :any or row.billing_interval in ["any", interval]) and
      (row.accessible_if_trial or not trialing?)
  end

  @doc """
  Replace all plan access of the version with `rows` (attrs without
  `version_alias_id`), in one transaction. Takes effect on every node at once.
  """
  @spec replace_all(VersionAlias.t(), [map()]) :: {:ok, [t()]} | {:error, Ecto.Changeset.t()}
  def replace_all(%VersionAlias{id: id} = version_alias, rows) when is_list(rows) do
    if VersionAlias.locked?(version_alias),
      do: VersionAlias.locked_error(version_alias),
      else: do_replace_all(id, rows)
  end

  defp do_replace_all(id, rows) do
    multi =
      rows
      |> Enum.with_index()
      |> Enum.reduce(
        Multi.delete_all(
          Multi.new(),
          :delete,
          from(p in __MODULE__, where: p.version_alias_id == ^id)
        ),
        fn {attrs, index}, multi ->
          changeset = changeset(%__MODULE__{}, Map.put(attrs, :version_alias_id, id))
          Multi.insert(multi, {:row, index}, changeset)
        end
      )

    case Repo.transaction(multi) do
      {:ok, changes} ->
        VersionAlias.clear_cache()
        {:ok, for({{:row, _}, row} <- changes, do: row)}

      {:error, _step, changeset, _changes} ->
        {:error, changeset}
    end
  end

  defp normalize_plan(nil), do: nil

  defp normalize_plan(plan),
    do: plan |> String.trim() |> String.upcase() |> Sanbase.Billing.Plan.canonical_name()

  # A row for a product the version is not exposed in would never match.
  defp validate_exposed(changeset) do
    with id when is_integer(id) <- get_field(changeset, :version_alias_id),
         product when product in @products <- get_field(changeset, :product),
         %VersionAlias{} = version_alias <- Repo.get(VersionAlias, id),
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
