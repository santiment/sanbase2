import * as actions from './../actions/types'

export const initialState = {
  isFeedbackModalOpened: false,
  isOnline: true,
  loginPending: false,
  loginSuccess: false,
  loginError: false,
  loginErrorMessage: ''
}

export default (state = initialState, action) => {
  switch (action.type) {
    case 'TOGGLE_FEEDBACK_MODAL':
      return {
        ...state,
        isFeedbackModalOpened: !state.isFeedbackModalOpened
      }
    case actions.APP_CHANGE_ONLINE_STATUS:
      return {
        ...state,
        isOnline: action.payload.isOnline
      }
    case actions.USER_LOGIN_PENDING:
      return {
        ...state,
        loginPending: true
      }
    case actions.USER_LOGIN_SUCCESS:
      return {
        ...state,
        loginPending: false,
        loginSuccess: true
      }
    case actions.USER_LOGIN_FAILED:
      return {
        ...state,
        loginPending: false,
        loginSuccess: false,
        loginError: true,
        loginErrorMessage: action.payload
      }
    default:
      return state
  }
}
