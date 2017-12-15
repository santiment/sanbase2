export const initialState = {
  isLoading: true,
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
        error: false,
        isLoading: false,
        token: action.token,
        data: {
          ...action.user
        }
      }
    case 'SUCCESS_LOGOUT':
      return {
        ...state,
        error: false,
        isLoading: false,
        data: {},
        token: null
      }
    case 'FAILED_LOGIN':
      return {
        ...state,
        error: true,
        isLoading: false,
        data: {},
        token: null,
        errorMessage: action.error
      }
    case 'CHANGE_USER_DATA':
      return {
        ...state,
        data: {
          ...action.user
        }
      }
    default:
      return state
  }
}
