defmodule Sanbase.Project.Multichain do
  @moduledoc ~s"""
  Multichain support for assets

  Historically, multichain support has been done by following a naming convention.
  This lack of formal definition skews some statistics and analysis, for example
  computing the total marketcap of a watchlist.
  """

  alias Sanbase.Project

  @prefix_mapping %{
    "arb-" => %{ecosystem: "arbitrum"},
    "o-" => %{ecosystem: "optimism"},
    "a-" => %{ecosystem: "avalanche"},
    "p-" => %{ecosystem: "polygon"},
    "bnb-" => %{ecosystem: "binance-smart-chain"}
  }

  @doc """
  Marks a project as a multichain project
  """
  @spec mark_multichain(
          %Project{},
          multichain_project_group_key: String.t(),
          ecosystem_id: non_neg_integer()
        ) ::
          {:ok, Ecto.Schema.t()} | {:error, Ecto.Changeset.t()}
  def mark_multichain(project, opts) do
    opts = Keyword.validate!(opts, [:ecosystem_id, :multichain_project_group_key])

    project
    |> Project.changeset(%{
      multichain_project_group_key: opts[:multichain_project_group_key],
      deployed_on_ecosystem_id: opts[:ecosystem_id]
    })
    |> Ecto.Changeset.validate_required([:deployed_on_ecosystem_id, :multichain_project_group_key])
    |> Sanbase.Repo.update()
  end

  def find_missing_data_by_prefix() do
    ecosystems_map = Sanbase.Ecosystem.get_ecosystems() |> Map.new(fn e -> {e.name, e.id} end)

    Project.List.projects()
    |> Enum.filter(& &1.multichain_project_group_key)
    |> Enum.each(fn project ->
      case matching_prefix(project.slug) do
        {:error, :nomatch} ->
          :ok

        {:ok, {prefix, ecosystem}} ->
          if not Map.has_key?(ecosystems_map, ecosystem) do
            raise("""
            Ecosystem #{ecosystem} should exist but it does not.
            Attempted to use it to set multichain values for projects with a specified prefix.
            """)
          end

          # The prefix is a string like arb-, p-, o-, etc. (with the trailing hyphen included)
          # All projects with the same string after the prefix are considered to be grouped together.
          key = String.trim_leading(project.slug, prefix)

          {:ok, _} =
            mark_multichain(project,
              multichain_project_group_key: key,
              ecosystem_id: ecosystems_map[ecosystem]
            )
      end
    end)
  end

  defp matching_prefix(slug) do
    case Enum.find(@prefix_mapping, fn {k, _v} -> String.starts_with?(slug, k) end) do
      {prefix, ecosystem} -> {:ok, {prefix, ecosystem}}
      nil -> {:error, :nomatch}
    end
  end
end
