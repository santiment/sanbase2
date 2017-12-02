import React from 'react'
import ReactDOM from 'react-dom'
import { BrowserRouter as Router, Route } from 'react-router-dom'
import { Provider } from 'react-redux'
import { createStore, applyMiddleware } from 'redux'
import { composeWithDevTools } from 'redux-devtools-extension'
import App from './App'
import reducers from './reducers/rootReducers.js'
import registerServiceWorker from './registerServiceWorker'
import './index.css'

const middleware = []

const store = createStore(reducers,
  {},
  composeWithDevTools(applyMiddleware(...middleware))
)

ReactDOM.render(
  <Provider store={store}>
    <Router>
      <Route path='/' component={App} />
    </Router>
  </Provider>,
  document.getElementById('root'))
registerServiceWorker()
