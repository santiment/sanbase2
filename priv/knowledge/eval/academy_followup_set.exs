# Follow-up questions for `Sanbase.Knowledge.AcademySearchEval.run_answers/1`.
#
# Each item is the second turn of an Academy Q&A chat: `history` holds the
# earlier turns and `question` only makes sense with them ("it", "them"). The
# fields are the same as in `academy_search_set.exs`; `answer_facts` are copied
# from the source md. Built on 2026-09-29.
url = &("https://academy.santiment.net" <> &1)

%{
  version: 1,
  items: [
    %{
      id: "followup-f1",
      type: "followup",
      negative: false,
      history: [
        %{role: "user", content: "What is the Gini index metric?"},
        %{
          role: "assistant",
          content:
            "The Gini index measures how evenly coins are distributed across addresses, from 0 (perfect equality) to 1 (perfect inequality) [1]."
        }
      ],
      question: "What is its metric name in the API and how often is it updated?",
      expected_urls: [url.("/metrics/gini-index/")],
      acceptable_urls: [],
      answer_facts: ["gini_index", "daily"]
    },
    %{
      id: "followup-f2",
      type: "followup",
      negative: false,
      history: [
        %{role: "user", content: "How do I create an API key?"},
        %{
          role: "assistant",
          content:
            "Log in to Sanbase, open Account Settings and generate a key in the API keys section [1]."
        }
      ],
      question: "Where do I paste it to use it in Google Sheets?",
      expected_urls: [url.("/sansheets/adding-an-api-key/")],
      acceptable_urls: [url.("/sansheets/setting-up/")],
      answer_facts: ["santiment data", "popup"]
    },
    %{
      id: "followup-f3",
      type: "followup",
      negative: false,
      history: [
        %{role: "user", content: "Does the Santiment API have rate limits?"},
        %{
          role: "assistant",
          content:
            "Yes, the API limits the number of calls per minute, per hour and per month depending on your plan [1]."
        }
      ],
      question: "What happens when I hit them?",
      expected_urls: [url.("/sanapi/rate-limits/")],
      acceptable_urls: [url.("/products-and-plans/sanapi-plans/")],
      answer_facts: ["429", "x ratelimit remaining"]
    },
    %{
      id: "followup-f4",
      type: "followup",
      negative: false,
      history: [
        %{role: "user", content: "What does the dead address label mean?"},
        %{
          role: "assistant",
          content:
            "It marks addresses that cannot be owned by anyone and are used for token burning, also known as cemetery addresses [1]."
        }
      ],
      question: "What is its label fqn?",
      expected_urls: [url.("/labels/dead-address/")],
      acceptable_urls: [url.("/labels/label-fqn/")],
      answer_facts: ["santiment dead address v1"]
    },
    %{
      id: "followup-f5",
      type: "followup",
      negative: false,
      history: [
        %{role: "user", content: "How do I set up a whale transaction alert in Sanbase?"},
        %{
          role: "assistant",
          content:
            "Open Alerts, choose the asset, select Whale Transactions from the On-Chain metrics and set your conditions [1]."
        }
      ],
      question: "What do I do after I set the conditions?",
      expected_urls: [url.("/education-and-use-cases/whale-activity-alert/")],
      acceptable_urls: [url.("/sanbase/alerts-page/")],
      answer_facts: ["notification", "create alert"]
    },
    %{
      id: "followup-f6",
      type: "followup",
      negative: true,
      history: [
        %{role: "user", content: "What is MVRV?"},
        %{
          role: "assistant",
          content: "MVRV is the ratio of market value to realized value [1]."
        }
      ],
      question: "Can I trade it as a futures contract on Santiment?",
      expected_urls: [],
      acceptable_urls: [],
      answer_facts: []
    }
  ]
}
