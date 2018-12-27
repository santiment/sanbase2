defmodule SanbaseWeb.Graphql.ClickhouseDataloader do
  alias Sanbase.Clickhouse.Github
  alias Sanbase.Model.Project

  import Ecto.Query

  def data() do
    Dataloader.KV.new(&query/2)
  end

  def query(:average_dev_activity, args) do
    args = Enum.to_list(args)
    [%{from: from, to: to, days: days} | _] = args

    organizations =
      Enum.map(args, fn %{project: project} ->
        case Project.github_organization(project) do
          {:ok, organization} -> organization
          _ -> nil
        end
      end)
      |> Enum.reject(&is_nil/1)

    {:ok, dev_activity} = Github.total_dev_activity(organizations, from, to)

    dev_activity
    |> Enum.map(fn {organization, dev_activity} -> {organization, dev_activity / days} end)
    |> Map.new()
  end
end
