import gql from 'graphql-tag'

export const generateApikeyGQL = gql`
  mutation {
    generateApikey {
      apikeys
    }
  }
`
export const revokeApikeyGQL = gql`
  mutation revokeApikey($apikey: String!) {
    revokeApikey(apikey: $apikey) {
      apikeys
    }
  }
`
