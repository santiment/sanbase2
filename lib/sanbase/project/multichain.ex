defmodule Sanbase.Project.Multichain do
  @moduledoc ~s"""
  Multichain support for assets

  Historically, multichain support has been done by following a naming convention.
  This lack of formal definition skews some statistics and analysis, for example
  computing the total marketcap of a watchlist.
  """

  alias Sanbase.Project

  @prefix_mapping %{
    "arb-" => %{ecosystem: "Arbitrum"},
    "o-" => %{ecosystem: "Optimism"},
    "a-" => %{ecosystem: "Avalanche"},
    "p-" => %{ecosystem: "Polygon"},
    "bnb-" => %{ecosystem: "BNB Chain"}
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
    |> Ecto.Changeset.validate_required([
      :deployed_on_ecosystem_id,
      :multichain_project_group_key
    ])
    |> Sanbase.Repo.update()
  end

  def fill_missing_data_by_prefix do
    # The project slug is always lowercased, the ecosystem might be not
    ecosystems_map =
      Map.new(Sanbase.Ecosystem.all(), fn e -> {e.ecosystem, e.id} end)

    Project.List.projects()
    |> Enum.filter(&is_nil(&1.multichain_project_group_key))
    |> Enum.map(fn project ->
      maybe_mark_as_multichain(project, ecosystems_map)
    end)
  end

  defp matching_prefix(slug) do
    case Enum.find(@prefix_mapping, fn {k, _v} -> String.starts_with?(slug, k) end) do
      {prefix, ecosystem} -> {:ok, {prefix, ecosystem}}
      nil -> {:error, :nomatch}
    end
  end

  defp maybe_mark_as_multichain(project, ecosystems_map) do
    case matching_prefix(project.slug) do
      {:error, :nomatch} ->
        :ok

      {:ok, {prefix, %{ecosystem: ecosystem}}} ->
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
  end
end
