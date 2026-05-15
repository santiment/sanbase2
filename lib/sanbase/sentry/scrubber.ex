defmodule Sanbase.Sentry.Scrubber do
  @moduledoc """
  Sentry `before_send` callback that scrubs GraphQL document/variables and
  Absinthe breadcrumbs for users whose activity is privacy-protected
  (see `Sanbase.Accounts.privacy_protected?/1`).

  `Sentry.PlugContext` captures the raw HTTP request body before
  `SanbaseWeb.Graphql.AuthPlug` knows who the caller is, so the request
  data field embedded in a Sentry event for a protected user can still
  carry the GraphQL `query` / `variables`. This scrubber runs at the
  moment of send and replaces the sensitive fields with a sentinel.
  """

  alias Sanbase.Accounts
  alias Sentry.Event
  alias Sentry.Interfaces.{Breadcrumb, Request}

  @scrubbed_request_keys ~w(query variables operationName operation_name)

  @spec before_send(Event.t()) :: Event.t()
  def before_send(%Event{} = event) do
    case protected_user_id(event) do
      nil -> event
      _id -> scrub(event)
    end
  end

  defp protected_user_id(%Event{user: user}) when is_map(user) do
    case Map.get(user, :id) || Map.get(user, "id") do
      id when is_integer(id) ->
        if Accounts.privacy_protected?(id), do: id, else: nil

      _ ->
        nil
    end
  end

  defp protected_user_id(_), do: nil

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

    Enum.reduce(@scrubbed_request_keys, data, fn key, acc ->
      cond do
        Map.has_key?(acc, key) -> Map.put(acc, key, masked)
        Map.has_key?(acc, String.to_atom(key)) -> Map.put(acc, String.to_atom(key), masked)
        true -> acc
      end
    end)
  end

  defp scrub_breadcrumbs(breadcrumbs) when is_list(breadcrumbs) do
    Enum.reject(breadcrumbs, &absinthe_breadcrumb?/1)
  end

  defp scrub_breadcrumbs(other), do: other

  defp absinthe_breadcrumb?(%Breadcrumb{message: msg}) when is_binary(msg),
    do: String.starts_with?(msg, "ABSINTHE")

  defp absinthe_breadcrumb?(%{message: msg}) when is_binary(msg),
    do: String.starts_with?(msg, "ABSINTHE")

  defp absinthe_breadcrumb?(_), do: false
end
