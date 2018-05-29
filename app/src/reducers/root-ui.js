export const initialState = {
  isFeedbackModalOpened: false,
  isOnline: true
}

export default (state = initialState, action) => {
  switch (action.type) {
    case 'TOGGLE_FEEDBACK_MODAL':
      return {
        ...state,
        isFeedbackModalOpened: !state.isFeedbackModalOpened
      }
    case 'APP_CHANGE_ONLINE_STATUS':
      return {
        ...state,
        isOnline: action.payload.isOnline
      }
    default:
      return state
  }
}
