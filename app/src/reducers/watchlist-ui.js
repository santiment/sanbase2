import * as actions from './../actions/types'

export const initialState = {
  selectedId: null,
  newItemPending: false,
  newItemFailed: false,
  newItemSuccess: false,
  statusDeleteAssetList: null,
  showConfirmDeleteModal: false
}

export default (state = initialState, action) => {
  switch (action.type) {
    case actions.USER_ADD_NEW_ASSET_LIST:
      return {
        ...state,
        newItemPending: true
      }
    case actions.USER_ADD_NEW_ASSET_LIST_SUCCESS:
      return {
        ...state,
        newItemSuccess: true,
        newItemFailed: false,
        newItemPending: false
      }
    case actions.USER_ADD_NEW_ASSET_LIST_FAILED:
      return {
        ...state,
        newItemFailed: true,
        newItemSuccess: false,
        newItemPending: false
      }
    case actions.USER_ADD_NEW_ASSET_LIST_CANCEL:
      return {
        ...initialState
      }
    case actions.USER_REMOVE_ASSET_LIST:
      return {
        ...state,
        statusDeleteAssetList: 'PENDING'
      }
    case actions.USER_REMOVE_ASSET_LIST_SUCCESS:
      return {
        ...state,
        statusDeleteAssetList: 'SUCCESS',
        showConfirmDeleteModal: false
      }
    case actions.USER_REMOVE_ASSET_LIST_FAILED:
      return {
        ...state,
        statusDeleteAssetList: 'FAILED'
      }
    case actions.USER_CHOOSE_ASSET_LIST:
      return {
        ...state,
        selectedId: action.payload.id
      }
    case actions.WATCHLIST_TOGGLE_CONFIRM_DELETE_MODAL:
      return {
        ...state,
        showConfirmDeleteModal: !state.showConfirmDeleteModal,
        statusDeleteAssetList: null,
        selectedId: !state.showConfirmDeleteModal ? action.payload.id : null
      }
    default:
      return state
  }
}
