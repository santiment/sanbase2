defmodule Sanbase.Project.EcosystemTest do
  use SanbaseWeb.ConnCase, async: true

  import Sanbase.Factory

  test "compute full path ecosystem" do
    insert(:project, name: "Ethereum", slug: "ethereum", ecosystem: "ethereum")
    insert(:project, name: "Bitcoin", slug: "bitcoin", ecosystem: "bitcoin")
    insert(:project, name: "Santiment", slug: "santiment", ecosystem: "ethereum")
    insert(:project, name: "Arbitrum", slug: "arbitrum", ecosystem: "ethereum")
    insert(:project, name: "Xyz", slug: "xyz", ecosystem: "arbitrum")
    insert(:project, name: "Abc", slug: "abc", ecosystem: "arbitrum")
    insert(:project, name: "Ykc", slug: "ykc", ecosystem: "abc")

    list =
      Sanbase.Project.Job.compute_ecosystem_full_path()
      |> Enum.map(fn {p, e} -> {p.slug, e} end)

    expected_list = [
      {"abc", "/ethereum/arbitrum/abc/"},
      {"arbitrum", "/ethereum/arbitrum/"},
      {"bitcoin", "/bitcoin/"},
      {"ethereum", "/ethereum/"},
      {"santiment", "/ethereum/santiment/"},
      {"xyz", "/ethereum/arbitrum/xyz/"},
      {"ykc", "/ethereum/arbitrum/abc/ykc/"}
    ]

    assert Enum.sort(list) == Enum.sort(expected_list)
  end
end
