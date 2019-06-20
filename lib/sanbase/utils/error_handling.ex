defmodule Sanbase.Utils.ErrorHandling do
  require Logger

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

  def log_graphql_error(message, error) do
    Logger.warn("#{message}" <> ", Reason: #{inspect(error)}")
  end
end
