defmodule Sanbase.Utils.ErrorHandling do
  require Logger

  def error_result(message) do
    log_id = Ecto.UUID.generate()
    Logger.error("[#{log_id}] #{message}")
    {:error, "[#{log_id}] Error executing query. See logs for details."}
  end
end
