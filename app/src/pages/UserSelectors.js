export const getBalance = state => {
  const ethAccounts = state.user.data.ethAccounts
  if (ethAccounts) {
    return state.user.data.ethAccounts.length > 0
      ? state.user.data.ethAccounts[0].sanBalance
      : 0
  }
  return 0
}

export const checkHasPremium = state => {
  const ethAccounts = state.user.data.ethAccounts
  if (ethAccounts) {
    return state.user.data.ethAccounts.length > 0
      ? state.user.data.ethAccounts[0].sanBalance >= 1000
      : false
  }
  return false
}

export const checkIsLoggedIn = state => {
  return !!state.user.token
}
