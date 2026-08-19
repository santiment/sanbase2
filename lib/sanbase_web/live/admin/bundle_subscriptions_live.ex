defmodule SanbaseWeb.Admin.BundleSubscriptionsLive do
  @moduledoc ~s"""
  Create, edit and inspect bundle subscriptions, and check what one actually
  grants.

  ## Two testers, and why both

  **Decide** calls the same functions the GraphQL middleware calls, handing in the
  stored entitlement. It proves the decision logic - entitlement, access map,
  allow or deny - with no side effects and no ClickHouse.

  **Request** POSTs to the real `/graphql` endpoint with an API key. It goes
  through the actual plug pipeline, so it also proves the part *Decide cannot*:
  that a live request carries the entitlement from the request context to the
  access checker. If that plumbing broke, Decide would still say "allowed" while
  every real call returned an error.

  ## Subscriptions created here have no Stripe object

  There is no purchase flow yet, so this writes a `subscriptions` row directly
  with `stripe_id: nil`. That is deliberate and it is how the whole path is
  testable before any Stripe work - but it means these are local test rows, not
  billable subscriptions, and nothing will ever invoice for them.

  See task OB in `docs/composable-api-plans-handover.md`.
  """

  use SanbaseWeb, :live_view

  import Ecto.Query

  alias Sanbase.Accounts.Apikey
  alias Sanbase.Accounts.User
  alias Sanbase.Billing.Plan
  alias Sanbase.Billing.Plan.AccessChecker
  alias Sanbase.Billing.Plan.Bundle
  alias Sanbase.Billing.Plan.Bundle.ApiCallAddon
  alias Sanbase.Billing.Plan.Bundle.Package
  alias Sanbase.Billing.Plan.Bundle.PackageSnapshot
  alias Sanbase.Billing.Plan.Bundle.Resolver
  alias Sanbase.Billing.Subscription
  alias Sanbase.Billing.Subscription.Item
  alias Sanbase.Repo

  @products ["SANAPI", "SANBASE"]
  @default_probe "price_usd"

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Bundle Subscriptions")
     |> assign(:products, @products)
     |> assign(:user_query, "")
     |> assign(:user_matches, [])
     |> assign(:selected_user, nil)
     |> assign(:new_interval, "month")
     |> assign(:new_packages, MapSet.new())
     |> assign(:new_addon_quantity, 0)
     |> assign(:selected_id, nil)
     |> assign(:probe, @default_probe)
     |> assign(:probe_kind, "metric")
     |> assign(:probe_result, nil)
     |> assign(:scenario_results, [])
     |> assign(:inspected_name, nil)
     |> assign(:compare_plan, "PRO")
     |> assign(:apikey, "")
     |> assign(:request_result, nil)
     |> assign(:requesting?, false)
     |> load()
     |> assign_name_suggestions()}
  end

  # ── Creating ────────────────────────────────────────────────────────────

  @impl true
  def handle_event("search_user", %{"value" => query}, socket) do
    {:noreply, socket |> assign(:user_query, query) |> assign(:user_matches, search_users(query))}
  end

  def handle_event("select_user", %{"id" => id}, socket) do
    with {user_id, ""} <- Integer.parse(id),
         {:ok, user} <- User.by_id(user_id) do
      {:noreply,
       socket
       |> assign(:selected_user, user)
       |> assign(:user_query, user.email || "user##{user.id}")
       |> assign(:user_matches, [])}
    else
      _ -> {:noreply, put_flash(socket, :error, "Could not load that user.")}
    end
  end

  def handle_event("clear_user", _params, socket) do
    {:noreply,
     socket
     |> assign(:selected_user, nil)
     |> assign(:user_query, "")
     |> assign(:user_matches, [])}
  end

  def handle_event("set_interval", %{"interval" => interval}, socket)
      when interval in ["month", "year"] do
    {:noreply, assign(socket, :new_interval, interval)}
  end

  def handle_event("toggle_new_package", %{"slug" => slug}, socket) do
    packages = socket.assigns.new_packages

    packages =
      if MapSet.member?(packages, slug),
        do: MapSet.delete(packages, slug),
        else: MapSet.put(packages, slug)

    {:noreply, assign(socket, :new_packages, packages)}
  end

  def handle_event("set_addon_quantity", %{"value" => value}, socket) do
    {:noreply, assign(socket, :new_addon_quantity, parse_non_negative(value, 0))}
  end

  def handle_event("create", _params, socket) do
    %{selected_user: user, new_packages: packages, new_interval: interval} = socket.assigns

    cond do
      is_nil(user) ->
        {:noreply, put_flash(socket, :error, "Pick a user first.")}

      MapSet.size(packages) == 0 ->
        {:noreply, put_flash(socket, :error, "Pick at least one package.")}

      is_nil(PackageSnapshot.latest()) ->
        {:noreply,
         put_flash(
           socket,
           :error,
           "No package snapshot has been published. Publish one on the Bundle Packages page first."
         )}

      true ->
        create_bundle_subscription(socket, user, packages, interval)
    end
  end

  # ── Editing an existing one ─────────────────────────────────────────────

  def handle_event("select_subscription", %{"id" => id}, socket) do
    {:noreply,
     socket
     |> assign(:selected_id, parse_non_negative(id, nil))
     |> assign(:probe_result, nil)
     |> assign(:scenario_results, [])
     |> assign(:inspected_name, nil)
     |> assign(:request_result, nil)}
  end

  def handle_event("toggle_item", %{"id" => id, "sku" => sku, "type" => type}, socket) do
    with_subscription(socket, id, fn socket, subscription ->
      result =
        case Enum.find(subscription.items, &(&1.sku == sku)) do
          nil ->
            Item.create(%{
              subscription_id: subscription.id,
              sku: sku,
              type: String.to_existing_atom(type)
            })

          item ->
            Repo.delete(item)
        end

      after_item_change(socket, subscription.id, result)
    end)
  end

  def handle_event(
        "set_item_quantity",
        %{"_id" => id, "sku" => sku, "quantity" => quantity},
        socket
      ) do
    with_subscription(socket, id, fn socket, subscription ->
      quantity = parse_non_negative(quantity, 0)
      existing = Enum.find(subscription.items, &(&1.sku == sku))

      result =
        cond do
          quantity == 0 and existing ->
            Repo.delete(existing)

          quantity == 0 ->
            {:ok, :noop}

          existing ->
            existing |> Item.changeset(%{quantity: quantity}) |> Repo.update()

          true ->
            Item.create(%{
              subscription_id: subscription.id,
              sku: sku,
              type: :api_calls,
              quantity: quantity
            })
        end

      after_item_change(socket, subscription.id, result)
    end)
  end

  def handle_event("resync", %{"id" => id}, socket) do
    with_subscription(socket, id, fn socket, subscription ->
      {:noreply, socket |> resync(subscription.id) |> load()}
    end)
  end

  def handle_event("cancel_subscription", %{"id" => id}, socket) do
    set_status(socket, id, :canceled, "Subscription canceled.")
  end

  def handle_event("reactivate_subscription", %{"id" => id}, socket) do
    set_status(socket, id, :active, "Subscription reactivated.")
  end

  # Only the rows this page created can be deleted. Deleting one backed by a Stripe object
  # leaves that subscription live and billing, with nothing local to track it by - no
  # items, no entitlement, no row for the webhook to reconcile against. Cancelling is what
  # ends a real subscription, and its button sits right next to this one.
  def handle_event("delete_subscription", %{"id" => id}, socket) do
    with_subscription(socket, id, fn
      socket, %Subscription{stripe_id: stripe_id} when is_binary(stripe_id) ->
        {:noreply,
         put_flash(
           socket,
           :error,
           "This subscription exists in Stripe (#{stripe_id}) and cannot be deleted here - " <>
             "cancel it instead, or it keeps billing with nothing local to track it."
         )}

      socket, subscription ->
        delete_local_subscription(socket, subscription)
    end)
  end

  # ── Decide: the offline access check ────────────────────────────────────

  def handle_event("set_probe", %{"probe" => probe, "kind" => kind}, socket) do
    {:noreply,
     socket
     |> assign(:probe, probe)
     |> assign(:probe_kind, kind)
     |> assign(:inspected_name, nil)
     |> assign(:probe_result, decide(socket, probe, kind))}
  end

  # Only the kind, so the autocomplete list swaps to queries or signals as soon
  # as the select changes rather than after Check is pressed.
  def handle_event("set_probe_kind", %{"kind" => kind}, socket) do
    {:noreply, assign(socket, :probe_kind, kind)}
  end

  def handle_event("set_compare_plan", %{"plan" => plan}, socket) do
    socket = assign(socket, :compare_plan, plan)

    {:noreply,
     assign(
       socket,
       :probe_result,
       decide(socket, socket.assigns.probe, socket.assigns.probe_kind)
     )}
  end

  def handle_event("run_scenarios", _params, socket) do
    {:noreply,
     socket
     |> assign(:scenario_results, run_scenarios(socket))
     |> assign(:inspected_name, nil)}
  end

  # Expands the row in place: the Decide card sits above the table, so pushing the result
  # only up there looked like the button did nothing. It still fills the Decide form, so
  # the same check can be varied by hand afterwards.
  def handle_event("probe_scenario", %{"kind" => kind, "name" => name}, socket) do
    if socket.assigns.inspected_name == name do
      {:noreply, assign(socket, :inspected_name, nil)}
    else
      socket = socket |> assign(:probe, name) |> assign(:probe_kind, kind)

      {:noreply,
       socket
       |> assign(:inspected_name, name)
       |> assign(:probe_result, decide(socket, name, kind))}
    end
  end

  # ── Request: the real GraphQL call ──────────────────────────────────────

  def handle_event("set_apikey", %{"value" => apikey}, socket) do
    {:noreply, assign(socket, :apikey, String.trim(apikey))}
  end

  def handle_event("generate_own_apikey", _params, socket) do
    # Only ever for the signed-in admin's own account. Minting or displaying a
    # key for someone else would hand over their identity, which is a bigger
    # power than anything else on this page.
    case Apikey.generate_apikey(socket.assigns.current_user) do
      {:ok, apikey} ->
        {:noreply,
         socket
         |> assign(:apikey, apikey)
         |> put_flash(:info, "Generated an API key for your own account.")}

      {:error, error} ->
        {:noreply, put_flash(socket, :error, "Could not generate a key: #{inspect(error)}")}
    end
  end

  def handle_event("send_request", %{"metric" => metric}, socket) do
    metric = String.trim(metric)

    cond do
      socket.assigns.apikey == "" ->
        {:noreply, put_flash(socket, :error, "Paste an API key first.")}

      metric == "" ->
        {:noreply, put_flash(socket, :error, "Give a metric name.")}

      true ->
        # Bound outside the closure so only the two strings cross into the async
        # process, not the whole socket.
        apikey = socket.assigns.apikey

        {:noreply,
         socket
         |> assign(:requesting?, true)
         |> assign(:request_result, nil)
         |> start_async(:graphql_request, fn -> run_graphql(apikey, metric) end)}
    end
  end

  @impl true
  def handle_async(:graphql_request, {:ok, result}, socket) do
    {:noreply, socket |> assign(:requesting?, false) |> assign(:request_result, result)}
  end

  def handle_async(:graphql_request, {:exit, reason}, socket) do
    {:noreply,
     socket
     |> assign(:requesting?, false)
     |> assign(:request_result, %{status: nil, body: "Request crashed: #{inspect(reason)}"})}
  end

  # The page can be open in two tabs, or left open while a row is deleted elsewhere. Every
  # handler acting on a row goes through here, so a stale id gives a message and a reload
  # instead of a nil reaching `.items`, a changeset or a delete. Read from the database,
  # not the loaded list: a row deleted elsewhere is still in the list an earlier render
  # loaded, and updating that struct raises Ecto.StaleEntryError instead of saying it is
  # gone.
  defp with_subscription(socket, id, fun) do
    case fetch_subscription(id) do
      nil ->
        {:noreply,
         socket
         |> put_flash(:error, "That subscription no longer exists - reloaded the list.")
         |> assign(:selected_id, nil)
         |> load()}

      subscription ->
        fun.(socket, subscription)
    end
  end

  defp fetch_subscription(id) do
    case parse_non_negative(id, nil) do
      nil -> nil
      id -> Subscription.get_bundle_subscription(id)
    end
  end

  defp delete_local_subscription(socket, subscription) do
    case Repo.delete(subscription) do
      {:ok, _} ->
        {:noreply,
         socket
         |> put_flash(:info, "Deleted the test subscription and its items.")
         |> assign(:selected_id, nil)
         |> load()}

      {:error, changeset} ->
        {:noreply, put_flash(socket, :error, changeset_message(changeset))}
    end
  end

  defp set_status(socket, id, status, message) do
    with_subscription(socket, id, fn socket, subscription ->
      case subscription |> Subscription.changeset(%{status: status}) |> Repo.update() do
        {:ok, _} -> {:noreply, socket |> put_flash(:info, message) |> load()}
        {:error, changeset} -> {:noreply, put_flash(socket, :error, changeset_message(changeset))}
      end
    end)
  end

  defp after_item_change(socket, subscription_id, {:ok, _}),
    do: {:noreply, socket |> resync(subscription_id) |> load()}

  defp after_item_change(socket, _subscription_id, {:error, changeset}),
    do: {:noreply, put_flash(socket, :error, changeset_message(changeset))}

  # ── Data ────────────────────────────────────────────────────────────────

  defp load(socket) do
    subscriptions = Subscription.list_bundle_subscriptions()

    socket
    |> assign(:subscriptions, subscriptions)
    |> assign(:latest_snapshot, PackageSnapshot.latest())
  end

  # Assigned once in mount rather than called from the template: these are ~1200 names, and
  # as assigns that never change LiveView keeps them out of every diff, while a template
  # function call would be re-sent on every keystroke. Metrics are the union of what the
  # API serves and what the snapshot sells - the lists differ, and any name appearing in a
  # scenario has to be suggestable.
  defp assign_name_suggestions(socket) do
    snapshot_metrics =
      case socket.assigns.latest_snapshot do
        nil -> []
        %PackageSnapshot{contents: contents} -> contents |> Map.values() |> List.flatten()
      end

    socket
    |> assign(:metric_names, sorted_names(Sanbase.Metric.available_metrics() ++ snapshot_metrics))
    |> assign(:signal_names, sorted_names(Sanbase.Signal.available_signals()))
    |> assign(:query_names, sorted_names(all_query_names()))
  end

  defp all_query_names do
    Sanbase.Billing.ApiInfo.get_queries_with_access_level(:free) ++
      Sanbase.Billing.ApiInfo.get_queries_with_access_level(:restricted) ++
      Sanbase.Billing.ApiInfo.get_queries_without_access_level()
  end

  defp sorted_names(names) do
    names |> Enum.map(&to_string/1) |> Enum.uniq() |> Enum.sort()
  end

  defp datalist_id("query"), do: "query-names"
  defp datalist_id("signal"), do: "signal-names"
  defp datalist_id(_metric), do: "metric-names"

  defp selected(assigns) do
    Enum.find(assigns.subscriptions, &(&1.id == assigns.selected_id))
  end

  defp create_bundle_subscription(socket, user, packages, interval) do
    plan = bundle_plan(interval)

    if is_nil(plan) do
      {:noreply,
       put_flash(
         socket,
         :error,
         "No BUNDLE plan row for interval #{interval}. Run priv/repo/seed_plans_and_products.exs."
       )}
    else
      addon_quantity = socket.assigns.new_addon_quantity

      # Rolled back rather than matched with `{:ok, _} =`: a MatchError would abort the
      # transaction with a crash, the {:error, reason} branch below would never be
      # reached, and the admin would get a dead page instead of a message.
      Repo.transaction(fn ->
        with {:ok, subscription} <- insert_subscription(user, plan),
             :ok <- create_package_items(subscription, packages),
             :ok <- create_addon_item(subscription, addon_quantity) do
          subscription
        else
          {:error, reason} -> Repo.rollback(reason)
        end
      end)
      |> case do
        {:ok, subscription} ->
          socket = resync(socket, subscription.id, reload_first: true)

          {:noreply,
           socket
           |> put_flash(:info, "Created a bundle subscription for #{user.email || user.id}.")
           |> assign(:selected_id, subscription.id)
           |> assign(:new_packages, MapSet.new())
           |> assign(:new_addon_quantity, 0)
           |> load()}

        {:error, %Ecto.Changeset{} = changeset} ->
          {:noreply,
           put_flash(socket, :error, "Could not create: #{changeset_message(changeset)}")}

        {:error, reason} ->
          {:noreply, put_flash(socket, :error, "Could not create: #{inspect(reason)}")}
      end
    end
  end

  # Inserted through the changeset, not Subscription.create/1: create/1 emits a
  # :create_subscription billing event, and these rows have no Stripe object - the event
  # fails validation, and the handlers behind it (emails, Discord, Stripe reconciliation)
  # have no business acting on a local test row.
  defp insert_subscription(user, plan) do
    %Subscription{}
    |> Subscription.changeset(%{
      user_id: user.id,
      plan_id: plan.id,
      status: :active,
      type: :fiat
    })
    |> Repo.insert()
  end

  defp create_package_items(subscription, packages) do
    Enum.reduce_while(MapSet.to_list(packages), :ok, fn slug, :ok ->
      case Item.create(%{subscription_id: subscription.id, sku: slug, type: :package}) do
        {:ok, _} -> {:cont, :ok}
        {:error, changeset} -> {:halt, {:error, changeset}}
      end
    end)
  end

  defp create_addon_item(_subscription, quantity) when quantity <= 0, do: :ok

  defp create_addon_item(subscription, quantity) do
    case Item.create(%{
           subscription_id: subscription.id,
           sku: hd(ApiCallAddon.skus()),
           type: :api_calls,
           quantity: quantity
         }) do
      {:ok, _} -> :ok
      {:error, changeset} -> {:error, changeset}
    end
  end

  defp resync(socket, subscription_id, opts \\ []) do
    socket = if Keyword.get(opts, :reload_first, false), do: load(socket), else: socket

    case Resolver.sync(subscription_id) do
      {:ok, _subscription} ->
        socket

      {:error, message} when is_binary(message) ->
        put_flash(socket, :error, message)

      {:error, changeset} ->
        put_flash(socket, :error, changeset_message(changeset))
    end
  end

  defp bundle_plan(interval) do
    from(p in Plan, where: p.name == "BUNDLE" and p.interval == ^interval, limit: 1)
    |> Repo.one()
  end

  defp search_users(query) when byte_size(query) < 2, do: []

  defp search_users(query) do
    query = String.trim(query)
    pattern = "%" <> query <> "%"

    base =
      from(u in User,
        where: ilike(u.email, ^pattern) or ilike(u.username, ^pattern),
        order_by: [desc: u.id],
        limit: 8,
        select: %{id: u.id, email: u.email, username: u.username}
      )

    case Integer.parse(query) do
      {id, ""} -> from(u in base, or_where: u.id == ^id)
      _ -> base
    end
    |> Repo.all()
  end

  # ── The offline decision ────────────────────────────────────────────────

  # Both products: a bundle lives on SanAPI but a Sanbase request falls back to it
  # (auth_plug.ex find_best_subscription/2), so the same entitlement answers on both - and
  # the Sanbase side is where unimplemented functions still raise.
  defp decide(socket, probe, kind) do
    case {selected(socket.assigns), build_query_or_argument(kind, probe)} do
      {nil, _} ->
        nil

      {_, {:error, message}} ->
        %{error: message}

      {subscription, {:ok, query_or_argument}} ->
        entitlement = Subscription.bundle_entitlement(subscription)
        compare_plan = socket.assigns.compare_plan

        %{
          item: query_or_argument,
          bundle:
            Map.new(@products, &{&1, verdict(query_or_argument, &1, "BUNDLE", entitlement)}),
          compare: Map.new(@products, &{&1, verdict(query_or_argument, &1, compare_plan, nil)}),
          compare_plan: compare_plan
        }
    end
  end

  defp verdict(query_or_argument, product, plan_name, entitlement) do
    %{
      access:
        safely(fn ->
          AccessChecker.plan_has_access?(query_or_argument, product, plan_name, entitlement)
        end),
      historical_days:
        safely(fn ->
          AccessChecker.historical_data_in_days(
            query_or_argument,
            product,
            product,
            plan_name,
            entitlement
          )
        end),
      realtime_cut_off:
        safely(fn ->
          AccessChecker.realtime_data_cut_off_in_days(
            query_or_argument,
            product,
            product,
            plan_name,
            entitlement
          )
        end)
    }
  end

  # Every function here can raise for a bundle by design, not by bug (see
  # Bundle.NotImplementedError and Bundle.MissingEntitlementError). Showing which error
  # came back is the useful part, so nothing may take the page down.
  defp safely(fun) do
    {:ok, fun.()}
  rescue
    error -> {:raised, error.__struct__ |> Module.split() |> List.last()}
  end

  defp build_query_or_argument("metric", name), do: {:ok, {:metric, String.trim(name)}}
  defp build_query_or_argument("signal", name), do: {:ok, {:signal, String.trim(name)}}

  defp build_query_or_argument("query", name) do
    {:ok, {:query, String.to_existing_atom(String.trim(name))}}
  rescue
    ArgumentError ->
      {:error,
       "#{inspect(String.trim(name))} is not a known GraphQL query name. Queries are matched as atoms, so only names the schema already defines can be checked."}
  end

  # ── Generated scenarios ─────────────────────────────────────────────────

  # Derived from what this subscription actually bought, not a fixed list: owning Social
  # and Development gives "a Social metric must be allowed", "a Development metric must be
  # allowed", and one "must be refused" per package not bought. Each scenario carries its
  # own expectation, so the table shows pass/fail instead of leaving you to work out
  # whether "refused" was right.
  defp scenarios(nil, _snapshot), do: []
  defp scenarios(_subscription, nil), do: []

  defp scenarios(subscription, %PackageSnapshot{contents: contents}) do
    case Subscription.bundle_entitlement(subscription) do
      nil ->
        []

      %{packages: owned} ->
        owned_set = MapSet.new(owned)

        package_scenarios =
          Enum.flat_map(Package.all(), fn package ->
            bought? = MapSet.member?(owned_set, package.slug)

            case sample_metric(contents, package.slug) do
              nil ->
                []

              metric ->
                [
                  %{
                    label: "#{package.name} metric",
                    kind: "metric",
                    name: metric,
                    expected: bought?,
                    why:
                      if(bought?,
                        do: "bought this package",
                        else: "did not buy this package"
                      )
                  }
                ]
            end
          end)

        package_scenarios ++
          [
            %{
              label: "Any query",
              kind: "query",
              name: "get_trending_words",
              expected: true,
              why: "every bundle gets all queries (§6.4)"
            },
            %{
              label: "Unknown metric",
              kind: "metric",
              name: "not_a_real_metric_xyz",
              expected: false,
              why: "not in any package"
            }
          ]
    end
  end

  # One representative metric per package. Sorted lists mean this is stable
  # between reloads, so a scenario that failed can be looked at again.
  defp sample_metric(contents, slug) do
    contents |> Map.get(slug, []) |> List.first()
  end

  defp run_scenarios(socket) do
    subscription = selected(socket.assigns)

    entitlement = Subscription.bundle_entitlement(subscription)

    scenarios(subscription, socket.assigns.latest_snapshot)
    |> Enum.map(fn scenario ->
      actual =
        case build_query_or_argument(scenario.kind, scenario.name) do
          {:ok, query_or_argument} ->
            safely(fn ->
              AccessChecker.plan_has_access?(
                query_or_argument,
                "SANAPI",
                "BUNDLE",
                entitlement
              )
            end)

          {:error, _} ->
            {:raised, "BadName"}
        end

      Map.put(scenario, :actual, actual)
    end)
  end

  # ── The real request ────────────────────────────────────────────────────

  defp graphql_url, do: SanbaseWeb.Endpoint.url() <> "/graphql"

  defp graphql_document(metric) do
    """
    {
      getMetric(metric: "#{metric}") {
        timeseriesData(
          slug: "bitcoin"
          from: "#{Timex.shift(DateTime.utc_now(), days: -7) |> DateTime.to_iso8601()}"
          to: "#{DateTime.utc_now() |> DateTime.to_iso8601()}"
          interval: "1d"
        ) { datetime value }
      }
    }
    """
  end

  defp run_graphql(apikey, metric) do
    body = Jason.encode!(%{query: graphql_document(metric)})

    headers = [
      {"Content-Type", "application/json"},
      {"Authorization", "Apikey " <> apikey}
    ]

    case HTTPoison.post(graphql_url(), body, headers, recv_timeout: 30_000) do
      {:ok, %HTTPoison.Response{status_code: status, body: response_body}} ->
        %{status: status, body: pretty(response_body)}

      {:error, %HTTPoison.Error{reason: reason}} ->
        %{
          status: nil,
          body:
            "Could not reach #{graphql_url()}: #{inspect(reason)}\n\nIf this environment cannot reach its own endpoint, use the curl command below instead."
        }
    end
  end

  defp pretty(body) do
    case Jason.decode(body) do
      {:ok, decoded} -> Jason.encode!(decoded, pretty: true)
      _ -> body
    end
  end

  defp curl_command(apikey, metric) do
    key = if apikey == "", do: "<your-api-key>", else: Apikey.mask_apikey(apikey)

    """
    curl -s #{graphql_url()} \\
      -H 'Content-Type: application/json' \\
      -H 'Authorization: Apikey #{key}' \\
      -d '#{Jason.encode!(%{query: graphql_document(metric)})}'
    """
  end

  # ── Small helpers ───────────────────────────────────────────────────────

  defp parse_non_negative(value, default) do
    case value |> to_string() |> String.trim() |> Integer.parse() do
      {number, ""} when number >= 0 -> number
      _ -> default
    end
  end

  defp changeset_message(changeset) do
    changeset
    |> Ecto.Changeset.traverse_errors(fn {message, _opts} -> message end)
    |> Enum.map_join("; ", fn {field, messages} ->
      "#{field}: #{Enum.join(List.wrap(messages), ", ")}"
    end)
  end

  defp has_item?(subscription, sku), do: Enum.any?(subscription.items, &(&1.sku == sku))

  defp item_quantity(subscription, sku) do
    case Enum.find(subscription.items, &(&1.sku == sku)) do
      nil -> 0
      item -> item.quantity
    end
  end

  defp package_names(subscription) do
    case Subscription.bundle_entitlement(subscription) do
      nil -> "—"
      %{packages: []} -> "—"
      %{packages: packages} -> Enum.join(packages, ", ")
    end
  end

  defp monthly_calls(subscription) do
    case Subscription.bundle_entitlement(subscription) do
      nil -> nil
      entitlement -> Bundle.Access.api_call_limits(entitlement).month
    end
  end

  defp metric_count(subscription) do
    case Subscription.bundle_entitlement(subscription) do
      nil -> 0
      entitlement -> entitlement.metric_access |> Map.get("accessible", []) |> length()
    end
  end

  defp verdict_label({:ok, true}), do: {"allowed", "badge-success"}
  defp verdict_label({:ok, false}), do: {"refused", "badge-error"}
  defp verdict_label({:ok, nil}), do: {"no limit", "badge-ghost"}
  defp verdict_label({:ok, value}), do: {to_string(value), "badge-ghost"}
  defp verdict_label({:raised, error}), do: {error, "badge-warning"}

  attr :verdict, :any, required: true

  defp verdict_badge(assigns) do
    {label, class} = verdict_label(assigns.verdict)
    assigns = assigns |> assign(:label, label) |> assign(:class, class)

    ~H"""
    <span class={["badge badge-sm", @class]}>{@label}</span>
    """
  end

  attr :products, :list, required: true
  attr :result, :map, required: true

  defp verdict_table(assigns) do
    ~H"""
    <table class="table table-sm">
      <thead>
        <tr>
          <th>Plan</th>
          <th :for={product <- @products}>{product} access</th>
          <th :for={product <- @products}>{product} history</th>
          <th :for={product <- @products}>{product} realtime</th>
        </tr>
      </thead>
      <tbody>
        <tr>
          <td class="font-medium">BUNDLE</td>
          <td :for={product <- @products}>
            <.verdict_badge verdict={@result.bundle[product].access} />
          </td>
          <td :for={product <- @products}>
            <.verdict_badge verdict={@result.bundle[product].historical_days} />
          </td>
          <td :for={product <- @products}>
            <.verdict_badge verdict={@result.bundle[product].realtime_cut_off} />
          </td>
        </tr>
        <tr class="text-base-content/60">
          <td class="font-medium">{@result.compare_plan}</td>
          <td :for={product <- @products}>
            <.verdict_badge verdict={@result.compare[product].access} />
          </td>
          <td :for={product <- @products}>
            <.verdict_badge verdict={@result.compare[product].historical_days} />
          </td>
          <td :for={product <- @products}>
            <.verdict_badge verdict={@result.compare[product].realtime_cut_off} />
          </td>
        </tr>
      </tbody>
    </table>
    """
  end

  attr :metric_names, :list, required: true
  attr :query_names, :list, required: true
  attr :signal_names, :list, required: true

  defp name_datalists(assigns) do
    ~H"""
    <datalist id="metric-names">
      <option :for={name <- @metric_names} value={name}></option>
    </datalist>
    <datalist id="query-names">
      <option :for={name <- @query_names} value={name}></option>
    </datalist>
    <datalist id="signal-names">
      <option :for={name <- @signal_names} value={name}></option>
    </datalist>
    """
  end

  @impl true
  def render(assigns) do
    assigns = assign(assigns, :selected, selected(assigns))

    ~H"""
    <div class="bg-base-200/40 min-h-full">
      <.name_datalists
        metric_names={@metric_names}
        query_names={@query_names}
        signal_names={@signal_names}
      />

      <div class="max-w-6xl mx-auto px-6 py-8 space-y-6">
        <div class="flex items-start justify-between gap-4">
          <div>
            <h1 class="text-3xl font-bold">Bundle Subscriptions</h1>
            <p class="text-sm text-base-content/60 mt-1">
              Build a bundle subscription and check what it actually grants.
            </p>
          </div>

          <.link navigate={~p"/admin/bundle_packages"} class="btn btn-sm btn-soft shrink-0">
            Bundle packages
          </.link>
        </div>

        <div role="alert" class="alert alert-warning">
          <span class="text-sm">
            Subscriptions created here have <strong>no Stripe object</strong> and will never be
            invoiced. They exist so the entitlement path can be tested before the purchase flow is
            built.
          </span>
        </div>

        <div :if={is_nil(@latest_snapshot)} role="alert" class="alert alert-error">
          <span class="text-sm">
            No package snapshot has been published, so no entitlement can be resolved.
            <.link navigate={~p"/admin/bundle_packages"} class="link">Publish one first.</.link>
          </span>
        </div>

        <%!-- ── Create ──────────────────────────────────────────────────── --%>
        <div class="card bg-base-100 border border-base-300 p-4 space-y-4">
          <h2 class="font-semibold">Create a bundle subscription</h2>

          <div class="relative">
            <fieldset class="fieldset">
              <legend class="fieldset-legend">User (email, username or id)</legend>
              <div class="flex gap-2">
                <input
                  type="text"
                  value={@user_query}
                  phx-keyup="search_user"
                  phx-debounce="250"
                  placeholder="start typing..."
                  class="input input-sm w-96"
                />
                <button :if={@selected_user} phx-click="clear_user" class="btn btn-sm btn-soft">
                  Clear
                </button>
              </div>
            </fieldset>

            <ul
              :if={@user_matches != []}
              class="menu bg-base-100 border border-base-300 rounded-box absolute z-10 w-96 shadow-lg"
            >
              <li :for={match <- @user_matches}>
                <a phx-click="select_user" phx-value-id={match.id}>
                  {match.email || match.username || "user##{match.id}"}
                  <span class="text-xs text-base-content/50">#{match.id}</span>
                </a>
              </li>
            </ul>
          </div>

          <div class="flex flex-wrap items-end gap-4">
            <fieldset class="fieldset">
              <legend class="fieldset-legend">Interval</legend>
              <div class="join">
                <button
                  :for={interval <- ["month", "year"]}
                  phx-click="set_interval"
                  phx-value-interval={interval}
                  class={[
                    "btn btn-sm join-item",
                    if(@new_interval == interval, do: "btn-primary", else: "btn-soft")
                  ]}
                >
                  {interval}
                </button>
              </div>
            </fieldset>

            <fieldset class="fieldset">
              <legend class="fieldset-legend">Extra API call add-ons (× 500k)</legend>
              <input
                type="text"
                value={@new_addon_quantity}
                phx-blur="set_addon_quantity"
                class="input input-sm w-20"
              />
            </fieldset>
          </div>

          <fieldset class="fieldset">
            <legend class="fieldset-legend">Packages</legend>
            <div class="flex flex-wrap gap-2">
              <button
                :for={package <- Package.all()}
                phx-click="toggle_new_package"
                phx-value-slug={package.slug}
                class={[
                  "btn btn-sm",
                  if(MapSet.member?(@new_packages, package.slug),
                    do: "btn-primary",
                    else: "btn-soft"
                  )
                ]}
              >
                {package.name}
              </button>
            </div>
          </fieldset>

          <button
            phx-click="create"
            disabled={is_nil(@selected_user) or MapSet.size(@new_packages) == 0}
            class="btn btn-sm btn-primary self-start"
          >
            Create subscription
          </button>
        </div>

        <%!-- ── Existing ────────────────────────────────────────────────── --%>
        <div class="card bg-base-100 border border-base-300 overflow-hidden">
          <div class="px-4 pt-4">
            <h2 class="font-semibold">Existing bundle subscriptions</h2>
          </div>

          <table class="table table-sm">
            <thead>
              <tr>
                <th>#</th>
                <th>User</th>
                <th>Interval</th>
                <th>Status</th>
                <th>Packages</th>
                <th class="text-right">Metrics</th>
                <th class="text-right">Calls / mo</th>
                <th class="text-right">Snapshot</th>
                <th></th>
              </tr>
            </thead>
            <tbody>
              <tr
                :for={subscription <- @subscriptions}
                class={if @selected_id == subscription.id, do: "bg-base-200/60"}
              >
                <td class="text-xs">{subscription.id}</td>
                <td class="text-xs">
                  {subscription.user.email || subscription.user.username ||
                    "user##{subscription.user_id}"}
                </td>
                <td class="text-xs">{subscription.plan.interval}</td>
                <td>
                  <span class={[
                    "badge badge-sm",
                    if(subscription.status == :active, do: "badge-success", else: "badge-ghost")
                  ]}>
                    {subscription.status}
                  </span>
                </td>
                <td class="text-xs">{package_names(subscription)}</td>
                <td class="text-right text-xs">{metric_count(subscription)}</td>
                <td class="text-right text-xs">
                  {case monthly_calls(subscription) do
                    nil -> "—"
                    calls -> Number.Delimit.number_to_delimited(calls, precision: 0)
                  end}
                </td>
                <td class="text-right text-xs">
                  {case Subscription.bundle_entitlement(subscription) do
                    nil -> "—"
                    entitlement -> "v#{entitlement.package_snapshot_version}"
                  end}
                </td>
                <td class="text-right">
                  <button
                    phx-click="select_subscription"
                    phx-value-id={subscription.id}
                    class="btn btn-xs btn-soft"
                  >
                    {if @selected_id == subscription.id, do: "Selected", else: "Inspect"}
                  </button>
                </td>
              </tr>

              <tr :if={@subscriptions == []}>
                <td colspan="9" class="text-sm text-base-content/60">
                  None yet. Create one above.
                </td>
              </tr>
            </tbody>
          </table>
        </div>

        <%!-- ── Inspect the selected one ────────────────────────────────── --%>
        <div :if={@selected} class="card bg-base-100 border border-base-300 p-4 space-y-4">
          <div class="flex items-start justify-between gap-4">
            <div>
              <h2 class="font-semibold">
                Subscription #{@selected.id} — {@selected.user.email || @selected.user_id}
              </h2>
              <p class="text-xs text-base-content/60">
                Items are re-resolved into the entitlement on every change, the same way the Stripe
                webhook will do it.
              </p>
            </div>

            <div class="flex gap-2 shrink-0">
              <button phx-click="resync" phx-value-id={@selected.id} class="btn btn-xs btn-soft">
                Re-resolve
              </button>
              <button
                :if={@selected.status == :active}
                phx-click="cancel_subscription"
                phx-value-id={@selected.id}
                class="btn btn-xs btn-soft btn-warning"
              >
                Cancel
              </button>
              <button
                :if={@selected.status != :active}
                phx-click="reactivate_subscription"
                phx-value-id={@selected.id}
                class="btn btn-xs btn-soft"
              >
                Reactivate
              </button>
              <button
                phx-click="delete_subscription"
                phx-value-id={@selected.id}
                data-confirm="Delete this test subscription and its items?"
                disabled={not is_nil(@selected.stripe_id)}
                title={
                  if @selected.stripe_id,
                    do: "Exists in Stripe - cancel it instead of deleting the row",
                    else: nil
                }
                class="btn btn-xs btn-soft btn-error"
              >
                Delete
              </button>
            </div>
          </div>

          <%!-- items --%>
          <div class="flex flex-wrap gap-2">
            <button
              :for={package <- Package.all()}
              phx-click="toggle_item"
              phx-value-id={@selected.id}
              phx-value-sku={package.slug}
              phx-value-type="package"
              class={[
                "btn btn-sm",
                if(has_item?(@selected, package.slug), do: "btn-primary", else: "btn-soft")
              ]}
            >
              {package.name}
            </button>

            <form
              :for={addon <- ApiCallAddon.all()}
              phx-submit="set_item_quantity"
              class="flex items-center gap-1"
            >
              <input type="hidden" name="_id" value={@selected.id} />
              <input type="hidden" name="sku" value={addon.sku} />
              <span class="text-xs text-base-content/60">{addon.name} ×</span>
              <input
                type="text"
                name="quantity"
                value={item_quantity(@selected, addon.sku)}
                class="input input-xs w-14"
              />
              <button type="submit" class="btn btn-xs btn-soft">Set</button>
            </form>
          </div>

          <%!-- resolved entitlement --%>
          <div
            :if={entitlement = Subscription.bundle_entitlement(@selected)}
            class="grid grid-cols-2 md:grid-cols-4 gap-3"
          >
            <div class="bg-base-200/50 rounded p-3">
              <div class="text-xs text-base-content/50">Monthly calls</div>
              <div class="font-semibold">
                {Number.Delimit.number_to_delimited(entitlement.api_call_limits["month"],
                  precision: 0
                )}
              </div>
            </div>
            <div class="bg-base-200/50 rounded p-3">
              <div class="text-xs text-base-content/50">Hour / minute</div>
              <div class="font-semibold">
                {entitlement.api_call_limits["hour"]} / {entitlement.api_call_limits["minute"]}
              </div>
            </div>
            <div class="bg-base-200/50 rounded p-3">
              <div class="text-xs text-base-content/50">History</div>
              <div class="font-semibold">
                {entitlement.historical_data_in_days || "full"}
              </div>
            </div>
            <div class="bg-base-200/50 rounded p-3">
              <div class="text-xs text-base-content/50">Realtime cut-off</div>
              <div class="font-semibold">
                {entitlement.realtime_data_cut_off_in_days} day(s)
              </div>
            </div>
          </div>

          <div
            :if={is_nil(Subscription.bundle_entitlement(@selected))}
            role="alert"
            class="alert alert-warning"
          >
            <span class="text-sm">
              No entitlement stored. Add at least one package, or press Re-resolve.
            </span>
          </div>

          <div :if={entitlement = Subscription.bundle_entitlement(@selected)}>
            <div :if={Bundle.Entitlement.stale?(entitlement)} role="alert" class="alert alert-warning">
              <span class="text-sm">
                This entitlement was written by an older version of the code. Re-resolve it.
              </span>
            </div>
          </div>
        </div>

        <%!-- ── Decide ──────────────────────────────────────────────────── --%>
        <div :if={@selected} class="card bg-base-100 border border-base-300 p-4 space-y-4">
          <div>
            <h2 class="font-semibold">Decide — check access without making a request</h2>
            <p class="text-xs text-base-content/60">
              Calls the same functions the GraphQL middleware calls, with this subscription's stored
              entitlement. No side effects. Shows both products because a bundle lives on SanAPI but
              a Sanbase request falls back to it.
            </p>
          </div>

          <form phx-submit="set_probe" class="flex flex-wrap items-end gap-2">
            <fieldset class="fieldset">
              <legend class="fieldset-legend">Kind</legend>
              <select
                name="kind"
                phx-change="set_probe_kind"
                class="select select-sm w-28"
              >
                <option
                  :for={kind <- ~w(metric query signal)}
                  value={kind}
                  selected={@probe_kind == kind}
                >
                  {kind}
                </option>
              </select>
            </fieldset>

            <%!-- The button sits inside the fieldset because `.fieldset` adds
                  padding-block, so `items-end` on the row would align it to the
                  fieldset's bottom edge rather than the input's. --%>
            <fieldset class="fieldset">
              <legend class="fieldset-legend">Name</legend>
              <div class="flex gap-2">
                <input
                  type="text"
                  name="probe"
                  value={@probe}
                  list={datalist_id(@probe_kind)}
                  autocomplete="off"
                  class="input input-sm w-64"
                />
                <button type="submit" class="btn btn-sm btn-primary">Check</button>
              </div>
            </fieldset>

            <fieldset class="fieldset ml-auto">
              <legend class="fieldset-legend">Compare against</legend>
              <select
                name="plan"
                phx-change="set_compare_plan"
                class="select select-sm w-32"
              >
                <option
                  :for={
                    plan <-
                      ~w(FREE BASIC PRO PRO_PLUS MAX BUSINESS_PRO BUSINESS_MAX INSTITUTIONAL ENTERPRISE)
                  }
                  value={plan}
                  selected={@compare_plan == plan}
                >
                  {plan}
                </option>
              </select>
            </fieldset>
          </form>

          <div :if={@probe_result && @probe_result[:error]} role="alert" class="alert alert-error">
            <span class="text-sm">{@probe_result.error}</span>
          </div>

          <.verdict_table
            :if={@probe_result && @probe_result[:bundle]}
            products={@products}
            result={@probe_result}
          />

          <p :if={@probe_result && @probe_result[:bundle]} class="text-xs text-base-content/50">
            A warning badge is a raised error, not a refusal. That is the designed behavior for the
            parts of the bundle path that are not implemented yet.
          </p>
        </div>

        <%!-- ── Generated scenarios ─────────────────────────────────────── --%>
        <div :if={@selected} class="card bg-base-100 border border-base-300 p-4 space-y-4">
          <div class="flex items-start justify-between gap-4">
            <div>
              <h2 class="font-semibold">Scenarios — generated from what this bundle owns</h2>
              <p class="text-xs text-base-content/60">
                One "must be allowed" per package bought, one "must be refused" per package not
                bought, plus a query and a metric that does not exist. Each row carries its own
                expectation, so a red row is a real disagreement rather than something to interpret.
              </p>
            </div>

            <button phx-click="run_scenarios" class="btn btn-sm btn-primary shrink-0">
              Run scenarios
            </button>
          </div>

          <table :if={@scenario_results != []} class="table table-sm">
            <thead>
              <tr>
                <th>Scenario</th>
                <th>Name</th>
                <th>Expected</th>
                <th>Actual</th>
                <th>Result</th>
                <th></th>
              </tr>
            </thead>
            <tbody>
              <%= for scenario <- @scenario_results do %>
                <tr>
                  <td class="text-xs">
                    {scenario.label}
                    <div class="text-base-content/50">{scenario.why}</div>
                  </td>
                  <td><code class="text-xs">{scenario.name}</code></td>
                  <td class="text-xs">{if scenario.expected, do: "allowed", else: "refused"}</td>
                  <td><.verdict_badge verdict={scenario.actual} /></td>
                  <td>
                    <span class={[
                      "badge badge-sm",
                      if(scenario.actual == {:ok, scenario.expected},
                        do: "badge-success",
                        else: "badge-error"
                      )
                    ]}>
                      {if scenario.actual == {:ok, scenario.expected}, do: "pass", else: "FAIL"}
                    </span>
                  </td>
                  <td class="text-right">
                    <button
                      phx-click="probe_scenario"
                      phx-value-kind={scenario.kind}
                      phx-value-name={scenario.name}
                      class="btn btn-xs btn-soft"
                    >
                      {if @inspected_name == scenario.name, do: "Hide", else: "Inspect"}
                    </button>
                  </td>
                </tr>

                <tr :if={@inspected_name == scenario.name}>
                  <td colspan="6" class="bg-base-200/50">
                    <div :if={@probe_result && @probe_result[:error]} class="text-xs text-error">
                      {@probe_result.error}
                    </div>

                    <.verdict_table
                      :if={@probe_result && @probe_result[:bundle]}
                      products={@products}
                      result={@probe_result}
                    />

                    <div class="text-xs text-base-content/50">
                      Also loaded into the Decide form above, so it can be varied by hand.
                    </div>
                  </td>
                </tr>
              <% end %>
            </tbody>
          </table>

          <div :if={@scenario_results == []} class="text-sm text-base-content/60">
            Press Run scenarios.
          </div>
        </div>

        <%!-- ── Request ─────────────────────────────────────────────────── --%>
        <div class="card bg-base-100 border border-base-300 p-4 space-y-4">
          <div>
            <h2 class="font-semibold">Request — make a real GraphQL call</h2>
            <p class="text-xs text-base-content/60">
              POSTs to {graphql_url()} with an API key, through the real plug pipeline. This is the
              only check that proves a live request carries the entitlement all the way to the access
              checker. It consumes the key's quota, like any other call.
            </p>
          </div>

          <div role="alert" class="alert alert-warning">
            <span class="text-xs">
              Two things to know before reading the result. <strong>A <code>@santiment.net</code> key skips the quota check entirely</strong>, so it
              proves access but not quota — a real customer's key would behave differently.
              And the quota path for bundles is not finished: a customer who *is* subject to it gets
              an error from the quota code before access is ever consulted. Until that lands, a
              refusal here may be about quota rather than about packages, so check the message.
            </span>
          </div>

          <fieldset class="fieldset">
            <legend class="fieldset-legend">API key</legend>
            <div class="flex gap-2">
              <input
                type="text"
                value={@apikey}
                phx-blur="set_apikey"
                placeholder="paste an API key belonging to the subscribed user"
                class="input input-sm grow font-mono"
              />
              <button phx-click="generate_own_apikey" class="btn btn-sm btn-soft shrink-0">
                Generate for my own account
              </button>
            </div>
          </fieldset>

          <form phx-submit="send_request">
            <fieldset class="fieldset">
              <legend class="fieldset-legend">Metric</legend>
              <div class="flex gap-2">
                <input
                  type="text"
                  name="metric"
                  value={@probe}
                  list="metric-names"
                  autocomplete="off"
                  class="input input-sm w-64"
                />
                <button type="submit" disabled={@requesting?} class="btn btn-sm btn-primary">
                  {if @requesting?, do: "Sending...", else: "Send"}
                </button>
              </div>
            </fieldset>
          </form>

          <div :if={@request_result}>
            <div class="flex items-center gap-2 mb-1">
              <span class="text-xs text-base-content/50">HTTP</span>
              <span class={[
                "badge badge-sm",
                if(@request_result.status == 200, do: "badge-success", else: "badge-warning")
              ]}>
                {@request_result.status || "no response"}
              </span>
            </div>

            <pre class="text-xs bg-base-200/50 rounded p-3 max-h-80 overflow-auto whitespace-pre-wrap">{@request_result.body}</pre>
          </div>

          <details>
            <summary class="text-xs text-base-content/60 cursor-pointer">
              Equivalent curl (key masked — substitute your own)
            </summary>
            <pre class="text-xs bg-base-200/50 rounded p-3 mt-2 overflow-auto whitespace-pre-wrap">{curl_command(@apikey, @probe)}</pre>
          </details>
        </div>
      </div>
    </div>
    """
  end
end
