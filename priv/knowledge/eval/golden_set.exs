# Golden question set for `mix knowledge.eval`.
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

%{
  version: 1,
  items: [
    %{
      id: "api-key-onboarding",
      question: "How do I get a Santiment API key?",
      expected: %{
        faq_ids: [],
        academy_paths: [],
        insight_post_ids: []
      },
      tags: ["api", "onboarding"]
    },
    %{
      id: "sanpy-install",
      question: "How do I install the sanpy Python library?",
      expected: %{
        academy_paths: ["sanpy/README.md"]
      },
      tags: ["api", "sanpy", "code"]
    },
    %{
      id: "subscription-cancel",
      question: "How do I cancel my Sanbase subscription?",
      expected: %{
        faq_ids: [],
        academy_paths: []
      },
      tags: ["subscription", "payment"]
    },
    %{
      id: "off-topic-football",
      question: "Who won the football world cup in 1990?",
      expected: %{
        faq_ids: [],
        academy_paths: [],
        insight_post_ids: []
      },
      tags: ["should-not-answer"]
    }
  ]
}
