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
  alias Sentry.Interfaces.Exception
  alias Sentry.Interfaces.Request
  alias Sentry.Interfaces.Stacktrace

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
      # activity_traces_hidden? for user_id is fast because the
      # user ids are stored in persistent term and are very fast to access.
      id when is_integer(id) -> Accounts.activity_traces_hidden?(id)
      _ -> false
    end
  end

  defp protected?(_), do: false

  defp scrub(%Event{} = event) do
    masked = Accounts.masked_sentinel()

    %{
      event
      | request: scrub_request(event.request, masked),
        breadcrumbs: scrub_breadcrumbs(event.breadcrumbs),
        # Exception messages and stack-frame locals can carry the
        # user-supplied slug / metric name / SQL fragment that triggered
        # the error; mask them just like the request body.
        exception: scrub_exceptions(event.exception, masked),
        extra: scrub_map(event.extra, masked)
    }
  end

  defp scrub_request(%Request{data: data} = request, masked) when is_map(data) do
    %{request | data: scrub_request_data(data, masked)}
  end

  defp scrub_request(other, _masked), do: other

  defp scrub_request_data(data, masked) do
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

  defp scrub_exceptions(exceptions, masked) when is_list(exceptions) do
    Enum.map(exceptions, &scrub_exception(&1, masked))
  end

  defp scrub_exceptions(other, _masked), do: other

  defp scrub_exception(%Exception{} = exc, masked) do
    %{exc | value: masked, stacktrace: scrub_stacktrace(exc.stacktrace, masked)}
  end

  defp scrub_exception(other, _masked), do: other

  defp scrub_stacktrace(%Stacktrace{frames: frames} = st, _masked) when is_list(frames) do
    %{st | frames: Enum.map(frames, &scrub_frame/1)}
  end

  defp scrub_stacktrace(other, _masked), do: other

  defp scrub_frame(%Stacktrace.Frame{} = frame) do
    # Local variable captures can interpolate user-supplied params; drop them.
    %{frame | vars: nil}
  end

  defp scrub_frame(other), do: other

  # `event.extra` is a free-form map. Resolvers occasionally stash
  # user-supplied params there via `Sentry.Context.set_extra_context/1`,
  # so blank it out wholesale rather than try to enumerate every key.
  defp scrub_map(map, masked) when is_map(map) and map_size(map) > 0,
    do: Map.new(map, fn {k, _v} -> {k, masked} end)

  defp scrub_map(map, _masked), do: map
end
