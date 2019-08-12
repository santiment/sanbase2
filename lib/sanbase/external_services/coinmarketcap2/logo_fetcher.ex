defmodule Sanbase.ExternalServices.Coinmarketcap.LogoFetcher do
  use Tesla

  require Logger

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
    filename = slug <> file_extension

    case Map.get(local_projects_map, slug) do
      %Project{} = project ->
        with {:ok, local_filepath_64} <- download(url, dir_path_64, filename),
             {:ok, local_filepath_32} <-
               resize_image(local_filepath_64, dir_path_32, filename),
             {:ok, uploaded_filepath_64} <- upload(local_filepath_64, 64),
             {:ok, uploaded_filepath_32} <- upload(local_filepath_32, 32),
             {:ok, _} <-
               update_local_project(project, %{
                 logo32_url: uploaded_filepath_32,
                 logo64_url: uploaded_filepath_64
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

  defp download(url, dir_path, filename) do
    filepath = Path.join(dir_path, filename)

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

  defp resize_image(source_filepath, dest_dir_path, filename) do
    dest_filepath = dest_dir_path <> "/" <> filename
    Mogrify.open(source_filepath) |> Mogrify.resize("32x32") |> Mogrify.save(path: dest_filepath)
    {:ok, dest_filepath}
  end

  defp upload(filepath, size) do
    with {:ok, filename} <- FileStore.store({filepath, "logo#{size}"}) do
      Logger.info("#{@log_tag} Successfully uploaded logo from #{filepath} to: #{filename}")
      {:ok, FileStore.url({filename, "logo#{size}"})}
    else
      {:error, error} ->
        error_msg = inspect(error)

        Logger.error(
          "#{@log_tag} Failed uploading logo: #{filepath}. Error message: #{error_msg}"
        )

        {:error, error_msg}
    end
  end

  defp update_local_project(%Project{} = project, %{} = fields) do
    Project.changeset(project, fields) |> Repo.update()
    Logger.info("#{@log_tag} Successfully updated logos for project: #{project.coinmarketcap_id}")
  end
end
