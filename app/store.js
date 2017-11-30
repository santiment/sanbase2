import { composeWithDevTools } from 'redux-devtools-extension'
import thunkMiddleware from 'redux-thunk'
import { createStore, applyMiddleware } from 'redux'
import reducers, { initialState } from 'reducers'

const makeStore = (state = initialState) => {
  const middlewares = [thunkMiddleware]
  return createStore(reducers,
    state,
    composeWithDevTools(applyMiddleware(...middlewares))
  )
}

export default makeStore
