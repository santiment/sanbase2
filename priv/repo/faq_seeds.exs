faqs = [
  %{
    question: "Do you use REST, GraphQL or something else?",
    answer: """
    Santiment API uses [GraphQL](https://graphql.org/) exclusively. For more information regarding the API, please visit [https://academy.santiment.net/for-developers/](https://academy.santiment.net/for-developers/)
    """
  },
  %{
    question: "Could you help me understand the difference between your plans?",
    answer: """
    Absolutely! As soon as you register on our platform and generate an API key, we provide you with our free plan.
    This grants you 1000 API calls per month and limited access to historical data, which is useful for beginners or
    those wanting to familiarize themselves with our API. For further access, our Basic plan includes most metrics,
    excluding the Advanced, and offers 300,000 API calls per month and 2 years of historical data.
    For unrestricted metrics and historical data access, our Pro plan grants you 600,000 API calls per month.
    """
  },
  %{
    question: "What is Rate Limiting?",
    answer: """
    Every subscription plan has a given number of allowed API calls per minute, per hour and per month.
    When that number of API calls is exceeded, you are being rate limited and can make another API call when
    the duration for the rate limiting is over.

    Example: If your subscription plan has a limit of 100 API calls per minute and you make 100 API calls,
    you will be able to make another API call when the minute is over. If you believe that the rate limits of
    the standard plans are not enough for your needs, please contact our sales team (link) and we will be happy to help.
    """
  },
  %{
    question: "When should I consider Tailored/Enterprise plan?",
    answer: """
    If the standard plans do not meet your needs - you need more API calls, you need some custom metric developed for you
    or have any other requirement that is not covered by our standard plans, please contact the sales team (link) and
    we will be happy to help.
    """
  },
  %{
    question: "How do I explore the API?",
    answer: """
    The main tool for exploring the API is to use the
    [GraphiQL visual tool](https://api.santiment.net/graphiql_advanced).

    More information on how to explore and understand the API can be found on the
    [Academy developer's page](https://academy.santiment.net/for-developers).

    For instructions on how to use the HTTP header containing your API key, please visit:
    [https://academy.santiment.net/sanapi/#authentication](https://academy.santiment.net/sanapi/#authentication)
    """
  },
  %{
    question: "Do you provide any libraries for API access?",
    answer: """
    We support and develop the [sanpy](https://github.com/santiment/sanpy) Python library.
    It provides easy access to our metrics, so you can get a Pandas DataFrame with our data
    with a single function call.

    If you believe you can contribute or want to create libraries in other popular languages,
    we would love to hear from you on our Discord server:
    [https://santiment.net/discord](https://santiment.net/discord)
    """
  },
  %{
    question: "What is considered an API call?",
    answer: """
    Every GraphQL query executed is counted as one API call.
    """
  },
  %{
    question: "What should I do if I exhaust my API calls?",
    answer: """
    If you've exhausted your API calls due to a coding issue, please connect with us on Discord:
    [https://santiment.net/discord](https://santiment.net/discord)

    We will review your situation and potentially reset your limits. However, if you constantly
    run out of API calls due to high data usage, reach out to us and we'll work together to
    determine the best custom solution for you.
    """
  },
  %{
    question: "Can I cancel my paid subscription anytime?",
    answer: """
    Definitely, you are free to cancel your subscription at any point during the month or year
    of your paid plan. Even after cancellation, you can continue to enjoy your pro benefits for
    the remainder of your billing period.
    """
  },
  %{
    question: "How long will my discount code work?",
    answer: """
    Most discount codes we offer are applicable for a single billing cycle, if not explicitly
    stated otherwise.
    """
  },
  %{
    question: "Is it possible to combine various discounts?",
    answer: """
    Unfortunately, it's impossible to combine multiple discounts.
    """
  },
  %{
    question: "Do you accept payments in cryptocurrency?",
    answer: """
    Yes, indeed! We accept payments in ETH, BTC, or any renowned Ethereum-based stablecoin.
    More options are available with our SAN token.

    Here's more information on crypto payments:
    [https://academy.santiment.net/products-and-plans/how-to-pay-with-crypto/](https://academy.santiment.net/products-and-plans/how-to-pay-with-crypto/)
    """
  },
  %{
    question: "Can I talk with one of your experts?",
    answer: """
    Absolutely! Request a demo and one of our product experts will guide you through the
    Sanbase platform and its various features:

    [https://calendly.com/santiment-team/sanapi-walkthrough](https://calendly.com/santiment-team/sanapi-walkthrough)
    """
  },
  %{
    question: "What if my question isn't listed here?",
    answer: """
    Our [Academy](https://academy.santiment.net/) is equipped to answer most of your initial
    queries. However, don't hesitate to contact us if you need any additional assistance.

    Simply click the chat icon in the bottom-right corner of your screen and you can chat with
    a team member instantly.

    Alternatively, you can connect with our team and community on Discord here:
    [https://santiment.net/discord](https://santiment.net/discord)

    Alternatively, you can email to [support@santiment.net](mailto:support@santiment.net)
    """
  },
  %{
    question: "Is there a graphical representation of the data?",
    answer: """
    Yes, you're welcome to check our web UI platform Sanbase:
    [https://app.santiment.net/](https://app.santiment.net/)
    """
  }
]

for faq <- faqs do
  try do
    Sanbase.Knowledge.Faq.create_entry(%{question: faq.question, answer_markdown: faq.answer})
  rescue
    _ -> :ok
  end
end
