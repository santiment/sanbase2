defmodule Sanbase.AI.DescriptionJobTest do
  use ExUnit.Case, async: true

  alias Sanbase.AI.DescriptionJob
  alias Sanbase.Chart.Configuration

  describe "build_user_message/2 for charts" do
    test "lists the metrics from metrics_json, with their slugs, in pane order" do
      config = %Configuration{
        title: "ETH holders",
        metrics: [],
        metrics_json: %{
          "0" => %{"metric" => "price_usd", "slug" => "ethereum"},
          "1" => %{"metric" => "amount_in_top_holders", "slug" => "ethereum"},
          "10" => %{"metric" => "social_volume_total"},
          "2" => %{"metric" => "daily_active_addresses"}
        }
      }

      assert DescriptionJob.build_user_message(config, :charts) =~
               "Metrics tracked: price_usd (ethereum), amount_in_top_holders (ethereum), daily_active_addresses, social_volume_total"
    end

    test "falls back to the per-widget metric lists when metrics_json is empty" do
      config = %Configuration{
        title: "ZEC 27.8",
        metrics: [],
        metrics_json: %{},
        options: %{
          "widgets" => [
            %{"widget" => "ChartWidget", "wm" => ["price_usd", "volume_usd"]},
            %{"widget" => "ChartWidget", "wm" => ["[1;social_volume_total;zcash;ZEC]"]},
            %{"widget" => "HoldersWidget"}
          ]
        }
      }

      assert DescriptionJob.build_user_message(config, :charts) =~
               "Metrics tracked: price_usd, volume_usd, social_volume_total"
    end

    test "decodes extended metric keys from the legacy metrics array" do
      config = %Configuration{
        title: "Tether activity",
        metrics: [
          "price_usd",
          "[1;daily_active_addresses;tether;USDT]",
          "[3;percent_of_holders_distribution_combined_balance;1_to_10;10_to_100]"
        ]
      }

      assert DescriptionJob.build_user_message(config, :charts) =~
               "Metrics tracked: price_usd, daily_active_addresses, percent_of_holders_distribution_combined_balance"
    end

    test "prefers metrics_json over the widgets and the legacy array" do
      config = %Configuration{
        title: "ETH price",
        metrics: ["[1;price_usd;ethereum;ETH]"],
        metrics_json: %{"0" => %{"metric" => "price_usd", "slug" => "ethereum"}},
        options: %{"widgets" => [%{"wm" => ["[1;price_usd;ethereum;ETH]"]}]}
      }

      assert String.ends_with?(
               DescriptionJob.build_user_message(config, :charts),
               "Metrics tracked: price_usd (ethereum)"
             )
    end

    test "keeps one entry per asset a metric is plotted for" do
      config = %Configuration{
        title: "USDT active addresses across chains",
        metrics_json: %{
          "0" => %{"metric" => "daily_active_addresses", "slug" => "tether"},
          "1" => %{"metric" => "daily_active_addresses", "slug" => "bnb-tether"},
          "2" => %{"metric" => "daily_active_addresses", "slug" => "tether"}
        }
      }

      assert String.ends_with?(
               DescriptionJob.build_user_message(config, :charts),
               "Metrics tracked: daily_active_addresses (tether), daily_active_addresses (bnb-tether)"
             )
    end

    test "says (none) only when the chart really tracks no metrics" do
      config = %Configuration{title: "Empty", metrics: [], metrics_json: %{}, options: %{}}

      assert DescriptionJob.build_user_message(config, :charts) =~ "Metrics tracked: (none)"
    end
  end
end
