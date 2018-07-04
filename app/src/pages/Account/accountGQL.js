import gql from 'graphql-tag'

export const changeEmailGQL = gql`
  mutation changeEmail($email: String!) {
    changeEmail(email: $email) {
      email
    }
  }
`

export const changeUsernameGQL = gql`
  mutation changeUsername($username: String!) {
    changeUsername(username: $username) {
      username
    }
  }
`
