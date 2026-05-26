# Golden question set for `mix knowledge_eval`.
#
# Each item is one user question that we expect retrieval to handle well.
# Fill in the `expected` fields with at least one of:
#   - faq_ids: list of FaqEntry binary_id (uuid string) values
#   - academy_paths: list of github_path values (e.g. "src/docs/sanapi/api-key.md")
#   - insight_post_ids: list of Post id integers
#
# Items with no `expected` ids skip hit-rate scoring for that source but
# still contribute to mean top-1 similarity. Use them to track drift on
# questions where you only care about a non-zero best-match score.
#
# Tags are free-form labels for slicing future per-tag reports.
#
# FAQ items below were derived from the live FAQ table on 2026-05-26.
# Questions are intentionally PARAPHRASED — not verbatim — so the eval
# measures real retrieval quality, not embedding self-similarity.

%{
  version: 1,
  items: [
    # === API: keys, exploration, libraries, transport ===
    %{
      id: "faq-api-key-where",
      question: "Where do I get my Santiment API key?",
      expected: %{faq_ids: ["7a5e4e22-232e-45cf-8aa4-f9a58700d3e5"]},
      tags: ["api", "onboarding"]
    },
    %{
      id: "faq-api-explore",
      question: "How can I try out the Santiment API and see what's available?",
      expected: %{faq_ids: ["e04621dd-84db-42a9-9214-89ab5224f127"]},
      tags: ["api", "onboarding"]
    },
    %{
      id: "faq-api-libraries",
      question: "Is there a Python or JS client library for your API?",
      expected: %{faq_ids: ["15b4f0f5-fe56-470a-bfd7-9b689aca14df"]},
      tags: ["api", "sanpy"]
    },
    %{
      id: "faq-api-transport",
      question: "Is your API REST or GraphQL?",
      expected: %{faq_ids: ["451e38e0-38d1-4eba-b48a-d0ef04c82bbd"]},
      tags: ["api"]
    },
    %{
      id: "faq-api-websockets",
      question: "Can I stream realtime data over websockets?",
      expected: %{faq_ids: ["493adfac-bd37-4b4d-89b4-51c4aa8177b8"]},
      tags: ["api", "realtime"]
    },
    %{
      id: "faq-api-assets-list",
      question: "How do I list all assets exposed by the GraphQL API?",
      expected: %{faq_ids: ["8d342865-4385-470d-8bfe-8bdc3d0122d8"]},
      tags: ["api", "graphql", "assets"]
    },
    %{
      id: "faq-api-metrics-list",
      question: "How do I list all metrics available in the GraphQL API?",
      expected: %{faq_ids: ["22694518-df23-413a-8105-7e028fdd80c7"]},
      tags: ["api", "graphql", "metrics"]
    },
    %{
      id: "faq-api-call-definition",
      question: "What counts as one API call for billing/limits?",
      expected: %{faq_ids: ["add86c49-d4ff-4696-a89c-2ac40eac69a1"]},
      tags: ["api", "billing", "rate-limit"]
    },
    %{
      id: "faq-api-rate-limit",
      question: "What rate limits apply to the API?",
      expected: %{faq_ids: ["e6f82dc8-fc6c-4357-b506-41ee46c5e15c"]},
      tags: ["api", "rate-limit"]
    },
    %{
      id: "faq-api-exhausted",
      question: "I hit my API call quota — now what?",
      expected: %{faq_ids: ["e2a89190-4cfe-4c3a-9510-1a141149f4b6"]},
      tags: ["api", "rate-limit"]
    },
    %{
      id: "faq-api-not-working",
      question: "The API isn't responding / returning errors — how do I debug?",
      expected: %{faq_ids: ["44c68d2d-7d8e-4f75-9e1d-6aa3e337a95b"]},
      tags: ["api", "troubleshooting"]
    },
    %{
      id: "faq-api-subscription-not-recognized",
      question: "I'm subscribed but the API says I'm on the free plan.",
      expected: %{faq_ids: ["db879f6b-c621-47b2-8731-084a407323dd"]},
      tags: ["api", "subscription", "troubleshooting"]
    },
    %{
      id: "faq-api-historical-upgrade",
      question: "Can I pay more to unlock full historical data through the API?",
      expected: %{faq_ids: ["08169e18-b5b9-4b76-9d35-ede0567cfbac"]},
      tags: ["api", "subscription", "historical"]
    },
    %{
      id: "faq-api-realtime-vs-historical",
      question: "What's the difference between real-time and historical access?",
      expected: %{faq_ids: ["5f8b4452-0077-4b72-ad0e-cb6dfa227ea6"]},
      tags: ["api", "realtime", "historical"]
    },
    %{
      id: "faq-api-daily-missing-today",
      question: "Today's daily metric value is missing from the API — why?",
      expected: %{faq_ids: ["4afe56b8-a49f-4e66-a457-2acbf4af104f"]},
      tags: ["api", "metrics", "troubleshooting"]
    },
    %{
      id: "faq-api-multi-seat",
      question: "On a Business plan, do all team members share API access?",
      expected: %{faq_ids: ["1e6c9a53-efef-4719-ae39-f1e57879452b"]},
      tags: ["api", "subscription", "team"]
    },
    %{
      id: "faq-sanpy-owner-label",
      question: "In sanpy, how do I pass owner and label to a metric?",
      expected: %{faq_ids: ["7190ad00-42ce-4c99-8e9b-b988eb03188c"]},
      tags: ["api", "sanpy", "code"]
    },
    %{
      id: "faq-sanmax-api-recent",
      question: "Does Sanbase Max give me the latest data via API too?",
      expected: %{faq_ids: ["5849b71b-2e6a-4e77-b91a-1c7a6d520980"]},
      tags: ["api", "subscription", "sanmax"]
    },

    # === Subscriptions, billing, trials, refunds ===
    %{
      id: "faq-plans-compare",
      question: "What are the differences between Sanbase plans?",
      expected: %{faq_ids: ["11b2433a-82de-4c4d-bcee-24b6f3caa032"]},
      tags: ["subscription", "plans"]
    },
    %{
      id: "faq-enterprise-when",
      question: "When does it make sense to move to the Enterprise plan?",
      expected: %{faq_ids: ["b01cfe3e-ecc1-4b06-953d-aa91931628e1"]},
      tags: ["subscription", "enterprise"]
    },
    %{
      id: "faq-pro-historical",
      question: "Does Sanbase Pro include full historical data?",
      expected: %{faq_ids: ["5106ae07-554c-42ed-b263-ee44463963ec"]},
      tags: ["subscription", "pro", "historical"]
    },
    %{
      id: "faq-sanmax-what",
      question: "What does the Sanbase Max plan include?",
      expected: %{faq_ids: ["2eab4fc6-a499-4041-8a30-d55823955a33"]},
      tags: ["subscription", "sanmax"]
    },
    %{
      id: "faq-sanmax-trial",
      question: "How do I start a free trial of Sanbase Max?",
      expected: %{faq_ids: ["99730899-d88b-4495-a66e-1612eedc65c0"]},
      tags: ["subscription", "sanmax", "trial"]
    },
    %{
      id: "faq-free-trial-generic",
      question: "Can I try Santiment for free before paying?",
      expected: %{faq_ids: ["d654ed2e-01c7-42dc-ad8e-f08ef74948dd"]},
      tags: ["subscription", "trial"]
    },
    %{
      id: "faq-trial-auto-renew",
      question: "Will my card be charged automatically when the 14-day trial ends?",
      expected: %{faq_ids: ["7081e057-7db1-4ef9-942c-e5971416ef3c"]},
      tags: ["subscription", "trial", "billing"]
    },
    %{
      id: "faq-trial-cancel-keep-access",
      question: "If I cancel during the trial, do I keep access until day 14?",
      expected: %{faq_ids: ["fda2a882-150f-41cd-a73a-6a62b47ddcc7"]},
      tags: ["subscription", "trial", "cancel"]
    },
    %{
      id: "faq-cancel-how",
      question: "How do I cancel my paid subscription?",
      expected: %{faq_ids: ["81825cb9-e07a-413e-b788-70edd9e25fe2"]},
      tags: ["subscription", "cancel"]
    },
    %{
      id: "faq-cancel-process",
      question: "What's the exact process to cancel — dashboard or support?",
      expected: %{faq_ids: ["49497355-7c3e-4e58-aea4-e7e88b7857a6"]},
      tags: ["subscription", "cancel"]
    },
    %{
      id: "faq-downgrade-free",
      question: "How do I switch back to the free plan?",
      expected: %{faq_ids: ["7e507999-94fa-4552-9fb4-a8f8a7ff5c48"]},
      tags: ["subscription", "downgrade"]
    },
    %{
      id: "faq-refund-policy",
      question: "What's your refund policy?",
      expected: %{faq_ids: ["5661aa7e-54d5-40a7-ac56-d8ff140f0587"]},
      tags: ["subscription", "refund"]
    },
    %{
      id: "faq-refund-forgot-cancel",
      question: "I forgot to cancel the trial and got charged — can I get my money back?",
      expected: %{faq_ids: ["0532b553-f28e-4db9-9b8f-9ce9a47a1147"]},
      tags: ["subscription", "refund", "trial"]
    },
    %{
      id: "faq-payment-methods",
      question: "Which payment methods do you accept for subscriptions?",
      expected: %{faq_ids: ["df5ea850-bbaa-4bc9-a350-66b3b0bbfeb7"]},
      tags: ["billing", "payment"]
    },
    %{
      id: "faq-payment-crypto",
      question: "Can I pay with crypto instead of a credit card?",
      expected: %{faq_ids: ["33c69a59-171c-40e3-bb5a-55d69d79e0dc"]},
      tags: ["billing", "payment", "crypto"]
    },
    %{
      id: "faq-payment-failed",
      question: "My subscription payment didn't go through — what should I do?",
      expected: %{faq_ids: ["02237fb6-4d8f-4675-935d-924d1d270b2e"]},
      tags: ["billing", "troubleshooting"]
    },
    %{
      id: "faq-billing-details-update",
      question: "How can I edit the company name and address on my invoice?",
      expected: %{faq_ids: ["b718ac91-c7a6-4a22-87f6-fbaa8afc4e9b"]},
      tags: ["billing", "invoice"]
    },
    %{
      id: "faq-api-allowance-per-plan",
      question: "How many API calls per month does each plan give me?",
      expected: %{faq_ids: ["d937c65f-8e54-45e0-8d6f-5179b1b18691"]},
      tags: ["api", "subscription", "billing"]
    },

    # === Discounts ===
    %{
      id: "faq-san-holder-discount",
      question: "How do I claim the 20% discount for holding 1000+ SAN tokens?",
      expected: %{faq_ids: ["47399594-b3a5-4c82-984b-692ea14898e4"]},
      tags: ["discount", "san"]
    },
    %{
      id: "faq-discount-duration",
      question: "How long is my discount code valid?",
      expected: %{faq_ids: ["badc5a57-feff-46f3-b198-262de6fc49a5"]},
      tags: ["discount"]
    },
    %{
      id: "faq-discount-stacking",
      question: "Can I stack two discount codes on the same subscription?",
      expected: %{faq_ids: ["20361585-d4d8-4c8a-86ee-95420b84a865"]},
      tags: ["discount"]
    },

    # === Account, login, 2FA, mobile ===
    %{
      id: "faq-change-email",
      question: "How do I change the email address tied to my Sanbase account?",
      expected: %{faq_ids: ["d55bd735-ea0c-4885-9a7c-4e7a00dd17c0"]},
      tags: ["account"]
    },
    %{
      id: "faq-2fa-support",
      question: "Do you support two-factor authentication?",
      expected: %{faq_ids: ["795108c4-8ffe-4c8f-a01a-d1a6ad49e8ff"]},
      tags: ["account", "security"]
    },
    %{
      id: "faq-username-login",
      question: "Can I sign in with a username and password instead of a wallet?",
      expected: %{faq_ids: ["56fe2e6d-d636-4529-a5f3-d5a3ba980061"]},
      tags: ["account", "login"]
    },
    %{
      id: "faq-mobile-parity",
      question: "Does the mobile app have all the features of the web Sanbase?",
      expected: %{faq_ids: ["ef850fcf-0153-448b-98e6-f0f0e3760966"]},
      tags: ["mobile"]
    },

    # === Metrics / on-chain ===
    %{
      id: "faq-find-metric",
      question: "I want to check if Santiment tracks a specific metric — how do I look it up?",
      expected: %{faq_ids: ["eb19bf77-5769-4372-b447-3120cf3d6673"]},
      tags: ["metrics", "discovery"]
    },
    %{
      id: "faq-metrics-overview",
      question: "What kinds of metrics does Santiment offer?",
      expected: %{faq_ids: ["6b42e743-6253-4256-b5f6-309bb38fb161"]},
      tags: ["metrics"]
    },
    %{
      id: "faq-chains-tokens-list",
      question: "Where can I see all chains and tokens Santiment supports?",
      expected: %{faq_ids: ["be9e114a-9999-4902-b89d-73cd66d17ce6"]},
      tags: ["assets", "discovery"]
    },
    %{
      id: "faq-age-destroyed-vs-consumed",
      question: "Age Destroyed vs Age Consumed — what's the distinction?",
      expected: %{faq_ids: ["2b8bea9c-ff30-47b4-a397-c9414c5d7bfd"]},
      tags: ["metrics", "on-chain"]
    },
    %{
      id: "faq-whale-accumulation",
      question: "Which metric shows whales accumulating a coin?",
      expected: %{faq_ids: ["7cebbf51-ec05-4261-a012-c551f3f07943"]},
      tags: ["metrics", "on-chain", "whales"]
    },
    %{
      id: "faq-social-dominance-use",
      question: "How can I use Social Dominance for trading decisions?",
      expected: %{faq_ids: ["280276d2-75f8-4b45-913d-9517ba1ee54c"]},
      tags: ["metrics", "social"]
    },
    %{
      id: "faq-supply-distribution",
      question: "What is the Supply Distribution metric and where is it documented?",
      expected: %{faq_ids: ["b00238e1-8ee5-427e-a730-a21683a03e43"]},
      tags: ["metrics", "on-chain"]
    },
    %{
      id: "faq-asset-prefix",
      question: "Why do some assets have a prefix like a- or o- in front of the symbol?",
      expected: %{faq_ids: ["e278b30d-0720-4e68-b32a-1c8bc3724933"]},
      tags: ["assets", "naming"]
    },
    %{
      id: "faq-dev-activity-bulk",
      question: "What's the efficient way to pull dev activity for many projects at once?",
      expected: %{faq_ids: ["2018fb2b-9a2f-4290-9fb0-cbc21883ef0e"]},
      tags: ["api", "metrics", "dev-activity"]
    },
    %{
      id: "faq-liquidations",
      question: "Do you have liquidation data?",
      expected: %{faq_ids: ["2829f3b2-3126-4156-a6d6-a6e852da2701"]},
      tags: ["metrics", "derivatives"]
    },
    %{
      id: "faq-liquidity-requirements",
      question: "How does Santiment validate liquidity provider thresholds?",
      expected: %{faq_ids: ["21669013-a630-404b-a3e9-47ade48bd607"]},
      tags: ["liquidity"]
    },

    # === Data export, charting, alerts ===
    %{
      id: "faq-csv-export",
      question: "Can I export historical data as a CSV file?",
      expected: %{faq_ids: ["f8f7205b-0cc6-439b-ab0b-901c62e0bdeb"]},
      tags: ["export", "csv"]
    },
    %{
      id: "faq-charts",
      question: "Is there a way to visualize the data as charts?",
      expected: %{faq_ids: ["168a3242-ceb0-41fb-939d-04b90a1b0006"]},
      tags: ["charts", "ui"]
    },
    %{
      id: "faq-telegram-group-alert",
      question: "Can a Telegram alert post to a group chat instead of a single user?",
      expected: %{faq_ids: ["66f73fd8-0fa4-4bfd-bdeb-2663b374639b"]},
      tags: ["alerts", "telegram"]
    },

    # === Support, contact, getting started ===
    %{
      id: "faq-get-started",
      question: "I'm brand new — how do I start using Sanbase?",
      expected: %{faq_ids: ["060ef277-876e-402c-8dfc-cb7de4de9a94"]},
      tags: ["onboarding"]
    },
    %{
      id: "faq-talk-to-expert",
      question: "Can I book a call with one of your analysts?",
      expected: %{faq_ids: ["41881b86-5edd-4af8-8596-068461b29973"]},
      tags: ["support", "expert"]
    },
    %{
      id: "faq-support-channels",
      question: "How do I contact Santiment support?",
      expected: %{faq_ids: ["debe1495-9bdb-4edd-bb67-8fdde1c89f8a"]},
      tags: ["support"]
    },
    %{
      id: "faq-question-not-here",
      question: "My question isn't covered in the FAQ — where do I go?",
      expected: %{faq_ids: ["a3dca486-cd64-42db-b9e5-53ff01af5a50"]},
      tags: ["support"]
    },
    %{
      id: "faq-bug-bounty",
      question: "Do you run a bug bounty program?",
      expected: %{faq_ids: ["a00bc9cd-e275-40cd-bc43-30ec3d4d593e"]},
      tags: ["security", "bug-bounty"]
    },
    %{
      id: "faq-intel-network",
      question: "What's the Santiment Intelligence Network?",
      expected: %{faq_ids: ["cee5f876-8cd1-4efe-85e4-103b315e6db1"]},
      tags: ["product"]
    },

    # === Should-not-answer sentinels (track no-info fallback / drift) ===
    %{
      id: "off-topic-football",
      question: "Who won the football world cup in 1990?",
      expected: %{faq_ids: []},
      tags: ["should-not-answer"]
    },
    %{
      id: "off-topic-weather",
      question: "What's the weather in Tokyo tomorrow?",
      expected: %{faq_ids: []},
      tags: ["should-not-answer"]
    }
  ]
}
