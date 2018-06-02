import { setContext } from 'apollo-link-context'
import { loadState } from './../utils/localStorage'

const AuthLink = setContext((_, { headers }) => {
  // get the authentication token from local storage if it exists
  const token = loadState() ? loadState().token : undefined
  return {
    headers: {
      ...headers,
      authorization: token ? `Bearer ${token}` : null
    }
  }
})

export default AuthLink
