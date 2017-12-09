import { SHOW_NOTIFICATION } from './../actions/types.js'

export const initialState = {
  notification: null
}

const defaultNotificationState = {
  key: 'any UID',
  message: `Notification ipsum...`,
  dismissAfter: 4000
}

export default (state = initialState, action) => {
  switch (action.type) {
    case SHOW_NOTIFICATION:
      return {
        ...defaultNotificationState,
        ...action.payload
      }
    default:
      return state
  }
}
