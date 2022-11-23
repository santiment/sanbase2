defmodule Sanbase.Mix.GenerateProjectsData do
  alias Sanbase.Model.Project
  import Ecto.Query

  require Jason.Helpers

  def run(path) do
    get_projects_data()
    |> Enum.map(&encode/1)
    |> export_json(path)
  end

  def get_projects_data() do
    from(p in Project,
      where: not is_nil(p.slug),
      left_join: contract in assoc(p, :contract_addresses),
      left_join: github in assoc(p, :github_organizations),
      left_join: infrastructure in assoc(p, :infrastructure),
      select: %{
        slug: p.slug,
        name: p.name,
        ticker: p.ticker,
        infrastructure: infrastructure.code,
        description: p.description,
        website: p.website_link,
        twitter: p.twitter_link,
        discord: p.discord_link,
        slack: p.slack_link,
        telegram: p.telegram_link,
        reddit: p.reddit_link,
        blog: p.blog_link,
        github_organizations: github,
        contract_addresses: contract
      }
    )
    |> Sanbase.Repo.all()
  end

  def export_json(list, path) do
    Enum.each(list, fn {slug, json} ->
      path = Path.join([path, slug])
      File.mkdir_p!(path)
      File.write!(Path.join([path, "data.json"]), json)
    end)
  end

  defp encode(map) do
    slug = map[:slug] || raise("Missing slug in map list #{inspect(map)}")

    general =
      [
        slug: slug,
        name: map[:name],
        ticker: map[:ticker],
        description: map[:description],
        website: map[:website]
      ]
      |> remove_nils()
      |> Jason.OrderedObject.new()

    social =
      [
        twitter: map[:twitter],
        telegram: map[:telegram],
        discord: map[:discord],
        slack: map[:slack],
        reddit: map[:reddit],
        blog: map[:blog]
      ]
      |> remove_nils()
      |> Jason.OrderedObject.new()

    orgs =
      (Map.get(map, :github_organizations) || []) |> List.wrap() |> Enum.map(& &1.organization)

    development =
      [
        github_organizations: orgs
      ]
      |> Map.new()

    contracts =
      (Map.get(map, :contract_addresses) || [])
      |> List.wrap()
      |> Enum.map(fn contract ->
        [
          address: contract.address,
          blockchain: Project.infrastructure_to_blockchain(map[:infrastructure]),
          decimals: contract.decimals,
          label: contract.label,
          description: contract.description
        ]
        |> remove_nils()
        |> Jason.OrderedObject.new()
      end)

    json =
      [
        general: general,
        social: social,
        development: development,
        blockchain: %{contracts: contracts}
      ]
      |> Jason.OrderedObject.new()
      |> Jason.encode!(%{pretty: true})

    {slug, json}
  end

  defp remove_nils(keyword) do
    Enum.reject(keyword, fn {_k, v} -> v == nil end)
  end
end
