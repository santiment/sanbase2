export const initialState = {
  isLoading: true,
  pending: false,
  error: false,
  data: {},
  account: null,
  token: null,
  hasMetamask: false
}

export default (state = initialState, action) => {
  switch (action.type) {
    case 'INIT_WEB3_ACCOUNT':
      return {
        ...state,
        account: action.account
      }
    case 'CHECK_WEB3_PROVIDER':
      return {
        ...state,
        hasMetamask: action.hasMetamask
      }
    case 'APP_LOADING_SUCCESS':
      return {
        ...state,
        isLoading: false
      }
    case 'SUCCESS_LOGIN':
      return {
        ...state,
        pending: false,
        error: false,
        isLoading: false,
        token: action.token,
        data: {
          username: action.username
        }
      }
    case 'PENDING_LOGIN':
      return {
        ...state,
        pending: true,
        isLoading: false,
        error: false
      }
    case 'SUCCESS_LOGOUT':
      return {
        ...state,
        pending: false,
        error: false,
        isLoading: false,
        data: {},
        token: null
      }
    case 'FAILED_LOGIN':
      return {
        ...state,
        pending: false,
        error: true,
        isLoading: false,
        data: {},
        token: null,
        errorMessage: action.error
      }
    default:
      return state
  }
}
