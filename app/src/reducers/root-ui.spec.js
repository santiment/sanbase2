import reducers from './rootReducers'
import * as actions from './../actions/types'

describe('root-ui reducer', () => {
  test('GDPR should be opened', () => {
    const action = { type: actions.APP_SHOW_GDPR_MODAL }
    const prevState = {
      user: {
        isLoading: false,
        error: false,
        token: 'asdfjadsf'
      },
      rootUi: {
        isGDPRModalOpened: false
      }
    }

    const state = reducers(prevState, action)
    expect(state.rootUi.isGDPRModalOpened).toEqual(true)
  })
  test('GDPR should close, if the user is logged off', () => {
    const action = { type: actions.APP_USER_HAS_INACTIVE_TOKEN }
    const prevState = {
      user: {
        isLoading: false,
        error: false,
        token: 'asdfjadsf'
      },
      rootUi: {
        isGDPRModalOpened: true
      }
    }

    const state = reducers(prevState, action)
    expect(state.rootUi.isGDPRModalOpened).toEqual(false)
    expect(state.user.token).toEqual(null)
  })
})
