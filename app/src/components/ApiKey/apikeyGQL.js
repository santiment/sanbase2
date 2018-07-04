import gql from 'graphql-tag'

export const generateApikeyGQL = gql`
  mutation {
    generateApikey {
      apikeys
    }
  }
`
