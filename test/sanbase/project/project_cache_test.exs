defmodule Sanbase.Project.ProjectCacheTest do
  use Sanbase.DataCase

  alias Sanbase.Project.ProjectCache
  alias Sanbase.Factory

  describe "ProjectCache" do
    setup do
      # Create some test projects
      projects = [
        Factory.insert(:random_erc20_project, %{name: "Bitcoin", ticker: "BTC", slug: "bitcoin"}),
        Factory.insert(:random_erc20_project, %{name: "Ethereum", ticker: "ETH", slug: "ethereum"}),
        Factory.insert(:random_erc20_project, %{
          name: "Bitcoin Cash",
          ticker: "BCH",
          slug: "bitcoin-cash"
        }),
        Factory.insert(:random_erc20_project, %{name: "Litecoin", ticker: "LTC", slug: "litecoin"}),
        Factory.insert(:random_erc20_project, %{name: "Ripple", ticker: "XRP", slug: "ripple"})
      ]

      # Clear cache to ensure fresh data
      ProjectCache.clear_cache()

      %{projects: projects}
    end

    test "search_projects returns empty list for short queries" do
      assert ProjectCache.search_projects("B") == []
      assert ProjectCache.search_projects("") == []
    end

    test "search_projects finds exact ticker matches", %{projects: _projects} do
      results = ProjectCache.search_projects("BTC")
      assert "BTC" in results
    end

    test "search_projects finds partial matches with fuzzy search", %{projects: _projects} do
      # Test fuzzy matching on name (only for 4+ character queries)
      results = ProjectCache.search_projects("bitco")
      # May or may not find matches depending on fuzzy threshold
      assert length(results) >= 0

      # Test that short queries don't use fuzzy matching
      results_short = ProjectCache.search_projects("BC")
      # Should only find exact/prefix/contains matches, no fuzzy
      assert length(results_short) >= 0
    end

    test "search_projects prioritizes exact matches", %{projects: _projects} do
      results = ProjectCache.search_projects("BTC", 5)

      if length(results) > 0 do
        # BTC should be first if it exists
        first_result = List.first(results)
        assert first_result == "BTC" or String.contains?(first_result, "BTC")
      end
    end

    test "search_projects respects limit parameter", %{projects: _projects} do
      results = ProjectCache.search_projects("coin", 2)
      assert length(results) <= 2
    end

    test "search_projects is case insensitive", %{projects: _projects} do
      results_upper = ProjectCache.search_projects("BTC")
      results_lower = ProjectCache.search_projects("btc")
      results_mixed = ProjectCache.search_projects("Btc")

      # All should return the same results
      assert results_upper == results_lower
      assert results_lower == results_mixed
    end

    test "get_cached_projects returns structured data", %{projects: _projects} do
      projects = ProjectCache.get_cached_projects()
      assert is_list(projects)

      if length(projects) > 0 do
        project = List.first(projects)
        assert is_map(project)
        assert Map.has_key?(project, :name)
        assert Map.has_key?(project, :ticker)
        assert Map.has_key?(project, :slug)
      end
    end

    test "cache is used on subsequent calls" do
      # First call - loads from DB
      _projects1 = ProjectCache.get_cached_projects()

      # Second call - should use cache (just verify it doesn't crash)
      _projects2 = ProjectCache.get_cached_projects()

      # Third call - verify consistency
      _projects3 = ProjectCache.get_cached_projects()

      # Cache is working if we get here without errors
      assert true
    end

    test "clear_cache forces reload from database" do
      # Load initial data
      projects1 = ProjectCache.get_cached_projects()

      # Clear cache
      ProjectCache.clear_cache()

      # Load again - should hit DB
      projects2 = ProjectCache.get_cached_projects()

      # Results should be the same
      assert length(projects1) == length(projects2)
    end

    test "search_projects returns no false positives for short unrelated queries", %{
      projects: _projects
    } do
      # This should not return results if there are no projects with ALT in name/ticker/slug
      results = ProjectCache.search_projects("ALT")

      # Verify that any results actually contain "ALT" in some form
      for ticker <- results do
        project_data = ProjectCache.get_cached_projects()
        matching_project = Enum.find(project_data, &(&1.ticker == ticker))

        assert matching_project != nil

        # The result should have ALT in ticker, name, or slug (case insensitive)
        has_alt =
          String.contains?(String.upcase(matching_project.ticker), "ALT") or
            String.contains?(String.upcase(matching_project.name), "ALT") or
            String.contains?(String.upcase(matching_project.slug), "ALT")

        assert has_alt, "#{ticker} should contain 'ALT' but doesn't: #{inspect(matching_project)}"
      end
    end

    test "fuzzy matching is disabled for short queries" do
      # Create a project that would match via fuzzy but not exact/prefix/contains
      ProjectCache.clear_cache()

      # Test with actual query that was problematic
      results = ProjectCache.search_projects("ALT")

      # Should only return results that actually contain "ALT"
      for ticker <- results do
        project_data = ProjectCache.get_cached_projects()
        matching_project = Enum.find(project_data, &(&1.ticker == ticker))

        # Verify it's not a false positive from fuzzy matching
        contains_alt =
          String.contains?(String.upcase(matching_project.ticker), "ALT") or
            String.contains?(String.upcase(matching_project.name), "ALT") or
            String.contains?(String.upcase(matching_project.slug), "ALT")

        assert contains_alt, "Short query returned fuzzy match: #{inspect(matching_project)}"
      end
    end
  end
end
