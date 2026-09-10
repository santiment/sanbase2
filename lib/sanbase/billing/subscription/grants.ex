defmodule Sanbase.Billing.Subscription.Grants do
  @moduledoc ~s"""
  Writing, refreshing and removing sales-applied grants.

  The counterpart of `Sanbase.Billing.Plan.Bundle.Resolver` for add-ons that were
  sold outside the subscription: it turns "full history on Market, plus 200,000
  calls" into the stored form the access and quota paths read. See §8 task **GR**
  of `docs/composable-api-plans-handover.md`.

  ## Expansion happens here, once

  `full_history_packages` is what sales chose; `full_history_metrics` is that
  choice resolved against the published package snapshot at the moment of the
  grant. Doing it here means an access check is a membership test rather than a
  metric-to-category lookup on every request - the same trade a bundle
  entitlement makes with its metric list.

  It also means a grant is frozen: a metric added to Market afterwards is not
  covered until `re_expand/1` is called. That is the same rule the rest of this
  epic applies to a purchase - a customer keeps what they paid for until someone
  deliberately re-resolves them - and it is why the admin screen has a re-expand
  action rather than silently refreshing.

  `"all"` is the exception. A customer who upgraded every package gets full
  history on anything they can see, including metrics that did not exist when the
  grant was written, so nothing is expanded for it.

  ## Every write refreshes the API call limits

  `Sanbase.ApiCallLimit.update_user_plan/1` runs after each change. Nothing else
  would: the daily `ApiCallLimit.Sync` reconciles on **plan name**, and a grant
  never changes one, so a granted allowance that was not pushed here would sit
  unapplied until some unrelated subscription change happened to trigger a
  refresh.
  """

  alias Sanbase.Accounts.User
  alias Sanbase.Billing.Plan.Bundle.PackageSnapshot
  alias Sanbase.Billing.Subscription
  alias Sanbase.Billing.Subscription.Grant
  alias Sanbase.Repo

  require Logger

  @type attrs :: %{
          optional(:extra_api_calls_per_month) => non_neg_integer(),
          optional(:full_history_packages) => [String.t()],
          optional(:note) => String.t()
        }

  @doc ~s"""
  Write a grant onto a subscription, replacing any grant already there.

  Replacing rather than merging is deliberate: a package dropped from the new
  grant must lose the metrics the old one expanded for it, and a merge would keep
  them.

  `granted_by` is recorded because a grant is money someone agreed to, and the
  only record of that agreement is an invoice raised elsewhere.
  """
  @spec grant(Subscription.t(), attrs(), User.t()) ::
          {:ok, Subscription.t()} | {:error, Ecto.Changeset.t() | String.t()}
  def grant(%Subscription{} = subscription, attrs, %User{} = granted_by) do
    packages = attrs |> Map.get(:full_history_packages, []) |> Enum.uniq()

    with {:ok, metrics, snapshot_version} <- expand(packages) do
      attrs =
        attrs
        |> Map.put(:full_history_packages, packages)
        |> Map.put(:full_history_metrics, metrics)
        |> Map.put(:package_snapshot_version, snapshot_version)
        |> Map.put(:granted_by_id, granted_by.id)
        |> Map.put(:granted_at, DateTime.utc_now() |> DateTime.truncate(:second))

      subscription
      |> Subscription.grant_changeset(attrs)
      |> Repo.update()
      |> refresh_api_call_limits()
    end
  end

  @doc ~s"""
  Remove the grant, putting the customer back on exactly what their plan gives.
  """
  @spec revoke(Subscription.t()) :: {:ok, Subscription.t()} | {:error, Ecto.Changeset.t()}
  def revoke(%Subscription{} = subscription) do
    subscription
    |> Subscription.grant_changeset(nil)
    |> Repo.update()
    |> refresh_api_call_limits()
  end

  @doc ~s"""
  Re-expand an existing grant against the current package snapshot, keeping
  everything else about it.

  What this is for: a grant's metric list is frozen when it is written, so a
  metric added to a granted package later is not covered. That is the intended
  default - a customer keeps what they bought - but when the omission is an
  oversight rather than a decision, this is how it is corrected, deliberately and
  visibly.
  """
  @spec re_expand(Subscription.t()) ::
          {:ok, Subscription.t()} | {:error, Ecto.Changeset.t() | String.t()}
  def re_expand(%Subscription{grant: %Grant{} = grant} = subscription) do
    with {:ok, metrics, snapshot_version} <- expand(grant.full_history_packages) do
      attrs =
        grant
        |> Map.from_struct()
        |> Map.put(:full_history_metrics, metrics)
        |> Map.put(:package_snapshot_version, snapshot_version)

      subscription
      |> Subscription.grant_changeset(attrs)
      |> Repo.update()
      |> refresh_api_call_limits()
    end
  end

  def re_expand(%Subscription{}), do: {:error, "This subscription has no grant to re-expand."}

  @doc ~s"""
  A human-readable summary of what a grant actually gives, for the admin screen.

  Deliberately describes the *result* rather than echoing the form back: the
  question someone answers with this is "did that do what I meant?", and the
  stored packages alone do not answer it.
  """
  @spec describe(Subscription.t()) :: map()
  def describe(%Subscription{grant: %Grant{} = grant} = subscription) do
    # The plan may not be loaded - callers reach this holding whatever row they had -
    # and a grant describes itself perfectly well without it.
    plan_name =
      case subscription.plan do
        %Sanbase.Billing.Plan{name: name} -> name
        _ -> nil
      end

    %{
      extra_api_calls_per_month: Grant.extra_api_calls(grant),
      full_history_packages: grant.full_history_packages,
      full_history_metric_count: length(grant.full_history_metrics || []),
      package_snapshot_version: grant.package_snapshot_version,
      snapshot_is_current?: current_snapshot?(grant),
      note: grant.note,
      granted_by_id: grant.granted_by_id,
      granted_at: grant.granted_at,
      plan_name: plan_name
    }
  end

  def describe(%Subscription{}), do: nil

  # `"all"` is stored as itself rather than expanded, so a package added later is
  # covered without anyone having to remember to re-expand.
  defp expand([]), do: {:ok, [], nil}

  defp expand(packages) do
    if Grant.all_packages() in packages do
      {:ok, [], PackageSnapshot.latest() |> version_of()}
    else
      case PackageSnapshot.latest() do
        %PackageSnapshot{} = snapshot ->
          {:ok, PackageSnapshot.metrics_for(snapshot, packages), snapshot.version}

        _ ->
          {:error,
           "No package snapshot has been published yet, so there is nothing to expand a " <>
             "full-history grant against. Publish one from /admin/bundle_packages first."}
      end
    end
  end

  defp version_of(%PackageSnapshot{version: version}), do: version
  defp version_of(_), do: nil

  defp current_snapshot?(%Grant{full_history_packages: []}), do: true

  defp current_snapshot?(%Grant{package_snapshot_version: version}) do
    case PackageSnapshot.latest() do
      %PackageSnapshot{version: ^version} -> true
      _ -> false
    end
  end

  # The subscription's user is what the api_call_limits row is keyed by. Preloaded
  # rather than assumed, because the callers here are admin screens holding a row
  # they queried for display.
  defp refresh_api_call_limits({:ok, %Subscription{} = subscription}) do
    subscription = Repo.preload(subscription, [:user, :plan])

    case subscription.user do
      %User{} = user ->
        Sanbase.ApiCallLimit.update_user_plan(user)

      _ ->
        Logger.error(
          "[Grants] Subscription #{subscription.id} has no user; API call limits not refreshed."
        )
    end

    {:ok, subscription}
  end

  defp refresh_api_call_limits(other), do: other
end
