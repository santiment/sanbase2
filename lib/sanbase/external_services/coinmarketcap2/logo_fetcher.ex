defmodule Sanbase.ExternalServices.Coinmarketcap.LogoFetcher do
  use Tesla

  require Logger

  import Mogrify

  alias Sanbase.Model.Project
  alias Sanbase.Repo
  alias Sanbase.ExternalServices.Coinmarketcap.CryptocurrencyInfo
  alias Sanbase.FileStore

  @log_tag "[CMC][LogoFetcher]"

  def run() do
    local_projects_map =
      Project.List.projects()
      |> Enum.map(fn %{coinmarketcap_id: cmc_id} = project -> {cmc_id, project} end)
      |> Map.new()

    Logger.info("#{@log_tag} Started fetching logos from coinmarketcap.")

    Temp.track!()
    dir_path_64 = Temp.mkdir!("logos_64")
    dir_path_32 = Temp.mkdir!("logos_32")

    Map.keys(local_projects_map)
    |> Enum.chunk_every(100)
    |> Enum.flat_map(fn slugs ->
      {:ok, remote_projects} = CryptocurrencyInfo.fetch_data(slugs)

      Enum.each(remote_projects, fn remote_project ->
        update_project_logos(remote_project, local_projects_map, dir_path_64, dir_path_32)
      end)

      remote_projects
    end)

    Temp.cleanup()

    Logger.info("#{@log_tag} Finished fetching logos from coinmarketcap.")
  end

  defp update_project_logos(remote_project, local_projects_map, dir_path_64, dir_path_32) do
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
             {:ok, _} <- upload(local_filepath_32),
             {:ok, _} <-
               update_local_project(project, %{
                 logo_32_url: local_filepath_32,
                 logo_64_url: local_filepath_64
               }) do
          :ok
        else
          error ->
            error
        end

      _ ->
        :ok
    end
  end

  defp download(url, dir_path, file_name) do
    filepath = Path.join(dir_path, file_name)

    case get(url) do
      {:ok, %Tesla.Env{status: 200, body: body}} ->
        Logger.info("#{@log_tag} Successfully downloaded logo: #{url}")
        File.write!(filepath, body)
        {:ok, filepath}

      {:ok, %Tesla.Env{status: status}} ->
        error_msg = "#{@log_tag} Failed downloading logo: #{url}. Status: #{status}"
        Logger.error(error_msg)
        {:error, error_msg}

      {:error, error} ->
        error_msg = inspect(error)
        Logger.error("#{@log_tag} Error downloading logo: #{url}. Error message: #{error_msg}")
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
      Logger.info("#{@log_tag} Successfully uploaded logo: #{filepath}")
      {:ok, FileStore.url({file_name, "logo"})}
    else
      {:error, error} ->
        error_msg = inspect(error)

        Logger.error(
          "#{@log_tag} Failed uploading logo: #{filepath}. Error message: #{error_msg}"
        )

        {:error, error_msg}
    end
  end

  defp update_local_project(nil, _filepath), do: {:error, "Project not found"}

  defp update_local_project(project, fields) do
    Project.changeset(project, fields) |> Repo.update()
  end
end
