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
end
