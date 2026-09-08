defmodule Sanbase.AI.DescriptionJobTest do
  use ExUnit.Case, async: true

  alias Sanbase.AI.DescriptionJob
  alias Sanbase.Chart.Configuration

  describe "normalize_description/1" do
    test "strips the indented lead sentence, trailing spaces and outer blank lines" do
      raw =
        "\n        Zcash price trend in plain terms.\n\nMeasures: price_usd  \nTags: x   \n\n  "

      assert DescriptionJob.normalize_description(raw) ==
               "Zcash price trend in plain terms.\n\nMeasures: price_usd\nTags: x"
    end

    test "keeps blank lines inside the description" do
      text = "Lead sentence.\n\nMeasures: price_usd\n\nTags: x"

      assert DescriptionJob.normalize_description(text) == text
    end

    test "passes nil through" do
      assert DescriptionJob.normalize_description(nil) == nil
    end
  end

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

    test "leaves out formula panes, which carry a client-generated UUID" do
      config = %Configuration{
        title: "ZEC 27.8",
        options: %{
          "widgets" => [
            %{"wm" => ["price_usd", "volume_usd"]},
            %{"wm" => ["social_volume_total", "01a01cf6-6c3f-7104-946e-472d88ad64b0"]}
          ]
        }
      }

      assert String.ends_with?(
               DescriptionJob.build_user_message(config, :charts),
               "Metrics tracked: price_usd, volume_usd, social_volume_total"
             )
    end

    test "says (none) only when the chart really tracks no metrics" do
      config = %Configuration{title: "Empty", metrics: [], metrics_json: %{}, options: %{}}

      assert DescriptionJob.build_user_message(config, :charts) =~ "Metrics tracked: (none)"
    end
  end
end
