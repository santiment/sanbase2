# Golden question set for `Sanbase.Knowledge.AcademySearchEval`.
#
# Measures the production `academySearch` path
# (`Sanbase.AI.AcademyAIService.semantic_search/2`): vector search + rerank.
#
# Built on 2026-09-29 from a 32-question evaluation against prod and the
# academy repo sources (4 slices x 8 questions). Fields:
#   - expected_urls: the page(s) that should rank first (page-level match on academy_url)
#   - acceptable_urls: related pages that also count as relevant (not used for hit@K)
#   - answer_facts: short phrases copied from the source md (matched after
#     lowercasing and stripping punctuation) that a useful result must contain
#   - negative: true when the Academy does not cover the question; used to
#     measure whether scores separate "not covered" from real answers
#   - type: question category, used for per-type breakdowns
%{
  version: 1,
  items: [
    %{
      id: "api_dev-q1",
      question:
        "What are the Santiment API rate limits and how do I know when I am being rate limited?",
      type: "auth_rate_limits",
      negative: false,
      expected_urls: ["https://academy.santiment.net/sanapi/rate-limits/"],
      acceptable_urls: [
        "https://academy.santiment.net/sanapi/accessing-the-api/",
        "https://academy.santiment.net/products-and-plans/sanapi-plans/"
      ],
      answer_facts: [
        "when the rate limit is reached an error response with",
        "x ratelimit remaining minute",
        "per minute per hour and per month"
      ]
    },
    %{
      id: "api_dev-q2",
      question: "How do I fetch daily active addresses for bitcoin with a GraphQL query?",
      type: "code_graphql",
      negative: false,
      expected_urls: ["https://academy.santiment.net/sanapi/common-queries/"],
      acceptable_urls: [
        "https://academy.santiment.net/sanapi/fetching-metrics/",
        "https://academy.santiment.net/metrics/daily-active-addresses/"
      ],
      answer_facts: [
        "getmetric metric daily active addresses timeseriesdatajson selector slug bitcoin"
      ]
    },
    %{
      id: "api_dev-q3",
      question:
        "SQL query to get the balance of centralized exchange addresses in Santiment Queries",
      type: "code_sql",
      negative: false,
      expected_urls: ["https://academy.santiment.net/santiment-queries/metric-tables/"],
      acceptable_urls: [
        "https://academy.santiment.net/santiment-queries/writing-sql-queries/",
        "https://academy.santiment.net/santiment-queries/exploration/"
      ],
      answer_facts: [
        "select dt value as balance from labeled intraday metrics final where",
        "label id dictget labels by fqn label id santiment centralized exchange v1 and metric id dictget"
      ]
    },
    %{
      id: "api_dev-q4",
      question: "How do I add my API key to Sansheets in Google Sheets?",
      type: "sansheets_howto",
      negative: false,
      expected_urls: ["https://academy.santiment.net/sansheets/adding-an-api-key/"],
      acceptable_urls: [
        "https://academy.santiment.net/sansheets/setting-up/",
        "https://academy.santiment.net/products-and-plans/create-an-api-key/"
      ],
      answer_facts: [
        "you will find the option to add an api key",
        "paste it into the popup and click ok"
      ]
    },
    %{
      id: "api_dev-q5",
      question: "How do I connect the Santiment MCP connector to Claude?",
      type: "mcp_setup",
      negative: false,
      expected_urls: ["https://academy.santiment.net/mcp-connector/"],
      acceptable_urls: [
        "https://academy.santiment.net/for-ai/",
        "https://academy.santiment.net/santiment-skills/",
        "https://academy.santiment.net/mcp-connector/open-claw/"
      ],
      answer_facts: [
        "navigate to the customize connectors section",
        "mcp server url https api santiment net mcp"
      ]
    },
    %{
      id: "api_dev-q6",
      question:
        "Why does my request get rejected when I ask for several years of data for many coins at once?",
      type: "paraphrase",
      negative: false,
      expected_urls: ["https://academy.santiment.net/sanapi/complexity/"],
      acceptable_urls: [
        "https://academy.santiment.net/sanapi/historical-and-realtime-data-restrictions/",
        "https://academy.santiment.net/sanapi/accessing-the-api/"
      ],
      answer_facts: ["if it exceeds a certain threshold the api server rejects"]
    },
    %{
      id: "api_dev-q7",
      question: "sansheet functons",
      type: "typo_short",
      negative: false,
      expected_urls: ["https://academy.santiment.net/sansheets/functions/"],
      acceptable_urls: [
        "https://academy.santiment.net/sansheets/functions/onchain/",
        "https://academy.santiment.net/sansheets/functions/social/"
      ],
      answer_facts: ["on chain data functions"]
    },
    %{
      id: "api_dev-q8",
      question: "Is there an official Rust SDK for the Santiment API?",
      type: "not_in_academy",
      negative: true,
      expected_urls: [],
      acceptable_urls: ["https://academy.santiment.net/sanapi/accessing-the-api/"],
      answer_facts: []
    },
    %{
      id: "guides-q1",
      question: "What is the circulation metric and how does it treat wash trades?",
      type: "definition",
      negative: false,
      expected_urls: [
        "https://academy.santiment.net/education-and-use-cases/understanding-circulation/"
      ],
      acceptable_urls: ["https://academy.santiment.net/metrics/circulation/"],
      answer_facts: ["accounted tokens in circulation are unique meaning that if the"]
    },
    %{
      id: "guides-q2",
      question: "How do I set up a whale transaction alert in Sanbase?",
      type: "how_to",
      negative: false,
      expected_urls: [
        "https://academy.santiment.net/education-and-use-cases/whale-activity-alert/"
      ],
      acceptable_urls: ["https://academy.santiment.net/sanbase/alerts-page/"],
      answer_facts: ["navigate to the metrics section and choose your preferred whale"]
    },
    %{
      id: "guides-q3",
      question: "How do I generate an API key for SanAPI?",
      type: "how_to",
      negative: false,
      expected_urls: ["https://academy.santiment.net/products-and-plans/create-an-api-key/"],
      acceptable_urls: [
        "https://academy.santiment.net/sanapi/accessing-the-api/",
        "https://academy.santiment.net/sanbase/account-settings/",
        "https://academy.santiment.net/sansheets/adding-an-api-key/"
      ],
      answer_facts: ["in the account settings click on the generate button to"]
    },
    %{
      id: "guides-q4",
      question: "How many API calls per month does the Sanbase Max plan allow?",
      type: "plans/pricing",
      negative: false,
      expected_urls: ["https://academy.santiment.net/products-and-plans/sanapi-plans/"],
      acceptable_urls: ["https://academy.santiment.net/products-and-plans/sanbase-plans/"],
      answer_facts: ["monthly limit 1 000 api calls 5 000 api calls"]
    },
    %{
      id: "guides-q5",
      question:
        "How can divergence between price and daily active addresses or network growth help spot market tops?",
      type: "multi_doc/conceptual",
      negative: false,
      expected_urls: [
        "https://academy.santiment.net/education-and-use-cases/how-to-spot-tops-with-price-network-activity-divergences/"
      ],
      acceptable_urls: [
        "https://academy.santiment.net/education-and-use-cases/price-to-daily-addresses-divergence-guide/",
        "https://academy.santiment.net/education-and-use-cases/understanding-daily-active-addresses/",
        "https://academy.santiment.net/metrics/price-daa-divergence/",
        "https://academy.santiment.net/data-anomaly/network-activity-price-divergence/"
      ],
      answer_facts: ["if there is a spike in these metrics during a"]
    },
    %{
      id: "guides-q6",
      question: "Can I get a cheaper subscription by destroying my Santiment coins?",
      type: "paraphrased",
      negative: false,
      expected_urls: ["https://academy.santiment.net/san-tokens/san-tokens-holding-benefits/"],
      acceptable_urls: [
        "https://academy.santiment.net/products-and-plans/how-to-pay-with-crypto/"
      ],
      answer_facts: [
        "you can burn your san tokens to pay for a",
        "credit your sanbase account at a rate of twice the"
      ]
    },
    %{
      id: "guides-q7",
      question: "keybord shortcuts",
      type: "short_keyword/typo",
      negative: false,
      expected_urls: ["https://academy.santiment.net/sanbase/keyboard-shortcuts/"],
      acceptable_urls: [],
      answer_facts: ["select the sanbase search bar"]
    },
    %{
      id: "guides-q8",
      question: "How do I get a refund for my Sanbase subscription?",
      type: "not_in_academy",
      negative: true,
      expected_urls: [],
      acceptable_urls: [],
      answer_facts: []
    },
    %{
      id: "labels_anomaly-q1",
      question: "What does the dead address label mean?",
      type: "definition",
      negative: false,
      expected_urls: ["https://academy.santiment.net/labels/dead-address/"],
      acceptable_urls: ["https://academy.santiment.net/labels/"],
      answer_facts: ["addresses that cannot be owned by anyone and or are"]
    },
    %{
      id: "labels_anomaly-q2",
      question: "What are deposit addresses and why are they useful for analysis?",
      type: "definition",
      negative: false,
      expected_urls: ["https://academy.santiment.net/glossary/deposit-addresses/"],
      acceptable_urls: [
        "https://academy.santiment.net/labels/deposit/",
        "https://academy.santiment.net/metrics/daily-active-deposits/",
        "https://academy.santiment.net/metrics/active-deposits/"
      ],
      answer_facts: [
        "temporary wallets are referred to as deposit addresses",
        "total number of deposit addresses can serve as a reliable"
      ]
    },
    %{
      id: "labels_anomaly-q3",
      question: "How can I use the network activity price divergence anomaly to time exits?",
      type: "interpretation",
      negative: false,
      expected_urls: [
        "https://academy.santiment.net/data-anomaly/network-activity-price-divergence/"
      ],
      acceptable_urls: [
        "https://academy.santiment.net/education-and-use-cases/how-to-spot-tops-with-price-network-activity-divergences/",
        "https://academy.santiment.net/metrics/price-daa-divergence/"
      ],
      answer_facts: [
        "traders can use this anomaly as a contrarian indicator to",
        "triggered only if the price growth exceeds 3 on the"
      ]
    },
    %{
      id: "labels_anomaly-q4",
      question: "How should I combine the MVRV danger zone with the opportunity zone anomaly?",
      type: "interpretation",
      negative: false,
      expected_urls: ["https://academy.santiment.net/data-anomaly/mvrv-danger-zone/"],
      acceptable_urls: [
        "https://academy.santiment.net/data-anomaly/mvrv-opportunity-zone/",
        "https://academy.santiment.net/metrics/mvrv/"
      ],
      answer_facts: ["by leveraging both anomalies you can strategically time their entry"]
    },
    %{
      id: "labels_anomaly-q5",
      question: "What is the label fqn for NFT trader threshold 1000?",
      type: "api/label_name",
      negative: false,
      expected_urls: ["https://academy.santiment.net/labels/nft-trader-threshold/"],
      acceptable_urls: [
        "https://academy.santiment.net/labels/label-fqn/",
        "https://academy.santiment.net/labels/nft-trader/"
      ],
      answer_facts: ["santiment nft trader threshold 1000 v1"]
    },
    %{
      id: "labels_anomaly-q6",
      question:
        "How much does a wallet need to hold to count as a big holder of a coin with a 100 billion market cap?",
      type: "paraphrase",
      negative: false,
      expected_urls: ["https://academy.santiment.net/labels/whale-usd-balance/"],
      acceptable_urls: ["https://academy.santiment.net/labels/whale/"],
      answer_facts: ["if the coin s market capitalization is 100b we label"]
    },
    %{
      id: "labels_anomaly-q7",
      question: "dsprxy smart walet",
      type: "typo/keyword",
      negative: false,
      expected_urls: ["https://academy.santiment.net/labels/dsproxy/"],
      acceptable_urls: [],
      answer_facts: [
        "dsproxy developed by dapphub is a smart wallet that offers",
        "execute multiple contract calls in a single transaction"
      ]
    },
    %{
      id: "labels_anomaly-q8",
      question: "Which data anomaly detects Solana validator downtime?",
      type: "not_in_academy",
      negative: true,
      expected_urls: [],
      acceptable_urls: [],
      answer_facts: []
    },
    %{
      id: "metrics-m1",
      question: "What does the dormant circulation metric measure?",
      type: "definition",
      negative: false,
      expected_urls: ["https://academy.santiment.net/metrics/dormant-circulation/"],
      acceptable_urls: [
        "https://academy.santiment.net/metrics/circulation/",
        "https://academy.santiment.net/metrics/details/timebound/",
        "https://academy.santiment.net/metrics/age-consumed/"
      ],
      answer_facts: ["dormant circulation shows the number of unique coins tokens transacted"]
    },
    %{
      id: "metrics-m2",
      question: "What is the Gini index metric in crypto?",
      type: "definition",
      negative: false,
      expected_urls: ["https://academy.santiment.net/metrics/gini-index/"],
      acceptable_urls: [
        "https://academy.santiment.net/metrics/supply-distribution/",
        "https://academy.santiment.net/metrics/top-holders/"
      ],
      answer_facts: [
        "ranging from 0 perfect equality to 1 perfect inequality",
        "can also be applied to cryptocurrencies to measure the distribution"
      ]
    },
    %{
      id: "metrics-m3",
      question: "How should I interpret a negative MVRV long/short difference?",
      type: "interpretation",
      negative: false,
      expected_urls: ["https://academy.santiment.net/metrics/mvrv/"],
      acceptable_urls: [
        "https://academy.santiment.net/sansheets/pro-templates/",
        "https://academy.santiment.net/education-and-use-cases/understanding-long-term-market-trends-and-cycles/"
      ],
      answer_facts: ["negative values mean that short term holders will realize higher"]
    },
    %{
      id: "metrics-m4",
      question: "Why can social dominance of an asset be higher than 100%?",
      type: "interpretation",
      negative: false,
      expected_urls: ["https://academy.santiment.net/metrics/social-dominance/"],
      acceptable_urls: ["https://academy.santiment.net/metrics/social-volume/"],
      answer_facts: ["this definition allows the social dominance of an asset to"]
    },
    %{
      id: "metrics-m5",
      question:
        "Which SanAPI metric name gives a smoothed divergence between price and daily active addresses?",
      type: "api",
      negative: false,
      expected_urls: ["https://academy.santiment.net/metrics/price-daa-divergence/"],
      acceptable_urls: ["https://academy.santiment.net/metrics/daily-active-addresses/"],
      answer_facts: [
        "adjusted price daa divergence smoother version of price daa divergence averaging data over the last"
      ]
    },
    %{
      id: "metrics-m6",
      question: "At what price were the coins that moved today originally bought?",
      type: "paraphrase",
      negative: false,
      expected_urls: ["https://academy.santiment.net/metrics/transacted-coin-acquisition-cost/"],
      acceptable_urls: [
        "https://academy.santiment.net/metrics/circulation/",
        "https://academy.santiment.net/metrics/mean-realized-price/"
      ],
      answer_facts: ["for the coins tokens transacted on a given day get"]
    },
    %{
      id: "metrics-m7",
      question: "exchnage inflow",
      type: "typo",
      negative: false,
      expected_urls: ["https://academy.santiment.net/metrics/exchange-funds-flow/"],
      acceptable_urls: [
        "https://academy.santiment.net/metrics/labeled-exchange/",
        "https://academy.santiment.net/metrics/supply-on-or-outside-exchanges/"
      ],
      answer_facts: ["exchange inflow how many coins tokens are moved from non exchange"]
    },
    %{
      id: "metrics-m8",
      question: "Google Trends search interest for bitcoin",
      type: "not_in_academy",
      negative: true,
      expected_urls: [],
      acceptable_urls: [],
      answer_facts: []
    }
  ]
}
