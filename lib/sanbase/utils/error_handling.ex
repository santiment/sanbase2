defmodule Sanbase.Utils.ErrorHandling do
  require Logger

  def changeset_errors_to_str(%Ecto.Changeset{} = changeset) do
    changeset
    |> Ecto.Changeset.traverse_errors(&format_error/1)
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
    target = Keyword.get(opts, :description, "project with slug")
    error_msg = "[#{Ecto.UUID.generate()}] Can't fetch #{metric} for #{target}: #{identifier}"
    error_msg_with_reason = error_msg <> ", Reason: #{inspect(reason)}"

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
  defp format_error({msg, opts}) do
    Enum.reduce(opts, msg, fn {key, value}, acc ->
      String.replace(acc, "%{#{key}}", to_string(inspect(value)))
    end)
  end
end
