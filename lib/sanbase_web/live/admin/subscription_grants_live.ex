defmodule SanbaseWeb.Admin.SubscriptionGrantsLive do
  @moduledoc ~s"""
  Apply the add-ons sales sold: extra monthly API calls, and full history on
  individual data packages.

  The add-on is charged as a **separate one-off Stripe invoice** raised outside
  the subscription, and then recorded here. So this screen moves entitlement, not
  money - it will not charge anyone and it will not appear on an invoice.

  ## Why this is not part of /admin/bundle_subscriptions

  That page is a test rig: it creates local subscriptions with no Stripe object,
  fires probe requests with an API key, and lists only bundles. This one acts on
  **real, paying** subscriptions, most of them Institutional, which are not
  bundles at all. Widening that page's queries would have mixed a sales tool into
  a developer tool and put a "create a fake subscription" button next to a
  customer's live plan.

  ## What a grant can and cannot do

  Only ever additive: more calls, wider history. There is deliberately no way to
  take anything away, which is what makes applying one safe without reasoning
  about how it interacts with the plan underneath.

  See §8 task **GR** of `docs/composable-api-plans-handover.md`.
  """

  use SanbaseWeb, :live_view

  import Ecto.Query

  alias Sanbase.Accounts.User
  alias Sanbase.Billing.Plan.Bundle.Package
  alias Sanbase.Billing.Plan.Bundle.PackageSnapshot
  alias Sanbase.Billing.Subscription
  alias Sanbase.Billing.Subscription.Grant
  alias Sanbase.Billing.Subscription.Grants
  alias Sanbase.Repo

  @active_statuses [:active, :past_due, :trialing]

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Subscription grants")
     |> assign(:user_query, "")
     |> assign(:user_matches, [])
     |> assign(:selected_user, nil)
     |> assign(:subscriptions, [])
     |> assign(:selected_id, nil)
     |> assign(:form_extra_calls, 0)
     |> assign(:form_packages, MapSet.new())
     |> assign(:form_note, "")
     |> assign(:latest_snapshot, PackageSnapshot.latest())}
  end

  # ── Finding the customer ────────────────────────────────────────────────

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
       |> assign(:user_matches, [])
       |> assign(:user_query, user.email || user.username || "user##{user.id}")
       |> assign(:selected_id, nil)
       |> load_subscriptions()}
    else
      _ -> {:noreply, put_flash(socket, :error, "Could not load that user.")}
    end
  end

  def handle_event("clear_user", _params, socket) do
    {:noreply,
     socket
     |> assign(:selected_user, nil)
     |> assign(:user_query, "")
     |> assign(:user_matches, [])
     |> assign(:subscriptions, [])
     |> assign(:selected_id, nil)}
  end

  def handle_event("select_subscription", %{"id" => id}, socket) do
    socket = assign(socket, :selected_id, parse_non_negative(id, nil))

    {:noreply, prefill_form(socket)}
  end

  # ── The form ────────────────────────────────────────────────────────────

  def handle_event("set_extra_calls", %{"value" => value}, socket) do
    {:noreply, assign(socket, :form_extra_calls, parse_non_negative(value, 0))}
  end

  def handle_event("set_note", %{"value" => value}, socket) do
    {:noreply, assign(socket, :form_note, value)}
  end

  def handle_event("toggle_package", %{"slug" => slug}, socket) do
    packages = socket.assigns.form_packages

    packages =
      if MapSet.member?(packages, slug),
        do: MapSet.delete(packages, slug),
        else: MapSet.put(packages, slug)

    # "all" and a list of individual packages mean different things - "all" keeps
    # covering packages added later - so the two are mutually exclusive rather than
    # one being shorthand for the other.
    packages =
      cond do
        slug == Grant.all_packages() and MapSet.member?(packages, slug) ->
          MapSet.new([slug])

        slug != Grant.all_packages() ->
          MapSet.delete(packages, Grant.all_packages())

        true ->
          packages
      end

    {:noreply, assign(socket, :form_packages, packages)}
  end

  # ── Writing ─────────────────────────────────────────────────────────────

  def handle_event("apply_grant", _params, socket) do
    %{
      selected_id: id,
      form_extra_calls: extra_calls,
      form_packages: packages,
      form_note: note
    } = socket.assigns

    with_subscription(socket, id, fn socket, subscription ->
      attrs = %{
        extra_api_calls_per_month: extra_calls,
        full_history_packages: MapSet.to_list(packages),
        note: String.trim(note)
      }

      subscription
      |> Grants.grant(attrs, socket.assigns.current_user)
      |> handle_write(socket, "Grant applied and API call limits refreshed.")
    end)
  end

  def handle_event("re_expand", %{"id" => id}, socket) do
    with_subscription(socket, id, fn socket, subscription ->
      subscription
      |> Grants.re_expand()
      |> handle_write(socket, "Re-expanded against the current package snapshot.")
    end)
  end

  def handle_event("revoke", %{"id" => id}, socket) do
    with_subscription(socket, id, fn socket, subscription ->
      socket =
        socket
        |> assign(:form_extra_calls, 0)
        |> assign(:form_packages, MapSet.new())
        |> assign(:form_note, "")

      subscription
      |> Grants.revoke()
      |> handle_write(socket, "Grant removed. The customer is back on what their plan gives.")
    end)
  end

  # The three writes report the same four outcomes, so they say so in one place.
  #
  # `:api_call_limits_not_refreshed` is the interesting one: the grant is stored but the
  # quota row was not updated, and nothing will retry on its own - the daily reconciler
  # matches on plan name and a grant never changes one. So it is a warning rather than
  # either a success or an error, and it says what to do about it.
  defp handle_write(result, socket, success_message) do
    case result do
      {:ok, _subscription} ->
        {:noreply, socket |> put_flash(:info, success_message) |> load_subscriptions()}

      {:ok, _subscription, :api_call_limits_not_refreshed} ->
        {:noreply,
         socket
         |> put_flash(
           :error,
           "Saved, but the API call limits could not be refreshed - the customer's quota does " <>
             "not reflect this yet. Apply it again to retry."
         )
         |> load_subscriptions()}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, put_flash(socket, :error, changeset_message(changeset))}

      {:error, message} ->
        {:noreply, put_flash(socket, :error, to_string(message))}
    end
  end

  # ── Data ────────────────────────────────────────────────────────────────

  # Read from the database rather than the list an earlier render loaded: two tabs, or a
  # subscription cancelled elsewhere, would otherwise write against a stale struct.
  defp with_subscription(socket, id, fun) do
    case fetch_subscription(id) do
      nil ->
        {:noreply,
         socket
         |> put_flash(:error, "That subscription no longer exists - reloaded the list.")
         |> assign(:selected_id, nil)
         |> load_subscriptions()}

      subscription ->
        fun.(socket, subscription)
    end
  end

  defp fetch_subscription(id) do
    case parse_non_negative(id, nil) do
      nil -> nil
      id -> Repo.get(Subscription, id) |> Repo.preload([:plan, :user])
    end
  end

  defp load_subscriptions(%{assigns: %{selected_user: %User{} = user}} = socket) do
    subscriptions =
      from(s in Subscription,
        where: s.user_id == ^user.id,
        where: s.status in ^@active_statuses,
        order_by: [desc: s.id],
        preload: [:plan]
      )
      |> Repo.all()

    assign(socket, :subscriptions, subscriptions)
  end

  defp load_subscriptions(socket), do: assign(socket, :subscriptions, [])

  # A grant is edited, not re-entered: selecting a subscription that already has one loads
  # it into the form so a second grant does not silently wipe the first.
  defp prefill_form(socket) do
    case selected(socket.assigns) do
      %Subscription{grant: %Grant{} = grant} ->
        socket
        |> assign(:form_extra_calls, Grant.extra_api_calls(grant))
        |> assign(:form_packages, MapSet.new(grant.full_history_packages || []))
        |> assign(:form_note, grant.note || "")

      _ ->
        socket
        |> assign(:form_extra_calls, 0)
        |> assign(:form_packages, MapSet.new())
        |> assign(:form_note, "")
    end
  end

  defp selected(%{selected_id: nil}), do: nil

  defp selected(%{selected_id: id, subscriptions: subscriptions}),
    do: Enum.find(subscriptions, &(&1.id == id))

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

  defp parse_non_negative(value, default) do
    case value |> to_string() |> String.trim() |> Integer.parse() do
      {number, ""} when number >= 0 -> number
      _ -> default
    end
  end

  # A grant is an embed, so `traverse_errors/2` nests its errors one level down and a
  # flat join would print the raw inner map at the admin. Flattened recursively with the
  # path kept, so a failure reads "grant.note: can't be blank" rather than a dump.
  defp changeset_message(changeset) do
    changeset
    |> Ecto.Changeset.traverse_errors(fn {message, _opts} -> message end)
    |> flatten_errors()
    |> Enum.map_join("; ", fn {path, messages} -> "#{path}: #{Enum.join(messages, ", ")}" end)
  end

  defp flatten_errors(errors, prefix \\ nil) do
    Enum.flat_map(errors, fn {field, value} ->
      path = if prefix, do: "#{prefix}.#{field}", else: to_string(field)

      case value do
        %{} = nested -> flatten_errors(nested, path)
        messages when is_list(messages) -> flatten_message_list(messages, path)
        message -> [{path, [to_string(message)]}]
      end
    end)
  end

  # A list entry is itself a map when the embed is a collection, so the two shapes are
  # separated rather than assumed.
  defp flatten_message_list(messages, path) do
    {maps, strings} = Enum.split_with(messages, &is_map/1)

    nested = Enum.flat_map(maps, &flatten_errors(&1, path))

    case strings do
      [] -> nested
      strings -> [{path, Enum.map(strings, &to_string/1)} | nested]
    end
  end

  defp package_options do
    [%{slug: Grant.all_packages(), name: "All packages"} | Package.all()]
  end

  defp resolved_monthly_calls(%Subscription{} = subscription) do
    plan_key =
      Sanbase.ApiCallLimit.Restrictions.key(
        "SANAPI",
        Sanbase.Billing.Subscription.plan_name(subscription)
      )

    base = Sanbase.ApiCallLimit.Restrictions.call_limits_per_month()[plan_key]
    extra = subscription |> Subscription.grant() |> Grant.extra_api_calls()

    case base do
      nil -> nil
      base -> %{base: base, extra: extra, total: base + extra}
    end
  end

  # ── Render ──────────────────────────────────────────────────────────────

  @impl true
  def render(assigns) do
    assigns =
      assigns
      |> assign(:selected, selected(assigns))
      |> assign(:package_options, package_options())

    ~H"""
    <div class="bg-base-200/40 min-h-full">
      <div class="max-w-5xl mx-auto px-6 py-8 space-y-6">
        <div class="flex items-start justify-between gap-4">
          <div>
            <h1 class="text-3xl font-bold">Subscription grants</h1>
            <p class="text-sm text-base-content/60 mt-1">
              Apply an add-on that sales already sold and invoiced separately.
            </p>
          </div>

          <.link navigate={~p"/admin/bundle_subscriptions"} class="btn btn-sm btn-soft shrink-0">
            Bundle subscriptions
          </.link>
        </div>

        <div role="alert" class="alert alert-info">
          <span class="text-sm">
            This moves <strong>entitlement, not money</strong>.
            The add-on is charged on a separate one-off Stripe invoice; nothing here bills anyone.
            A grant only ever <strong>adds</strong> — more calls, wider history — and stays until
            someone removes it.
          </span>
        </div>

        <%!-- ── Find the customer ───────────────────────────────────────── --%>
        <div class="card bg-base-100 border border-base-300 p-4 space-y-4">
          <h2 class="font-semibold">Customer</h2>

          <div class="relative">
            <div class="flex gap-2">
              <input
                type="text"
                value={@user_query}
                phx-keyup="search_user"
                phx-debounce="250"
                placeholder="email, username or id"
                class="input input-sm w-96"
              />
              <button :if={@selected_user} phx-click="clear_user" class="btn btn-sm btn-soft">
                Clear
              </button>
            </div>

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

          <p :if={@selected_user && @subscriptions == []} class="text-sm text-base-content/60">
            This user has no active subscription, so there is nothing to grant against.
          </p>

          <div :if={@subscriptions != []} class="overflow-x-auto">
            <table class="table table-sm">
              <thead>
                <tr>
                  <th></th>
                  <th>Plan</th>
                  <th>Interval</th>
                  <th>Status</th>
                  <th>Grant</th>
                </tr>
              </thead>
              <tbody>
                <tr
                  :for={subscription <- @subscriptions}
                  class={if @selected_id == subscription.id, do: "bg-base-200", else: ""}
                >
                  <td>
                    <button
                      phx-click="select_subscription"
                      phx-value-id={subscription.id}
                      class="btn btn-xs btn-soft"
                    >
                      Select
                    </button>
                  </td>
                  <td class="font-mono text-xs">{subscription.plan.name}</td>
                  <td class="text-xs">{subscription.plan.interval}</td>
                  <td class="text-xs">{subscription.status}</td>
                  <td class="text-xs">
                    <span :if={is_nil(subscription.grant)} class="text-base-content/40">none</span>
                    <span :if={subscription.grant} class="badge badge-sm badge-primary">granted</span>
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
        </div>

        <%!-- ── What is granted now ─────────────────────────────────────── --%>
        <div :if={@selected} class="card bg-base-100 border border-base-300 p-4 space-y-3">
          <h2 class="font-semibold">
            What {@selected.plan.name} gives this customer now
          </h2>

          <% calls = resolved_monthly_calls(@selected) %>

          <div :if={calls} class="text-sm">
            <span class="font-mono">{calls.total}</span>
            API calls a month
            <span :if={calls.extra > 0} class="text-base-content/60">
              ({calls.base} from the plan + {calls.extra} granted)
            </span>
            <span :if={calls.extra == 0} class="text-base-content/60">
              (from the plan; nothing granted)
            </span>
          </div>

          <div :if={is_nil(calls)} class="text-sm text-base-content/60">
            This plan's call allowance is not resolved from its name — check
            /admin/bundle_subscriptions instead.
          </div>

          <% described = Grants.describe(@selected) %>

          <div :if={described} class="space-y-1 text-sm">
            <div>
              Full history on:
              <span :if={described.full_history_packages == []} class="text-base-content/60">
                nothing
              </span>
              <span :for={slug <- described.full_history_packages} class="badge badge-sm mr-1">
                {slug}
              </span>
              <span :if={described.full_history_metric_count > 0} class="text-base-content/60">
                — {described.full_history_metric_count} metrics, snapshot v{described.package_snapshot_version}
              </span>
            </div>

            <div :if={!described.snapshot_is_current?} role="alert" class="alert alert-warning py-2">
              <span class="text-xs">
                A newer package snapshot has been published since this grant was written, so
                metrics added to those packages are not covered. Re-expand only if that omission
                is an oversight — a customer keeping what they bought is the intended default.
              </span>
            </div>

            <div class="text-base-content/60">
              Note: {described.note}
            </div>
            <div class="text-xs text-base-content/50">
              Granted by user #{described.granted_by_id} on {described.granted_at}
            </div>

            <div class="flex gap-2 pt-2">
              <button
                phx-click="re_expand"
                phx-value-id={@selected.id}
                class="btn btn-xs btn-soft"
              >
                Re-expand
              </button>
              <button
                phx-click="revoke"
                phx-value-id={@selected.id}
                data-confirm="Remove this grant? The customer drops back to what their plan gives."
                class="btn btn-xs btn-error btn-soft"
              >
                Remove grant
              </button>
            </div>
          </div>
        </div>

        <%!-- ── Grant form ──────────────────────────────────────────────── --%>
        <div :if={@selected} class="card bg-base-100 border border-base-300 p-4 space-y-4">
          <h2 class="font-semibold">Apply an add-on</h2>

          <div :if={is_nil(@latest_snapshot)} role="alert" class="alert alert-error">
            <span class="text-sm">
              No package snapshot is published, so a full-history grant cannot be expanded.
              <.link navigate={~p"/admin/bundle_packages"} class="link">Publish one first.</.link>
              Extra API calls can still be granted.
            </span>
          </div>

          <fieldset class="fieldset">
            <legend class="fieldset-legend">Extra API calls a month</legend>
            <input
              type="number"
              min="0"
              step="10000"
              value={@form_extra_calls}
              phx-keyup="set_extra_calls"
              phx-debounce="300"
              class="input input-sm w-48"
            />
          </fieldset>

          <fieldset class="fieldset">
            <legend class="fieldset-legend">Full history on</legend>
            <div class="flex flex-wrap gap-2">
              <button
                :for={package <- @package_options}
                phx-click="toggle_package"
                phx-value-slug={package.slug}
                class={[
                  "btn btn-sm",
                  if(MapSet.member?(@form_packages, package.slug),
                    do: "btn-primary",
                    else: "btn-soft"
                  )
                ]}
              >
                {package.name}
              </button>
            </div>
            <p class="text-xs text-base-content/50 mt-1">
              "All packages" is not shorthand for ticking the five — it keeps covering a package
              added later, while a list stays frozen as written.
            </p>
          </fieldset>

          <fieldset class="fieldset">
            <legend class="fieldset-legend">Note (required — invoice or contract reference)</legend>
            <input
              type="text"
              value={@form_note}
              phx-keyup="set_note"
              phx-debounce="300"
              placeholder="e.g. INV-1234, Q3 contract"
              class="input input-sm w-full"
            />
          </fieldset>

          <div>
            <button phx-click="apply_grant" class="btn btn-sm btn-primary">
              Apply grant
            </button>
          </div>
        </div>
      </div>
    </div>
    """
  end
end
