# Prefix set for `Sanbase.Knowledge.AcademySearchEval.run_autocomplete/1`.
#
# Measures `academyAutocompleteQuestions`: what a user has typed so far in the
# Academy search box, and the page(s) a suggestion should point to. Built on
# 2026-09-29 from the golden search set (`academy_search_set.exs`) plus common
# short queries. Fields:
#   - prefix: the typed text (partial words and typos on purpose)
#   - expected_urls: a suggestion from any of these pages counts as a hit
#   - negative: true when the Academy does not cover the topic (excluded from hit rates)
#   - type: word | multi | partial | typo
url = &("https://academy.santiment.net" <> &1)

%{
  version: 1,
  items: [
    %{prefix: "rate limits", type: "multi", expected_urls: [url.("/sanapi/rate-limits/")]},
    %{
      prefix: "fetch metric",
      type: "multi",
      expected_urls: [url.("/sanapi/fetching-metrics/"), url.("/sanapi/common-queries/")]
    },
    %{
      prefix: "sql exchange",
      type: "multi",
      expected_urls: [url.("/santiment-queries/metric-tables/"), url.("/santiment-queries/")]
    },
    %{
      prefix: "sansheets api",
      type: "multi",
      expected_urls: [url.("/sansheets/adding-an-api-key/")]
    },
    %{prefix: "mcp conn", type: "partial", expected_urls: [url.("/mcp-connector/")]},
    %{prefix: "request rejected", type: "multi", expected_urls: [url.("/sanapi/complexity/")]},
    %{
      prefix: "sansheet func",
      type: "partial",
      expected_urls: [
        url.("/sansheets/functions/"),
        url.("/sansheets/functions/onchain/"),
        url.("/sansheets/functions/social/")
      ]
    },
    %{prefix: "rust sdk", type: "multi", negative: true, expected_urls: []},
    %{
      prefix: "circulation",
      type: "word",
      expected_urls: [
        url.("/metrics/circulation/"),
        url.("/education-and-use-cases/understanding-circulation/")
      ]
    },
    %{
      prefix: "whale alert",
      type: "multi",
      expected_urls: [url.("/education-and-use-cases/whale-activity-alert/")]
    },
    %{
      prefix: "api key",
      type: "multi",
      expected_urls: [
        url.("/products-and-plans/create-an-api-key/"),
        url.("/sansheets/adding-an-api-key/")
      ]
    },
    %{
      prefix: "max plan",
      type: "multi",
      expected_urls: [
        url.("/products-and-plans/sanapi-plans/"),
        url.("/products-and-plans/sanbase-plans/")
      ]
    },
    %{
      prefix: "price divergence",
      type: "multi",
      expected_urls: [
        url.("/metrics/price-daa-divergence/"),
        url.("/data-anomaly/network-activity-price-divergence/"),
        url.(
          "/education-and-use-cases/how-to-spot-tops-with-price-network-activity-divergences/"
        ),
        url.("/education-and-use-cases/price-to-daily-addresses-divergence-guide/"),
        url.("/metrics/btc-and-s-and-p-500-price-divergence/")
      ]
    },
    %{
      prefix: "burn san",
      type: "multi",
      expected_urls: [
        url.("/san-tokens/san-tokens-holding-benefits/"),
        url.("/products-and-plans/how-to-pay-with-crypto/")
      ]
    },
    %{prefix: "keybord", type: "typo", expected_urls: [url.("/sanbase/keyboard-shortcuts/")]},
    %{prefix: "refund", type: "word", negative: true, expected_urls: []},
    %{prefix: "dead address", type: "multi", expected_urls: [url.("/labels/dead-address/")]},
    %{
      prefix: "deposit addr",
      type: "partial",
      expected_urls: [url.("/glossary/deposit-addresses/")]
    },
    %{
      prefix: "network activity",
      type: "multi",
      expected_urls: [
        url.("/data-anomaly/network-activity-price-divergence/"),
        url.("/education-and-use-cases/how-to-spot-tops-with-price-network-activity-divergences/")
      ]
    },
    %{
      prefix: "mvrv danger",
      type: "multi",
      expected_urls: [url.("/data-anomaly/mvrv-danger-zone/")]
    },
    %{
      prefix: "nft trader",
      type: "multi",
      expected_urls: [url.("/labels/nft-trader-threshold/"), url.("/labels/nft-trader/")]
    },
    %{
      prefix: "whale",
      type: "word",
      expected_urls: [
        url.("/labels/whale/"),
        url.("/labels/whale-usd-balance/"),
        url.("/education-and-use-cases/whale-activity-alert/"),
        url.("/education-and-use-cases/whale-monitoring-to-predict-market-moves/"),
        url.("/metrics/whale-transaction-count/"),
        url.("/metrics/whale-transaction-volume/"),
        url.("/data-anomaly/eth-whale-dump/")
      ]
    },
    %{prefix: "dsprxy", type: "typo", expected_urls: [url.("/labels/dsproxy/")]},
    %{prefix: "solana validator", type: "multi", negative: true, expected_urls: []},
    %{
      prefix: "dormant circ",
      type: "partial",
      expected_urls: [url.("/metrics/dormant-circulation/")]
    },
    %{prefix: "gini", type: "word", expected_urls: [url.("/metrics/gini-index/")]},
    %{
      prefix: "mvrv",
      type: "word",
      expected_urls: [
        url.("/metrics/mvrv/"),
        url.("/data-anomaly/mvrv-danger-zone/"),
        url.("/data-anomaly/mvrv-opportunity-zone/")
      ]
    },
    %{
      prefix: "social dom",
      type: "partial",
      expected_urls: [
        url.("/metrics/social-dominance/"),
        url.("/data-anomaly/social-dominance-spike/")
      ]
    },
    %{
      prefix: "daa divergence",
      type: "multi",
      expected_urls: [
        url.("/metrics/price-daa-divergence/"),
        url.("/education-and-use-cases/price-to-daily-addresses-divergence-guide/")
      ]
    },
    %{
      prefix: "acquisition cost",
      type: "multi",
      expected_urls: [url.("/metrics/transacted-coin-acquisition-cost/")]
    },
    %{
      prefix: "exchnage inflow",
      type: "typo",
      expected_urls: [url.("/metrics/exchange-funds-flow/")]
    },
    %{prefix: "google trends", type: "multi", negative: true, expected_urls: []},
    %{
      prefix: "daily active",
      type: "multi",
      expected_urls: [
        url.("/metrics/daily-active-addresses/"),
        url.("/education-and-use-cases/understanding-daily-active-addresses/")
      ]
    },
    %{
      prefix: "age consumed",
      type: "multi",
      expected_urls: [
        url.("/metrics/age-consumed/"),
        url.("/metrics/age-consumed/age-consumed-technical/"),
        url.("/education-and-use-cases/age-consumed-alert/"),
        url.("/education-and-use-cases/timing-market-volatility-with-token-age-consumed/")
      ]
    },
    %{
      prefix: "santiment quer",
      type: "partial",
      expected_urls: [
        url.("/santiment-queries/"),
        url.("/santiment-queries/metric-tables/"),
        url.("/santiment-queries/rate-limits-and-credits-cost/")
      ]
    },
    %{prefix: "alerts", type: "word", expected_urls: [url.("/sanbase/alerts-page/")]},
    %{prefix: "complexity", type: "word", expected_urls: [url.("/sanapi/complexity/")]},
    %{
      prefix: "how do i create an api",
      type: "partial",
      expected_urls: [url.("/products-and-plans/create-an-api-key/")]
    },
    %{
      prefix: "graphql",
      type: "word",
      expected_urls: [
        url.("/sanapi/accessing-the-api/"),
        url.("/sanapi/common-queries/"),
        url.("/sanapi/fetching-metrics/")
      ]
    },
    %{prefix: "smart walet", type: "typo", expected_urls: [url.("/labels/dsproxy/")]}
  ]
}
