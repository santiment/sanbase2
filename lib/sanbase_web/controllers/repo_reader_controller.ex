defmodule SanbaseWeb.RepoReaderController do
  use SanbaseWeb, :controller

  alias Sanbase.Model.Project
  alias Sanbase.Model.Project.SocialVolumeQuery

  require Sanbase.Utils.Config, as: Config
  require Logger

  def validator_webhook(conn, %{"secret" => secret} = params) do
    case endpoint_secret() == secret do
      true ->
        changed_files = Map.get(params, "changed_files", [])
        branch = Map.get(params, "branch", "main")

        case Sanbase.RepoReader.validate_changes(branch, changed_files) do
          :ok ->
            conn
            |> put_resp_header("content-type", "application/json; charset=utf-8")
            |> Plug.Conn.send_resp(200, %{result: :ok} |> Jason.encode!())

          {:error, errors} ->
            conn
            |> put_resp_header("content-type", "application/json; charset=utf-8")
            |> Plug.Conn.send_resp(400, %{error: inspect(errors)} |> Jason.encode!())
        end

      false ->
        conn
        |> send_resp(403, "Unauthorized")
        |> halt()
    end
  end

  def reader_webhook(conn, %{"secret" => secret} = params) do
    case endpoint_secret() == secret do
      true ->
        changed_files = Map.get(params, "changed_files", [])

        case Sanbase.RepoReader.update_projects(changed_files) do
          :ok ->
            conn
            |> put_resp_header("content-type", "application/json; charset=utf-8")
            |> Plug.Conn.send_resp(200, %{result: :ok} |> Jason.encode!())

          {:error, errors} ->
            conn
            |> put_resp_header("content-type", "application/json; charset=utf-8")
            |> Plug.Conn.send_resp(400, %{errors: inspect(errors)} |> Jason.encode!())
        end

      false ->
        conn
        |> send_resp(403, "Unauthorized")
        |> halt()
    end
  end

  # On stage/prod the env var is set and is different from the default one.
  defp endpoint_secret(),
    do: Config.module_get(Sanbase.RepoReader, :projects_data_endpoint_secret)
end
