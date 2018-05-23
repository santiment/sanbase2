export const initialState = {
  isOpenedLoginRequestModal: false
}

export default (state = initialState, action) => {
  switch (action.type) {
    case 'TOGGLE_LOGIN_REQUEST_MODAL':
      return {
        ...state,
        isOpenedLoginRequestModal: !state.isOpenedLoginRequestModal
      }
    default:
      return state
  }
}
