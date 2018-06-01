export const getBalance = state => {
  return state.user.data.sanBalance
}

export const checkHasPremium = state => {
  return state.user.data.sanBalance >= 1000
}

export const checkIsLoggedIn = state => {
  return !!state.user.token
}
