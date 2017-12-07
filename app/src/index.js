import React from 'react'
import ReactDOM from 'react-dom'
import { BrowserRouter as Router, Route } from 'react-router-dom'
import { Provider } from 'react-redux'
import { createStore, applyMiddleware } from 'redux'
import { composeWithDevTools } from 'redux-devtools-extension'
import axios from 'axios'
import { multiClientMiddleware } from 'redux-axios-middleware'
import ApolloClient from 'apollo-client'
import gql from 'graphql-tag'
import { createHttpLink } from 'apollo-link-http'
import { setContext } from 'apollo-link-context'
import { InMemoryCache } from 'apollo-cache-inmemory'
import { ApolloProvider } from 'react-apollo'
import App from './App'
import reducers from './reducers/rootReducers.js'
import { loadState, saveState } from './utils/localStorage'
import setAuthorizationToken from './utils/setAuthorizationToken'
import './index.css'

const httpLink = createHttpLink({ uri: 'http://localhost:4000/graphql' })

const authLink = setContext((_, { headers }) => {
  // get the authentication token from local storage if it exists
  const token = loadState() ? loadState().token : undefined
  // return the headers to the context so httpLink can read them
  return {
    headers: {
      ...headers,
      authorization: token ? `Bearer ${token}` : null
    }
  }
})

const client = new ApolloClient({
  link: authLink.concat(httpLink),
  cache: new InMemoryCache()
})

const clients = {
  sanbaseClient: {
    client: axios.create({
      baseURL: 'http://localhost:4000/api',
      responseType: 'json'
    })
  }
}

loadState() && setAuthorizationToken(loadState().token)

const middleware = [multiClientMiddleware(clients)]

const store = createStore(reducers,
  {user: loadState()} || {},
  composeWithDevTools(applyMiddleware(...middleware))
)

client.query({
  query: gql`
    query {
      currentUser {
        id,
        email,
        username,
        ethAccounts{
          address,
          sanBalance
        }
      }
    }
  `
})
.then(response => {
  store.dispatch({
    type: 'CHANGE_USER_DATA',
    user: response.data.currentUser
  })
})
.catch(error => console.error(error))

store.subscribe(() => {
  // TODO: Yura Zatsepin: 2017-12-07 11:23:
  // we need add throttle when save action was hapenned
  saveState(store.getState().user)
})

ReactDOM.render(
  <ApolloProvider client={client}>
    <Provider store={store}>
      <Router>
        <Route path='/' component={App} />
      </Router>
    </Provider>
  </ApolloProvider>,
  document.getElementById('root'))
