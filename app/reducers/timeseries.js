import * as actions from './../actions/types'

export const initialState = {}

export default (state = initialState, action) => {
  switch (action.type) {
    case actions.TIMESERIES_FETCH:
      return {
        ...state,
        isLoading: true,
        isError: false
      }
    case actions.TIMESERIES_FETCH_SUCCESS:
      return {
        ...state,
        ...action.payload
      }
    default:
      return state
  }
}
