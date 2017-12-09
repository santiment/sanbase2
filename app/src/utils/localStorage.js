export const loadState = () => {
  try {
    const serializedState = window.localStorage.getItem('user')
    if (serializedState === null) {
      return undefined
    }
    return JSON.parse(serializedState)
  } catch (error) {
    return undefined
  }
}

export const saveState = (state) => {
  try {
    const serializedState = JSON.stringify(state)
    window.localStorage.setItem('user', serializedState)
  } catch (error) {
    // Ignore write errors.
  }
}
