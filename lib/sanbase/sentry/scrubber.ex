defmodule Sanbase.Sentry.Scrubber do
  @moduledoc """
  Sentry `before_send` callback that scrubs GraphQL document/variables and
  Absinthe breadcrumbs for users whose activity is privacy-protected
  (see `Sanbase.Accounts.activity_traces_hidden?/1`).

  `Sentry.PlugContext` captures the raw HTTP request body before
  `SanbaseWeb.Graphql.AuthPlug` knows who the caller is, so the request
  data field embedded in a Sentry event for a protected user can still
  carry the GraphQL `query` / `variables`. This scrubber runs at the
  moment of send and replaces the sensitive fields with a sentinel.
  """

  alias Sanbase.Accounts
  alias Sentry.Event
  alias Sentry.Interfaces.Request

  # Pre-interned at compile time. Sentry events can carry GraphQL
  # request fields under either string or atom keys depending on which
  # body parser produced them; we mask both forms without ever calling
  # `String.to_atom/1` on runtime input.
  @scrubbed_request_keys [
    {"query", :query},
    {"variables", :variables},
    {"operationName", :operationName},
    {"operation_name", :operation_name}
  ]

  @spec before_send(Event.t()) :: Event.t()
  def before_send(%Event{} = event) do
    if protected?(event), do: scrub(event), else: event
  end

  defp protected?(%Event{user: %{} = user}) do
    case Map.get(user, :id) || Map.get(user, "id") do
      id when is_integer(id) -> Accounts.activity_traces_hidden?(id)
      _ -> false
    end
  end

  defp protected?(_), do: false

  defp scrub(%Event{} = event) do
    %{
      event
      | request: scrub_request(event.request),
        breadcrumbs: scrub_breadcrumbs(event.breadcrumbs)
    }
  end

  defp scrub_request(%Request{data: data} = request) when is_map(data) do
    %{request | data: scrub_request_data(data)}
  end

  defp scrub_request(other), do: other

  defp scrub_request_data(data) do
    masked = Accounts.masked_sentinel()

    Enum.reduce(@scrubbed_request_keys, data, fn {string_key, atom_key}, acc ->
      cond do
        Map.has_key?(acc, string_key) -> Map.put(acc, string_key, masked)
        Map.has_key?(acc, atom_key) -> Map.put(acc, atom_key, masked)
        true -> acc
      end
    end)
  end

  defp scrub_breadcrumbs(breadcrumbs) when is_list(breadcrumbs) do
    Enum.reject(breadcrumbs, &absinthe_breadcrumb?/1)
  end

  defp scrub_breadcrumbs(other), do: other

  defp absinthe_breadcrumb?(%{message: msg}) when is_binary(msg),
    do: String.starts_with?(msg, "ABSINTHE")

  defp absinthe_breadcrumb?(_), do: false
end
