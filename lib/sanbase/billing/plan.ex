defmodule Sanbase.Billing.Plan do
  @moduledoc """
  Module for managing billing plans that define the amount and billing cycle
  for subscriptions.
  We have plans with the same name but different interval (`month`, `year`) and amount.
  """
  use Ecto.Schema

  import Ecto.Query
  import Ecto.Changeset

  alias __MODULE__.CustomPlan
  alias Sanbase.Repo
  alias Sanbase.Billing.{Product, Subscription}

  @plans_order [free: 0, basic: 1, pro: 2, business_pro: 3, max: 4, business_max: 5, custom: 6]
  @plans Keyword.keys(@plans_order)

  def plans(), do: @plans
  def plans_order(), do: @plans_order

  def existing_plan_names do
    from(p in __MODULE__, select: p.name, distinct: true)
    |> Repo.all()
  end

  def sort_plans(plans),
    do: Enum.sort_by(plans, fn plan -> Keyword.get(@plans_order, plan) end)

  schema "plans" do
    field(:name, :string)
    # amount is in cents
    field(:amount, :integer)
    field(:currency, :string)
    # interval is one of `month` or `year`
    field(:interval, :string)
    field(:stripe_id, :string)

    # there might be still customers on this plan, but new subscriptions should be disabled.
    field(:is_deprecated, :boolean, default: false)
    # plans that customers can't subscribe on their own
    field(:is_private, :boolean)

    # is plan for parity purchasing power
    field(:is_ppp, :boolean, default: false)

    # order first by `order` field, then by id
    field(:order, :integer)

    # if plan is custom, then the restrictions for it are read from the restrictions field
    field(:has_custom_restrictions, :boolean)
    embeds_one(:restrictions, CustomPlan.Restrictions, on_replace: :update)

    belongs_to(:product, Product)
    has_many(:subscriptions, Subscription, on_delete: :delete_all)
  end

  def changeset(%__MODULE__{} = plan, attrs \\ %{}) do
    plan
    |> cast(attrs, [
      :name,
      :product_id,
      :amount,
      :currency,
      :interval,
      :stripe_id,
      :is_deprecated,
      :is_private,
      :order,
      :has_custom_restrictions
    ])
    |> cast_embed(:restrictions,
      required: false,
      with: &CustomPlan.Restrictions.changeset/2
    )
    |> unique_constraint(:id, name: :plans_pkey)
  end

  def create_custom_api_plan(args) do
    args = %{
      name: Map.fetch!(args, :name),
      product_id: Map.fetch!(args, :product_id),
      amount: Map.fetch!(args, :amount),
      currency: Map.fetch!(args, :currency),
      interval: Map.fetch!(args, :interval),
      stripe_id: Map.get(args, :stripe_id),
      is_deprecated: false,
      is_private: true,
      order: Map.get(args, :order, 0),
      has_custom_restrictions: true,
      restrictions: Map.fetch!(args, :restrictions)
    }

    %__MODULE__{}
    |> changeset(args)
    |> validate_change(:name, &validate_custom_api_plan_name/2)
    |> validate_change(:product_id, &validate_product_is_api/2)
    |> Sanbase.Repo.insert()
  end

  def upgrade_plan(base_plan, extends: upgrades) do
    Sanbase.Utils.Map.merge_deep(base_plan, upgrades)
  end

  def update_plan(plan, params) do
    plan
    |> changeset(params)
    |> Repo.update()
  end

  def list_custom_plans() do
    plans =
      from(
        p in __MODULE__,
        where: p.has_custom_restrictions == true
      )
      |> Repo.all()

    {:ok, plans}
  end

  def by_ids(plan_ids) when is_list(plan_ids) do
    from(p in __MODULE__, where: p.id in ^plan_ids)
    |> Repo.all()
  end

  def free_plan() do
    %__MODULE__{name: "FREE", product_id: 1}
  end

  @same_name_plans [
    "FREE",
    "BASIC",
    "PRO",
    "PRO_PLUS",
    "MAX",
    "BUSINESS_PRO",
    "BUSINESS_MAX",
    "CUSTOM",
    "PREMIUM"
  ]

  # Names that canonicalize to another rung. Shared by `plan_name/1` and
  # `api_call_limits/1` so a future alias cannot update one and silently miss
  # the other.
  @plan_name_aliases %{"ESSENTIAL" => "BASIC"}

  @bundle_prefix "BUNDLE"
  @custom_prefix "CUSTOM_"
  @institutional_prefix "INSTITUTIONAL"

  # Withdrawn plans. Renaming a row to `RETIRED_*` retires it, and this prefix is what makes
  # the rename mean something: `product_with_plans/0` applies `is_deprecated` only to the
  # Business names, so without an explicit exclusion a renamed row stays on the pricing page
  # under a name that reads like debug output. `ensure_plan_is_for_sale/2` refuses it too -
  # delisting is not a purchase gate, since `subscribe(plan_id:)` takes an id.
  @retired_prefix "RETIRED_"

  # Unlike `BUNDLE` and `INSTITUTIONAL`, this prefix is shared with rows outside the new
  # offering: `ENTERPRISE_BASIC` (105) and `ENTERPRISE_PLUS` (106), sold in 2022, never
  # wired into any access checker, renamed out of the way by
  # `20260810121347_retire_legacy_enterprise_plans.exs`. Here and in `plan_name/1` the
  # prefix is what is wanted - the widest answer to "is this name in the Enterprise
  # family". The decisions that put a plan *on sale* or *cancel someone's subscription*
  # match `"ENTERPRISE"` exactly instead: `Sanbase.Billing.Plan.SaleControls` and
  # `Bundle.Lifecycle.stale_replaced_subscriptions/0`. `product_with_plans/0` keeps the
  # prefix on purpose - delisting the legacy rows is the desired outcome there.
  @enterprise_prefix "ENTERPRISE"

  # The two plans whose availability for sale is toggled by
  # `Sanbase.Billing.Plan.SaleControls`.
  @business_plan_names ["BUSINESS_PRO", "BUSINESS_MAX"]

  @spec business_plan_names() :: [String.t()]
  def business_plan_names, do: @business_plan_names

  def plan_name(%__MODULE__{} = plan) do
    case Map.get(@plan_name_aliases, plan.name, plan.name) do
      name when name in @same_name_plans -> name
      "CUSTOM_" <> _ = name -> name
      @bundle_prefix <> _ = name -> name
      @institutional_prefix <> _ = name -> name
      @enterprise_prefix <> _ = name -> name
    end
  end

  def plan_name(_), do: "FREE"

  @typedoc ~s"""
  How a plan is dispatched in the access and quota layers.

    * `:standard` - the ordinal plan ladder (FREE < BASIC < PRO < ...). Access is
      declared per metric/query/signal via `min_plan` in the GraphQL schema and
      compared ordinally.
    * `:custom` - a bespoke `CUSTOM_*` plan. Access is an explicit allow-list
      stored in the plan's embedded `Restrictions`.
    * `:bundle` - a composable `BUNDLE*` plan. Access is decoded from the
      subscription's items. See `docs/composable-api-plans-handover.md`.

  Note that the plan named exactly `"CUSTOM"` is `:standard` - it is a rung on
  the ladder, not a bespoke plan. `INSTITUTIONAL` and `ENTERPRISE` are `:standard`
  too: they belong to the same new offering as `BUNDLE` commercially, but they are
  fixed plans whose access and quota are declared in code like every other rung,
  not assembled from purchased items. Nothing about them needs the item or
  entitlement machinery.

  `ENTERPRISE` is in particular *not* the `CUSTOM_*` path. Those two were used
  interchangeably in prose for years, because every Enterprise deal used to be a
  hand-built bespoke plan. The tier introduced in §8 **EP** is the opposite: one
  fixed price for a declared set of access. Bespoke contracts still exist and are
  still `CUSTOM_*`.
  """
  @type plan_type :: :standard | :custom | :bundle

  @doc ~s"""
  Classify a canonical plan name (the output of `plan_name/1`) for dispatch.

  This is the single seam for plan-type dispatch. Every access or quota function
  that needs to behave differently per plan type should `case` on this rather
  than pattern-matching the name itself, so that:

    * `rg "Plan.type"` enumerates every plan-type-aware site, and
    * dispatch happens on an atom from a closed type, so a missing clause can be
      caught by Dialyzer instead of raising `CaseClauseError` at runtime.

  ## Examples

      iex> Sanbase.Billing.Plan.type("PRO")
      :standard

      iex> Sanbase.Billing.Plan.type("CUSTOM")
      :standard

      iex> Sanbase.Billing.Plan.type("CUSTOM_ACME")
      :custom

      iex> Sanbase.Billing.Plan.type("BUNDLE")
      :bundle

      iex> Sanbase.Billing.Plan.type("INSTITUTIONAL")
      :standard

      iex> Sanbase.Billing.Plan.type("ENTERPRISE")
      :standard

  ## Non-binary input

  This function is total: anything that is not a recognised prefix is
  `:standard`, including non-binary terms. That is deliberate rather than
  lenient-by-accident - it preserves the behavior of the `case plan_name do
  "CUSTOM_" <> _ -> ...; _ -> ... end` blocks this replaced, which accepted any
  term and fell through to the standard ladder.

  It does mean a caller that passes the wrong argument gets `:standard` instead
  of a crash. There is at least one such caller today:
  `SanbaseWeb.Graphql.TestHelpers.fully_restricted_metrics_for_plan/2` passes
  `plan_has_access?/3`'s arguments in the wrong order, so the plan name it
  supplies is actually a `{:metric, name}` tuple. Adding a guard here would turn
  that into a `FunctionClauseError`, which is a behavior change, so it is left
  as a separate fix.
  """
  @spec type(term()) :: plan_type()
  def type(@bundle_prefix <> _), do: :bundle
  def type(@custom_prefix <> _), do: :custom
  def type(_plan_name), do: :standard

  @doc ~s"""
  Classify an `api_call_limits.api_calls_limit_plan` value.

  Those strings are product-prefixed and downcased (`"sanapi_pro"`,
  `"sanapi_custom_acme"`) rather than canonical plan names, so they need
  unwrapping before `type/1` applies.

  `:custom` is only ever returned for the SanAPI prefix. `CUSTOM_*` plans can
  only exist on the API product (see `create_custom_api_plan/1`), and the quota
  code has always keyed on `"sanapi_custom_"` specifically - classifying a
  hypothetical `"sanbase_custom_*"` as `:custom` would change existing behavior.
  `:bundle` is recognised under both prefixes, since it is new and has no
  backward-compatibility constraint.

  Like `type/1`, this is total - see the note there on why.
  """
  @spec type_of_api_call_limit_plan(term()) :: plan_type()
  def type_of_api_call_limit_plan("sanapi_" <> rest), do: type(String.upcase(rest))

  def type_of_api_call_limit_plan("sanbase_" <> rest) do
    case type(String.upcase(rest)) do
      :bundle -> :bundle
      _ -> :standard
    end
  end

  def type_of_api_call_limit_plan(_plan), do: :standard

  @doc ~s"""
  The API call allowance a subscription on this plan grants, as a
  `%{month: _, hour: _, minute: _}` map, or `nil` when the row itself does not
  fix the numbers: `BUNDLE` rows (per-customer, resolved from the subscription's
  entitlement), `CUSTOM_*` rows sold without a ceiling, and rows with no entry
  in `Sanbase.ApiCallLimit.Restrictions` (e.g. Sanbase `FREE`, whose users are
  metered as `sanapi_free` because quota is keyed on the subscription, and a
  free plan means no subscription).

  `ESSENTIAL` answers as `BASIC` - the same mapping `plan_name/1` applies when a
  subscription is metered. `plan_name/1` itself is not called here because it is
  partial (it raises on `RETIRED_*` names), and this must answer for any row.

  ## Examples

      iex> Sanbase.Billing.Plan.api_call_limits(%Sanbase.Billing.Plan{name: "PRO", product_id: 1})
      %{month: 600_000, hour: 30_000, minute: 600}

      iex> Sanbase.Billing.Plan.api_call_limits(%Sanbase.Billing.Plan{name: "BUNDLE", product_id: 1})
      nil
  """
  @spec api_call_limits(%__MODULE__{}) ::
          %{month: pos_integer(), hour: pos_integer(), minute: pos_integer()} | nil
  def api_call_limits(%__MODULE__{} = plan) do
    case type(plan.name) do
      # TODO: A bundle's numbers are per-customer - every bundle subscription
      # points to the same BUNDLE marker row, and the real limits are decoded
      # from the subscription's items. Exposing them needs a field on the
      # subscription (Subscription.bundle_entitlement/1 +
      # Bundle.Access.api_call_limits/1), not on the plan.
      :bundle -> nil
      :custom -> custom_api_call_limits(plan)
      :standard -> standard_api_call_limits(plan)
    end
  end

  defp custom_api_call_limits(%__MODULE__{
         restrictions: %CustomPlan.Restrictions{
           api_call_limits: %{"month" => month, "hour" => hour, "minute" => minute}
         }
       }) do
    %{month: month, hour: hour, minute: minute}
  end

  # Matches both a missing restrictions embed and the %{"has_limits" => false}
  # shape a bespoke contract with no ceiling stores.
  defp custom_api_call_limits(_plan), do: nil

  defp standard_api_call_limits(%__MODULE__{} = plan) do
    name = Map.get(@plan_name_aliases, plan.name, plan.name)
    code = Product.code_by_id(plan.product_id)
    key = Sanbase.ApiCallLimit.Restrictions.key(code, name)

    case Map.get(Sanbase.ApiCallLimit.Restrictions.call_limits_per_month(), key) do
      nil ->
        nil

      month ->
        %{
          month: month,
          hour: Map.fetch!(Sanbase.ApiCallLimit.Restrictions.call_limits_per_hour(), key),
          minute: Map.fetch!(Sanbase.ApiCallLimit.Restrictions.call_limits_per_minute(), key)
        }
    end
  end

  def plan_full_name(plan) do
    plan = plan |> Repo.preload(:product)
    "#{plan.product.name} / #{plan.name}"
  end

  def by_id(plan_id) do
    Repo.get(__MODULE__, plan_id)
    |> Repo.preload(:product)
  end

  def by_stripe_id(stripe_id) do
    Repo.get_by(__MODULE__, stripe_id: stripe_id)
    |> Repo.preload(:product)
  end

  @doc """
  List all products with corresponding subscription plans

  `BUNDLE`, `INSTITUTIONAL` and `ENTERPRISE` rows are left out - the whole new
  offering. For `BUNDLE` the reason is that the row is a marker rather than a
  tier: its amount is 0 and the real prices live per item in the bundle price
  catalog, so listing it would show a $0 plan and offer `subscribe(plan_id:)` a
  plan that flow cannot correctly create. The bundle catalog is served by
  `bundleCatalog` instead.

  `INSTITUTIONAL` and `ENTERPRISE` are real priced plans and both are self-serve,
  but they are still excluded here: this query backs the legacy pricing grid,
  which renders a column per row and knows nothing about the three-column
  offering. The new purchase surface addresses them by plan id (§8 **UI**).

  `RETIRED_*` rows are excluded as well - withdrawn plans kept only so the
  subscriptions that reference them still resolve. The exclusion has to be by name
  because of the `is_deprecated` rule below: setting that field is what a caller
  would expect to withdraw a row, and for everything outside the Business names it
  does nothing here.

  ## Why `is_deprecated` is only applied to the Business plans

  Withdrawing Business Pro/Max from sale has to remove them from this list, or
  the admin toggle in `Sanbase.Billing.Plan.SaleControls` would have no visible
  effect. Every other row is returned exactly as it was before that toggle
  existed, and that is deliberate: `is_private` and `is_deprecated` are set on
  plenty of rows that are still expected here. On production `FREE` on both
  products, and `PRO`, `PRO_PLUS` and `MAX` on Sanbase, are all
  `is_private = true`, and Sanbase `BASIC` is deprecated - filtering on either
  field across the board empties most of the pricing page. Both fields are
  exposed on the GraphQL plan type, so a caller that wants to hide such rows
  still can.
  """
  def product_with_plans do
    bundle_pattern = @bundle_prefix <> "%"
    institutional_pattern = @institutional_prefix <> "%"
    enterprise_pattern = @enterprise_prefix <> "%"
    retired_pattern = @retired_prefix <> "%"

    query =
      from(p in Product,
        join: pl in __MODULE__,
        on: pl.product_id == p.id,
        where:
          not pl.is_ppp and not like(pl.name, ^bundle_pattern) and
            not like(pl.name, ^institutional_pattern) and
            not like(pl.name, ^enterprise_pattern) and
            not like(pl.name, ^retired_pattern) and
            (pl.name not in ^@business_plan_names or
               coalesce(pl.is_deprecated, false) == false),
        order_by: [desc: pl.order, asc: pl.id],
        preload: [plans: pl]
      )

    product_with_plans = Repo.all(query)

    {:ok, product_with_plans}
  end

  @doc ~s"""
  Marker `BUNDLE` plan for the given billing interval (`"month"` / `"year"`).
  """
  @spec bundle_plan(String.t()) :: %__MODULE__{} | nil
  def bundle_plan(interval) when interval in ["month", "year"] do
    Repo.get_by(__MODULE__,
      name: @bundle_prefix,
      interval: interval,
      product_id: Product.product_api()
    )
    |> Repo.preload(:product)
  end

  @doc """
  If a plan doesn't have filled `stripe_id` - create a plan in Stripe and update with the received
  `stripe_id`
  """
  def maybe_create_plan_in_stripe(%__MODULE__{stripe_id: stripe_id} = plan)
      when is_nil(stripe_id) do
    plan
    |> Sanbase.StripeApi.create_plan()
    |> case do
      {:ok, stripe_plan} ->
        update_plan(plan, %{stripe_id: stripe_plan.id})

      {:error, reason} ->
        {:error, reason}
    end
  end

  def maybe_create_plan_in_stripe(%__MODULE__{stripe_id: stripe_id} = plan)
      when is_binary(stripe_id) do
    {:ok, plan}
  end

  defp validate_product_is_api(:product_id, product_id) do
    case product_id == Product.product_api() do
      true -> []
      false -> [product_id: "Custom plans can be created only for SANAPI product"]
    end
  end

  defp validate_custom_api_plan_name(:name, name) do
    case String.starts_with?(name, "CUSTOM_") and name == String.upcase(name) do
      true ->
        []

      false ->
        [
          name:
            "Custom plan name must start with 'CUSTOM_' and contain only upcase letters and digits"
        ]
    end
  end
end
