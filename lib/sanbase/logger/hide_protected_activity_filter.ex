defmodule Sanbase.Logger.HideProtectedActivityFilter do
  @moduledoc """
  `:logger` filter that suppresses log entries containing the raw GraphQL
  document for users in `Sanbase.Accounts.activity_traces_hidden_user_ids/0`.

  The filter is keyed on the `hide_user_activity` Logger metadata flag
  (set by `SanbaseWeb.Graphql.AuthPlug` for protected users) combined
  with the message starting with `"ABSINTHE"` — the prefix emitted by
  `Absinthe.Logger.log_run/2` for every incoming GraphQL document.

  Returns `:stop` to drop the event, `:ignore` to leave it untouched.
  """

  @spec filter(:logger.log_event(), term()) :: :logger.filter_return()
  def filter(%{meta: %{hide_user_activity: true}, msg: msg}, _extra) do
    if absinthe_document_log?(msg), do: :stop, else: :ignore
  end

  def filter(_event, _extra), do: :ignore

  defp absinthe_document_log?({:string, iodata}), do: iodata_starts_with_absinthe?(iodata)

  defp absinthe_document_log?({:report, %{report_cb: cb} = report}) when is_function(cb, 1) do
    case cb.(report) do
      {format, args} when is_list(args) -> formatted_starts_with_absinthe?(format, args)
      _ -> false
    end
  rescue
    _ -> false
  end

  defp absinthe_document_log?({format, args}) when is_list(args),
    do: formatted_starts_with_absinthe?(format, args)

  defp absinthe_document_log?(_), do: false

  defp formatted_starts_with_absinthe?(format, args) do
    iodata_starts_with_absinthe?(:io_lib.format(format, args))
  rescue
    _ -> false
  end

  # Most Absinthe log payloads are already a binary or a `[binary | _]`
  # iodata starting with "ABSINTHE", so peek at the head before paying
  # for a full `IO.iodata_to_binary/1` flatten.
  defp iodata_starts_with_absinthe?("ABSINTHE" <> _), do: true
  defp iodata_starts_with_absinthe?(bin) when is_binary(bin), do: false
  defp iodata_starts_with_absinthe?(["ABSINTHE" <> _ | _]), do: true

  defp iodata_starts_with_absinthe?(iodata) do
    case IO.iodata_to_binary(iodata) do
      "ABSINTHE" <> _ -> true
      _ -> false
    end
  rescue
    _ -> false
  end
end
