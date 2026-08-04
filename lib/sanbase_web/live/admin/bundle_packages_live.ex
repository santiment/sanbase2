defmodule SanbaseWeb.Admin.BundlePackagesLive do
  @moduledoc ~s"""
  What each bundle package contains, and publishing that as a snapshot.

  The point of this page is to make one thing visible that is otherwise implicit:
  editing metric categorization **is** a change to what customers get. The pending
  changes panel shows exactly which metrics a publish would add or remove from
  each package, per package, before anything is written.

  See task PD / OB in `docs/composable-api-plans-handover.md`.
  """

  use SanbaseWeb, :live_view

  alias Sanbase.Billing.Plan.Bundle.ApiCallAddon
  alias Sanbase.Billing.Plan.Bundle.Package
  alias Sanbase.Billing.Plan.Bundle.PackageSnapshot
  alias Sanbase.Billing.Plan.Bundle.Resolver

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Bundle Packages")
     |> assign(:notes, "")
     |> assign(:expanded, nil)
     |> load()}
  end

  @impl true
  def handle_event("publish", params, socket) do
    # From the submitted params first: the input only pushes to the socket on blur,
    # so typing a note and pressing Enter would otherwise publish without it.
    notes = Map.get(params, "notes") || socket.assigns.notes

    case PackageSnapshot.publish(notes: blank_to_nil(notes)) do
      {:ok, snapshot} ->
        {:noreply,
         socket
         |> put_flash(:info, "Published snapshot version #{snapshot.version}.")
         |> assign(:notes, "")
         |> load()}

      {:error, message} when is_binary(message) ->
        {:noreply, put_flash(socket, :error, message)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, put_flash(socket, :error, changeset_message(changeset))}
    end
  end

  def handle_event("set_notes", %{"value" => notes}, socket) do
    {:noreply, assign(socket, :notes, notes)}
  end

  def handle_event("toggle_package", %{"slug" => slug}, socket) do
    expanded = if socket.assigns.expanded == slug, do: nil, else: slug

    {:noreply, assign(socket, :expanded, expanded)}
  end

  def handle_event("refresh", _params, socket) do
    {:noreply, load(socket)}
  end

  defp load(socket) do
    {live, live_error} =
      case PackageSnapshot.materialize() do
        {:ok, contents} -> {contents, nil}
        {:error, message} -> {%{}, message}
      end

    latest = PackageSnapshot.latest()

    pending =
      case live_error do
        nil -> PackageSnapshot.diff(snapshot_contents(latest), live)
        _ -> %{}
      end

    socket
    |> assign(:live, live)
    |> assign(:live_error, live_error)
    |> assign(:latest, latest)
    |> assign(:pending, pending)
    |> assign(:snapshots, PackageSnapshot.list_recent(10))
  end

  defp snapshot_contents(nil), do: %{}
  defp snapshot_contents(%PackageSnapshot{contents: contents}), do: contents

  defp blank_to_nil(value) do
    case String.trim(value || "") do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp changeset_message(changeset) do
    changeset
    |> Ecto.Changeset.traverse_errors(fn {message, _opts} -> message end)
    |> Enum.map_join("; ", fn {field, messages} ->
      "#{field}: #{Enum.join(List.wrap(messages), ", ")}"
    end)
  end

  defp count(contents, slug), do: contents |> Map.get(slug, []) |> length()

  defp pending_total(pending) do
    Enum.reduce(pending, 0, fn {_slug, %{added: added, removed: removed}}, acc ->
      acc + length(added) + length(removed)
    end)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="bg-base-200/40 min-h-full">
      <div class="max-w-6xl mx-auto px-6 py-8 space-y-6">
        <div class="flex items-start justify-between gap-4">
          <div>
            <h1 class="text-3xl font-bold">Bundle Packages</h1>
            <p class="text-sm text-base-content/60 mt-1">
              What each sellable package contains, worked out from metric categorization.
            </p>
          </div>

          <div class="flex gap-2 shrink-0">
            <.link navigate={~p"/admin/bundle_subscriptions"} class="btn btn-sm btn-soft">
              Bundle subscriptions
            </.link>
            <button phx-click="refresh" class="btn btn-sm btn-soft">Refresh</button>
          </div>
        </div>

        <%!-- ── Categorization is missing a category the definitions expect ── --%>
        <div :if={@live_error} role="alert" class="alert alert-error">
          <div>
            <h3 class="font-semibold">Cannot work out package contents</h3>
            <pre class="text-xs whitespace-pre-wrap mt-1">{@live_error}</pre>
          </div>
        </div>

        <%!-- ── Published state ─────────────────────────────────────────── --%>
        <div class="grid grid-cols-1 md:grid-cols-3 gap-4">
          <div class="card bg-base-100 border border-base-300 p-4">
            <div class="text-xs uppercase tracking-wide text-base-content/50">
              Published snapshot
            </div>
            <div class="text-2xl font-semibold mt-1">
              {if @latest, do: "v#{@latest.version}", else: "none"}
            </div>
            <div :if={@latest} class="text-xs text-base-content/60 mt-1">
              {Calendar.strftime(@latest.published_at, "%Y-%m-%d %H:%M UTC")}
            </div>
            <div :if={is_nil(@latest)} class="text-xs text-warning mt-1">
              Bundle subscriptions cannot be resolved until one is published.
            </div>
          </div>

          <div class="card bg-base-100 border border-base-300 p-4">
            <div class="text-xs uppercase tracking-wide text-base-content/50">
              Metrics currently sellable
            </div>
            <div class="text-2xl font-semibold mt-1">
              {@live |> Map.values() |> List.flatten() |> Enum.uniq() |> length()}
            </div>
            <div class="text-xs text-base-content/60 mt-1">
              across {length(Package.all())} packages, deprecated and hidden excluded
            </div>
          </div>

          <div class="card bg-base-100 border border-base-300 p-4">
            <div class="text-xs uppercase tracking-wide text-base-content/50">
              Base monthly API calls
            </div>
            <div class="text-2xl font-semibold mt-1">
              {Number.Delimit.number_to_delimited(Resolver.base_calls_per_month(), precision: 0)}
            </div>
            <div class="text-xs text-base-content/60 mt-1">
              flat, whatever the number of packages
            </div>
          </div>
        </div>

        <%!-- ── Pending changes / publish ───────────────────────────────── --%>
        <div class="card bg-base-100 border border-base-300 p-4 space-y-3">
          <div class="flex items-center justify-between gap-4">
            <div>
              <h2 class="font-semibold">Pending changes</h2>
              <p class="text-xs text-base-content/60">
                What publishing now would change. Customers keep the snapshot they were resolved
                against until something re-resolves them.
              </p>
            </div>

            <span class={[
              "badge shrink-0",
              if(pending_total(@pending) == 0, do: "badge-success", else: "badge-warning")
            ]}>
              {pending_total(@pending)} change(s)
            </span>
          </div>

          <div
            :if={pending_total(@pending) == 0 and is_nil(@live_error)}
            class="text-sm text-base-content/60"
          >
            The published snapshot matches the current categorization.
          </div>

          <div :for={{slug, %{added: added, removed: removed}} <- @pending} class="text-sm">
            <div class="font-medium">{slug}</div>

            <div :if={added != []} class="text-success text-xs mt-1">
              + {Enum.join(added, ", ")}
            </div>

            <div :if={removed != []} class="text-error text-xs mt-1">
              − {Enum.join(removed, ", ")}
            </div>
          </div>

          <form phx-submit="publish" class="flex items-end gap-2 pt-2 border-t border-base-300">
            <fieldset class="fieldset grow">
              <legend class="fieldset-legend">Notes (why publish?)</legend>
              <input
                type="text"
                name="notes"
                value={@notes}
                phx-blur="set_notes"
                placeholder="e.g. added the new staking metrics to Onchain Core"
                class="input input-sm w-full"
              />
            </fieldset>

            <button type="submit" disabled={not is_nil(@live_error)} class="btn btn-sm btn-primary">
              Publish snapshot
            </button>
          </form>
        </div>

        <%!-- ── The packages ────────────────────────────────────────────── --%>
        <div class="card bg-base-100 border border-base-300 overflow-hidden">
          <table class="table table-sm">
            <thead>
              <tr>
                <th>Package</th>
                <th>SKU</th>
                <th>Metric category</th>
                <th class="text-right">Live</th>
                <th class="text-right">Published</th>
                <th></th>
              </tr>
            </thead>
            <tbody>
              <%= for package <- Package.all() do %>
                <tr>
                  <td class="font-medium">{package.name}</td>
                  <td><code class="text-xs">{package.slug}</code></td>
                  <td>
                    <code class="text-xs">{package.category}</code>
                  </td>
                  <td class="text-right">{count(@live, package.slug)}</td>
                  <td class="text-right text-base-content/60">
                    {if @latest, do: count(@latest.contents, package.slug), else: "—"}
                  </td>
                  <td class="text-right">
                    <button
                      phx-click="toggle_package"
                      phx-value-slug={package.slug}
                      class="btn btn-xs btn-soft"
                    >
                      {if @expanded == package.slug, do: "Hide", else: "Metrics"}
                    </button>
                  </td>
                </tr>

                <tr :if={@expanded == package.slug}>
                  <td colspan="6" class="bg-base-200/50">
                    <div class="text-xs font-mono max-h-64 overflow-y-auto whitespace-pre-wrap">
                      {@live |> Map.get(package.slug, []) |> Enum.join("\n")}
                    </div>
                    <div :if={count(@live, package.slug) == 0} class="text-xs text-warning">
                      Nothing in this package. Either the category is empty, or every metric in it
                      is deprecated or hidden.
                    </div>
                  </td>
                </tr>
              <% end %>

              <tr :for={addon <- ApiCallAddon.all()} class="border-t-2 border-base-300">
                <td class="font-medium">{addon.name}</td>
                <td><code class="text-xs">{addon.sku}</code></td>
                <td><code class="text-xs">add-on</code></td>
                <td class="text-right text-base-content/60">—</td>
                <td class="text-right text-base-content/60">—</td>
                <td></td>
              </tr>
            </tbody>
          </table>

          <div class="px-4 py-2 border-t border-base-300 text-xs text-base-content/50">
            Prices are not set here — they are not final, and nothing charges from the catalog yet.
            That arrives with the Stripe catalog work.
          </div>
        </div>

        <%!-- ── Snapshot history ────────────────────────────────────────── --%>
        <div class="card bg-base-100 border border-base-300 overflow-hidden">
          <div class="px-4 pt-4">
            <h2 class="font-semibold">Snapshot history</h2>
            <p class="text-xs text-base-content/60">
              Each bundle subscription pins the version it was resolved against.
            </p>
          </div>

          <table class="table table-sm">
            <thead>
              <tr>
                <th>Version</th>
                <th>Published</th>
                <th class="text-right">Metrics</th>
                <th>Notes</th>
              </tr>
            </thead>
            <tbody>
              <tr :for={snapshot <- @snapshots}>
                <td class="font-medium">v{snapshot.version}</td>
                <td class="text-xs">
                  {Calendar.strftime(snapshot.published_at, "%Y-%m-%d %H:%M UTC")}
                </td>
                <td class="text-right">
                  {snapshot.contents |> Map.values() |> List.flatten() |> Enum.uniq() |> length()}
                </td>
                <td class="text-xs text-base-content/60">{snapshot.notes}</td>
              </tr>

              <tr :if={@snapshots == []}>
                <td colspan="4" class="text-sm text-base-content/60">
                  Nothing published yet.
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </div>
    </div>
    """
  end
end
