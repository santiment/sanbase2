import { SHOW_NOTIFICATION, APP_CHANGE_ONLINE_STATUS } from './types'

export const showNotification = (
  payload = { message: 'Empty message' }
) => {
  const newPayload = (typeof payload === 'string')
    ? { message: payload }
    : payload

  return {
    type: SHOW_NOTIFICATION,
    payload: {
      ...newPayload,
      key: new Date().getTime()
    }
  }
}

export const changeNetworkStatus = newtworkStatus => ({
  type: APP_CHANGE_ONLINE_STATUS,
  payload: {
    isOnline: newtworkStatus
  }
})
