defmodule Sanbase.ExternalServices.Coinmarketcap.LogoFetcher do
  use Tesla

  require Logger

  alias Sanbase.Model.Project
  alias Sanbase.Repo
  alias Sanbase.ExternalServices.Coinmarketcap.CryptocurrencyInfo
  alias Sanbase.FileStore

  def run(projects \\ all_projects()) do
    local_projects_map =
      Enum.reduce(projects, %{}, fn project, acc ->
        case(project.coinmarketcap_id) do
          nil ->
            acc

          _ ->
            Map.put(acc, project.coinmarketcap_id, project)
        end
      end)

    Logger.info("[CMC] Started fetching logos from coinmarketcap.")

    remote_projects =
      Map.keys(local_projects_map)
      |> Enum.chunk_every(100)
      |> Enum.flat_map(fn slugs ->
        {:ok, remote_projects} = CryptocurrencyInfo.fetch_data(slugs)
        remote_projects
      end)

    dir_path = Temp.mkdir!("logos")

    Enum.each(remote_projects, fn remote_project ->
      case Map.get(local_projects_map, remote_project.slug) do
        %Project{} = project ->
          file_extension = Path.extname(remote_project.logo |> String.downcase())
          cmc_filepath = Path.join(dir_path, remote_project.slug <> file_extension)

          with {:ok, local_filepath} <- download(cmc_filepath, remote_project.logo),
               {:ok, remote_filepath} <- upload(local_filepath),
               {:ok, _} <- update_local_project(remote_filepath, project) do
            :ok
          else
            error ->
              error
          end

        _ ->
          :ok
      end
    end)

    Logger.info("[CMC] Finished fetching logos from coinmarketcap.")
  end

  defp download(filepath, url) do
    case get(url) do
      {:ok, %Tesla.Env{status: 200, body: body}} ->
        Logger.info("[CMC] Successfully downloaded logo: #{url}")
        File.write!(filepath, body)
        {:ok, filepath}

      {:ok, %Tesla.Env{status: status}} ->
        error_msg = "[CMC] Failed downloading logo: #{url}. Status: #{status}"
        Logger.error(error_msg)
        {:error, error_msg}

      {:error, error} ->
        error_msg = inspect(error)
        Logger.error("[CMC] Error downloading logo: #{url}. Error message: #{error_msg}")
        {:error, error_msg}
    end
  end

  defp upload(filepath) do
    with {:ok, file_name} <- FileStore.store({filepath, "logo"}) do
      Logger.info("[CMC] Successfully uploaded logo: #{filepath}")
      {:ok, FileStore.url({file_name, "logo"})}
    else
      {:error, error} ->
        error_msg = inspect(error)
        Logger.error("[CMC] Failed uploading logo: #{filepath}. Error message: #{error_msg}")
        {:error, error_msg}
    end
  end

  defp update_local_project(_filepath, nil), do: {:error, "Project not found"}

  defp update_local_project(filepath, project) do
    Project.changeset(project, %{logo_url: filepath}) |> Repo.update()
  end

  defp all_projects do
    Project.List.projects()
  end
end
