import gql from 'graphql-tag'

export const allInsightsPublicGQL = gql`
  query allInsights {
    allInsights {
      id
      title
      createdAt
      state
      totalSanVotes
      user {
        id
        username
      }
    }
  }
`

export const allInsightsGQL = gql`
  query allInsights {
    allInsights {
      id
      title
      createdAt
      state
      totalSanVotes
      moderationComment
      votedAt
      user {
        id
        username
      }
    }
  }
`

export default allInsightsPublicGQL
