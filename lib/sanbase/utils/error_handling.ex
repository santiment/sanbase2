defmodule Sanbase.Utils.ErrorHandling do
  @moduledoc ~s"""

  """
  require Logger

  @compile inline: [
             description_and_identifier: 2
           ]
  def changeset_errors_to_str(%Ecto.Changeset{} = changeset) do
    changeset
    |> Ecto.Changeset.traverse_errors(&format_error/1)
    |> case do
      map when is_map(map) -> Jason.encode!(map)
      str when is_binary(str) -> str
    end
  end

  def error_result(message, query_name \\ "query") do
    log_id = Ecto.UUID.generate()
    Logger.error("[#{log_id}] #{message}")
    {:error, "[#{log_id}] Error executing #{query_name}. See logs for details."}
  end

  def warn_result(message, query_name \\ "query") do
    log_id = Ecto.UUID.generate()
    Logger.warn("[#{log_id}] #{message}")
    {:error, "[#{log_id}] Error executing #{query_name}. See logs for details."}
  end

  def handle_graphql_error(metric, identifier, reason, opts \\ []) do
    {target_description, identifier} = description_and_identifier(identifier, opts)
    # Detect if reason already contains UUID and use it.
    {uuid, message} =
      case reason do
        <<"["::utf8, uuid::binary-size(36), "]"::utf8, message::binary>> ->
          {uuid, message |> String.trim()}

        _ ->
          {Ecto.UUID.generate(), reason}
      end

    error_msg =
      "[#{uuid}] Can't fetch #{metric} for #{target_description} #{
        identifier_to_string(identifier)
      }"

    error_msg_with_reason = error_msg <> ", Reason: #{inspect(message)}"

    Logger.warn(error_msg_with_reason)

    case Keyword.get(opts, :propagate_reason, true) do
      true -> error_msg_with_reason
      false -> error_msg
    end
  end

  def maybe_handle_graphql_error({:ok, result}, _), do: {:ok, result}

  def maybe_handle_graphql_error({:error, error}, error_handler)
      when is_function(error_handler, 1) do
    {:error, error_handler.(error)}
  end

  # Private functions

  defp description_and_identifier(identifier, opts) do
    case Keyword.get(opts, :description) do
      nil ->
        case identifier do
          %{metric: metric, selector: selector} ->
            {"selector #{inspect(selector)} and metric #{metric}", ""}

          %{slug: slug} ->
            {"project with slug", slug}

          %{address: address} ->
            {"Address", address}

          %{text: text} ->
            {"search term", text}

          %{metric: metric} ->
            {"metric", metric}

          slug when is_binary(slug) ->
            {"project with slug", slug}

          %{} = selector when map_size(selector) > 0 ->
            {"selector", selector}

          %{} ->
            {"an empty selector", "{}"}
        end

      description ->
        {description, identifier}
    end
  end

  defp identifier_to_string(str) when is_binary(str), do: str
  defp identifier_to_string(data), do: inspect(data)

  defp format_error({msg, opts}) do
    Enum.reduce(opts, msg, fn {key, value}, acc ->
      String.replace(acc, "%{#{key}}", to_string(inspect(value)))
    end)
  end
end
