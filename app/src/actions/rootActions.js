import { SHOW_NOTIFICATION } from './types'

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
