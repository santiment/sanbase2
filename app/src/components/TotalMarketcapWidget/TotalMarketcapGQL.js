import gql from 'graphql-tag'

export const totalMarketcapGQL = gql`
  query historyPrice($from: DateTime!, $slug: String) {
    historyPrice(from: $from, slug: $slug, interval: "1d") {
      marketcap
      volume
      datetime
    }
  }
`

// Operation historyPrice is too complex: complexity is 273424 and maximum is 5000
export const constructTotalMarketcapGQL = (slugs, from) => {
  if (slugs.length === 0) slugs.push('TOTAL_MARKET')
  return gql`
  query historyPrice {
    ${slugs.reduce((acc, slug) => {
    return (
      acc +
        `
      _${slug.replace(
        /-/g,
        ''
      )}: historyPrice(from: "${from}", slug: "${slug}", interval: "1d") {
        marketcap
        volume
        datetime
      }
    `
    )
  }, ``)}
  }
`
}
