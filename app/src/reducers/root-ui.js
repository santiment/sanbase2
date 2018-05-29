export const initialState = {
  isFeedbackModalOpened: false
}

export default (state = initialState, action) => {
  switch (action.type) {
    case 'TOGGLE_FEEDBACK_MODAL':
      return {
        ...state,
        isFeedbackModalOpened: !state.isFeedbackModalOpened
      }
    default:
      return state
  }
}
