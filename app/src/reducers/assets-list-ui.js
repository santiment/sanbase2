import * as actions from './../actions/types'

export const initialState = {
  selectedId: null,
  assetsListNewItemPending: false,
  assetsListNewItemFailed: false,
  assetsListNewItemSuccess: false
}

export default (state = initialState, action) => {
  switch (action.type) {
    case actions.USER_ADD_NEW_ASSET_LIST:
      return {
        ...state,
        assetsListNewItemPending: true
      }
    case actions.USER_ADD_NEW_ASSET_LIST_SUCCESS:
      return {
        ...state,
        assetsListNewItemSuccess: true,
        assetsListNewItemFailed: false,
        assetsListNewItemPending: false
      }
    case actions.USER_ADD_NEW_ASSET_LIST_FAILED:
      return {
        ...state,
        assetsListNewItemFailed: true,
        assetsListNewItemSuccess: false,
        assetsListNewItemPending: false
      }
    case actions.USER_ADD_NEW_ASSET_LIST_CANCEL:
      return {
        ...initialState
      }
    case actions.USER_CHOOSE_ASSET_LIST:
      return {
        ...state,
        selectedId: action.payload.id
      }
    default:
      return state
  }
}
