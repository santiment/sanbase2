defmodule Sanbase.Factory.Helper do
  def rand_address("ripple") do
    [
      "r9vbV3EHvXWjSkeQ6CAcYVPGeq7TuiXY2X",
      "rUrdFHbrEKWNQQ444zcTLrThjcnHCw2FPu",
      "r49nVgaYSDuU7GEQh4mF1nyjsXSVRcUHsr",
      "rphasxS8Q5p5TLTpScQCBhh5HfJfPbM2M8",
      "rKWFsTLRPrgC8KDC7fCqQRzDsvajgcM1Tp",
      "rn8rUkteSFCL5gbi563RPYWew9mMqPhVGD",
      "rHAAGfqnBYxrUVYnqYyKcRESNyg8pqJdgN",
      "rJWnjUKWGJBZrJAZRGZtso7gQk6T2Wv6We",
      "r9YoMBhhQbEA8jsvHnWhAM8tdpN4xYrb8B",
      "rsWxmCo4ghqb5h1dsphKU1V1EKsMYSpXjQ",
      "rP8np2qeg88Sr1rCxc86y9KuCCnvv8854u",
      "rsK1CYzQqzc1xJ1L33pNjj26MPNVsT9RWz",
      "r3MeEnYZY9fAd5pGjAWf4dfJsQBVY9FZRL",
      "r3NqSG5o5iKTPKMqaR1xmCVvmEcSC3nmKn",
      "r3PDtZSa5LiYp1Ysn1vMuMzB59RzV3W9QH",
      "r3SRtN5Nt4uyLj2XhNhUGMBekTLkfBMPWS",
      "r3T3kYf2oGequEHvT7M4F6byeE2PzxwP5E",
      "r3kmLJN5D28dHuH8vZNUZpMC43pEHpaocV",
      "r3knww8JXufhM4R5uYdUCWScMYWGzSBsN3"
    ]
    |> Enum.random()
  end

  def rand_address("ethereum") do
    Faker.Blockchain.Ethereum.address()
  end

  def rand_interval() do
    (Enum.random([1, 3, 5, 10, 12, 60]) |> to_string) <>
      Enum.random(["m", "h", "d", "w"])
  end

  def rand_trigger_settings(rand_project, rand_erc20_project) do
    [
      %{
        type: "metric_signal",
        metric: "social_volume_total",
        target: %{text: "random text"},
        channel: "telegram",
        operation: %{above: 300}
      },
      %{
        type: "metric_signal",
        metric: "social_volume_total",
        target: %{slug: "bitcoin text"},
        channel: ["telegram", "email"],
        operation: %{above: 5000}
      },
      %{
        type: "metric_signal",
        metric: "mvrv_usd_intraday",
        target: %{slug: rand_project.().slug},
        channel: "telegram",
        time_window: "2d",
        operation: %{below: 40}
      },
      %{
        type: "metric_signal",
        metric: "active_addresses_24h",
        target: %{slug: rand_project.().slug},
        channel: ["telegram", "email"],
        time_window: "2d",
        operation: %{above: 1000}
      },
      %{
        type: "wallet_movement",
        selector: %{infrastructure: "ETH", slug: rand_erc20_project.().slug},
        target: %{address: rand_address("ethereum")},
        channel: "telegram",
        time_window: "1d",
        operation: %{amount_up: 200.0}
      },
      %{
        type: "wallet_movement",
        selector: %{infrastructure: "XRP", currency: "BTC"},
        target: %{address: rand_address("ripple")},
        channel: "telegram",
        time_window: "1d",
        operation: %{amount_down: 50.0}
      }
    ]
    |> Enum.random()
  end
end
