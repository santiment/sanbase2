defmodule Sanbase.ExternalServices.Coinmarketcap.LogoFetcher do
  use Tesla

  require Logger

  import Mogrify

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

    dir_path_64 = Temp.mkdir!("logos_64")
    dir_path_32 = Temp.mkdir!("logos_32")

    Map.keys(local_projects_map)
    |> Enum.chunk_every(100)
    |> Enum.flat_map(fn slugs ->
      {:ok, remote_projects} = CryptocurrencyInfo.fetch_data(slugs)

      Enum.each(remote_projects, fn remote_project ->
        url = remote_project.logo
        slug = remote_project.slug
        file_extension = Path.extname(url |> String.downcase())
        file_name = slug <> file_extension

        case Map.get(local_projects_map, slug) do
          %Project{} = project ->
            with {:ok, local_filepath_64} <- download(url, dir_path_64, file_name),
                 {:ok, local_filepath_32} <-
                   resize_image(local_filepath_64, dir_path_32, file_name),
                 {:ok, _} <- upload(local_filepath_64),
                 {:ok, _} <- upload(local_filepath_32) do
              :ok
            else
              error ->
                error
            end

          _ ->
            :ok
        end
      end)

      remote_projects
    end)

    Logger.info("[CMC] Finished fetching logos from coinmarketcap.")
  end

  defp download(url, dir_path, file_name) do
    filepath = Path.join(dir_path, file_name)

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

  defp resize_image(source_filepath, dest_dir_path, file_name) do
    dest_file_path = dest_dir_path <> "/" <> file_name
    open(source_filepath) |> resize("32x32") |> save(path: dest_file_path)
    {:ok, dest_file_path}
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
