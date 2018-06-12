export const getBalance = state => {
  return state.user.data.sanBalance > 0
    ? state.user.data.sanBalance : 0
}

export const checkHasPremium = state => {
  return state.user.data.sanBalance >= 1000
}

export const checkIsLoggedIn = state => {
  return !!state.user.token
}
