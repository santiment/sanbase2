import React, { Fragment } from 'react'
import { Button, Modal } from 'semantic-ui-react'
import { compose, withProps } from 'recompose'
import { connect } from 'react-redux'
import * as actions from './../../actions/types'

const ConfirmDeleteWatchlistModal = ({
  id,
  removeAssetList,
  toggleCofirmModal,
  showConfirmDeleteModal,
  isSuccess,
  isFailed,
  isPending
}) => {
  if (!showConfirmDeleteModal || !id) return ''
  return (
    <Modal
      defaultOpen
      dimmer={'blurring'}
      onClose={toggleCofirmModal}
      closeIcon
    >
      {isSuccess ? (
        <Modal.Content>
          <p>Watchlist was deleted.</p>
        </Modal.Content>
      ) : (
        <Fragment>
          <Modal.Content>
            <p>Do you want to delete this watchlist?</p>
          </Modal.Content>
          <Modal.Actions>
            <Button basic onClick={toggleCofirmModal}>
              Cancel
            </Button>
            <Button color='orange' onClick={removeAssetList.bind(this, id)}>
              {isPending ? 'Waiting...' : 'Delete'}
            </Button>
          </Modal.Actions>
        </Fragment>
      )}
    </Modal>
  )
}

const mapStateToProps = state => {
  return {
    statusDeleteAssetList: state.watchlistUi.statusDeleteAssetList,
    showConfirmDeleteModal: state.watchlistUi.showConfirmDeleteModal,
    id: state.watchlistUi.selectedId
  }
}

const mapDispatchToProps = dispatch => ({
  removeAssetList: id =>
    dispatch({
      type: actions.USER_REMOVE_ASSET_LIST,
      payload: { id }
    }),
  toggleCofirmModal: () =>
    dispatch({
      type: actions.WATCHLIST_TOGGLE_CONFIRM_DELETE_MODAL
    })
})

const enhance = compose(
  connect(
    mapStateToProps,
    mapDispatchToProps
  ),
  withProps(props => {
    return {
      isSuccess: props.statusDeleteAssetList === 'SUCCESS',
      isFailed: props.statusDeleteAssetList === 'FAILED',
      isPending: props.statusDeleteAssetList === 'PENDING'
    }
  })
)

export default enhance(ConfirmDeleteWatchlistModal)
