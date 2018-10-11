import gql from 'graphql-tag'

export const allInsightsPublicGQL = gql`
  query allInsightsPublic {
    allInsights {
      id
      title
      createdAt
      state
      votes {
        totalSanVotes
        totalVotes
      }
      tags {
        name
      }
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
      updatedAt
      votedAt
      state
      tags {
        name
      }
      votes {
        totalSanVotes
        totalVotes
      }
      moderationComment
      discourseTopicUrl
      readyState
      votedAt
      user {
        id
        username
      }
    }
  }
`

export default allInsightsPublicGQL
