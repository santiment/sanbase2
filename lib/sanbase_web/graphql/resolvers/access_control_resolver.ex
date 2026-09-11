defmodule SanbaseWeb.Graphql.Resolvers.AccessControlResolver do
  import Absinthe.Resolution.Helpers, only: [on_load: 2]

  alias Sanbase.Billing.Product
  alias SanbaseWeb.Graphql.Cache
  alias SanbaseWeb.Graphql.SanbaseDataloader

  def get_access_restrictions(_root, %{plan: _, plan_name: _}, _resolution) do
    {:error, "Both 'plan' and 'plan_name' arguments are provided. Please use only one of them."}
  end

  def get_access_restrictions(_root, args, %{context: context}) do
    # An explicit `null` still arrives as a present key, and it falls through to the
    # caller's own plan - so "did they name another plan?" has to be about the value
    # that was resolved, not about the key being there. Keyed on presence, a
    # `plan: null` would silently drop the caller's own grant.
    named_plan = Map.get(args, :plan_name) || Map.get(args, :plan)
    asked_for_another_plan? = not is_nil(named_plan)

    plan_name = named_plan || context[:auth][:plan] || "FREE"

    plan_name = plan_name |> to_string() |> String.upcase()

    case valid_plan_name?(plan_name) do
      false ->
        {:error, "Invalid plan name: #{plan_name}"}

      true ->
        product_id =
          Product.id_by_code(Map.get(args, :product)) || context[:requested_product_id] ||
            context[:subscription_product_id] || Product.product_api()

        product_code = Product.code_by_id(product_id)

        filter = Map.get(args, :filter)

        # A grant belongs to one customer, so it is only applied when the caller is asking
        # about their own plan - naming a plan explicitly asks what that plan gives, not
        # what this customer happens to have been granted on top of it.
        grant =
          if asked_for_another_plan?,
            do: nil,
            else: Sanbase.Billing.Subscription.grant(context[:auth][:subscription])

        Cache.wrap(
          fn ->
            restrictions =
              Sanbase.Billing.Plan.Restrictions.get_all(
                plan_name,
                product_code,
                filter,
                nil,
                grant
              )

            {:ok, restrictions}
          end,
          # The grant is part of the key. Without it one granted customer's wider windows
          # would be cached under the plan name and served to everyone else on that plan.
          {:get_access_restrictions, plan_name, product_code, filter, grant_cache_key(grant)}
        ).()
    end
  end

  # Only the parts a grant can change the answer with. `nil` for the overwhelming
  # majority of callers, which keeps their cache key exactly what it was before.
  #
  # The values go in whole rather than hashed here: `Cache.cache_key/3` already
  # SHA-256s the finished key, so pre-hashing would only add a 32-bit collision
  # surface in front of it - and a collision means one customer's wider windows
  # served to another.
  defp grant_cache_key(nil), do: nil

  defp grant_cache_key(%Sanbase.Billing.Subscription.Grant{} = grant) do
    {grant.full_history_packages, grant.full_history_metrics}
  end

  defp valid_plan_name?("CUSTOM_" <> _), do: true

  # A bundle's restrictions cannot be listed from its name. Every bundle
  # subscription is named `BUNDLE` and each one allows something different, so
  # there is no single answer to "what does BUNDLE allow?".
  #
  # This has to be rejected here rather than left to fail further along: `plan` is
  # a free-form string argument on a query marked `access: :free`, so without this
  # any caller could reach the bundle access path with no entitlement and turn a
  # deliberate `MissingEntitlementError` into an unauthenticated 500.
  defp valid_plan_name?(plan_name) do
    Sanbase.Billing.Plan.type(plan_name) != :bundle and
      plan_name in Sanbase.Billing.Plan.existing_plan_names()
  end

  def available_versions(
        %{type: "metric"} = restriction,
        _args,
        %{context: %{loader: loader}} = resolution
      ) do
    loader
    |> Dataloader.load(SanbaseDataloader, :available_metric_versions, restriction.name)
    |> on_load(fn loader ->
      versions =
        Dataloader.get(
          loader,
          SanbaseDataloader,
          :available_metric_versions,
          restriction.name
        ) || []

      metric_access_level = resolution_to_metric_access_level(resolution)

      versions_maps =
        versions
        |> Enum.reject(fn ver -> ver =~ "Experimental" and metric_access_level != "alpha" end)
        |> Enum.map(fn version -> %{version: version} end)

      {:ok, versions_maps}
    end)
  end

  def available_versions(%{type: _}, _args, _resolution), do: {:ok, []}

  def get_access_control(_root, _args, _resolution) do
    {:error, "The query does not have a product key in the context."}
  end

  defp resolution_to_metric_access_level(resolution) do
    get_in(resolution.context, [:auth, :current_user, Access.key(:metric_access_level)]) ||
      "released"
  end
end
