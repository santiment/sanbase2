import gql from 'graphql-tag'

export const insightsWidgetGQL = gql`
  query allInsights {
    allInsights {
      id
      createdAt
      title
      text
      votes {
        totalVotes
      }
      user {
        id
        username
      }
    }
  }
`
