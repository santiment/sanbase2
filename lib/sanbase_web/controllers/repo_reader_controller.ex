defmodule SanbaseWeb.RepoReaderController do
  use SanbaseWeb, :controller

  require Logger
  require Sanbase.Utils.Config, as: Config

  def validator_webhook(conn, params) do
    Logger.info("[RepoReaderController] Received validator webhook with params: #{inspect(Map.delete(params, "secret"))}")

    changed_files = Map.get(params, "changed_files", [])
    branch = Map.fetch!(params, "branch")
    fork_repo = Map.fetch!(params, "fork_repo")

    case Sanbase.RepoReader.validate_changes(fork_repo, branch, changed_files) do
      :ok ->
        conn
        |> put_resp_header("content-type", "application/json; charset=utf-8")
        |> put_status(200)
        |> json(%{result: "OK"})

      {:error, error} ->
        conn
        |> put_resp_header("content-type", "application/json; charset=utf-8")
        |> put_status(400)
        |> json(%{error: error})
    end
  end

  def reader_webhook(conn, %{"secret" => secret} = params) do
    Logger.info("[RepoReaderController] Received reader webhook with params: #{inspect(Map.delete(params, "secret"))}")

    if endpoint_secret() == secret do
      changed_files = Map.get(params, "changed_files", [])

      case Sanbase.RepoReader.update_projects(changed_files) do
        :ok ->
          conn
          |> put_resp_header("content-type", "application/json; charset=utf-8")
          |> put_status(200)
          |> json(%{result: "OK"})

        {:error, error} ->
          conn
          |> put_resp_header("content-type", "application/json; charset=utf-8")
          |> put_status(400)
          |> json(%{error: error})
      end
    else
      conn
      |> send_resp(403, "Unauthorized")
      |> halt()
    end
  end

  # On stage/prod the env var is set and is different from the default one.
  defp endpoint_secret, do: Config.module_get(Sanbase.RepoReader, :projects_data_endpoint_secret)
end
