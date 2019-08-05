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

  def graphql_error_msg(metric_name) do
    "[#{Ecto.UUID.generate()}] Can't fetch #{metric_name}"
  end

  def graphql_error_msg(metric_name, identifier, opts \\ []) do
    description = Keyword.get(opts, :description, "project with slug")

    "[#{Ecto.UUID.generate()}] Can't fetch #{metric_name} for #{description}: #{identifier}"
  end

  def graphql_error_msg_eth(metric_name, identifier) do
    "[#{Ecto.UUID.generate()}] Can't fetch #{metric_name} for project with slug #{identifier}, because the only slug, that can be used, is ethereum."
  end

  def log_graphql_error(message, error) do
    Logger.warn("#{message}" <> ", Reason: #{inspect(error)}")
  end

  # Private functions
  defp format_error({msg, opts}) do
    Enum.reduce(opts, msg, fn {key, value}, acc ->
      String.replace(acc, "%{#{key}}", to_string(inspect(value)))
    end)
  end
end
