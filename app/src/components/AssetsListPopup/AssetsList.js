import React from 'react'
import { connect } from 'react-redux'
import { compose, withState } from 'recompose'
import { Button, Label } from 'semantic-ui-react'
import AddNewAssetsListBtn from './AddNewAssetsListBtn'
import * as actions from './../../actions/types'

const ConfigurationListBtn = ({ isConfigOpened = false, setConfigOpened }) =>
  isConfigOpened ? (
    <Button onClick={() => setConfigOpened(!isConfigOpened)} icon='close' />
  ) : (
    <Button onClick={() => setConfigOpened(!isConfigOpened)} icon='setting' />
  )

// id is a number of current date for new list,
// until backend will have returned a real id
const isNewestList = id => typeof id === 'number'

class AssetsList extends React.Component {
  render () {
    const {
      lists = [],
      projectId,
      assetsListUI,
      addNewAssetList,
      isConfigOpened,
      setConfigOpened,
      removeAssetList,
      addAssetToList
    } = this.props
    return (
      <div>
        {lists.length > 0 && (
          <ConfigurationListBtn
            setConfigOpened={setConfigOpened}
            isConfigOpened={isConfigOpened}
          />
        )}
        {lists.length > 0 &&
          lists.map(({ id, name }) => (
            <div key={id} onClick={addAssetToList.bind(this, projectId, id)}>
              {name}
              {isConfigOpened &&
                !isNewestList(id) && (
                  <Button
                    onClick={removeAssetList.bind(this, id)}
                    icon='trash'
                  />
                )}
              {isNewestList(id) && (
                <Label color='green' horizontal>
                  NEW
                </Label>
              )}
            </div>
          ))}
        <AddNewAssetsListBtn
          assetsListUI={assetsListUI}
          addNewAssetList={addNewAssetList}
        />
      </div>
    )
  }
}

const mapStateToProps = state => {
  return {
    assetsListUI: state.assetsListUI
  }
}

const mapDispatchToProps = (dispatch, ownProps) => ({
  addAssetToList: (projectId, assetsListId) => {
    if (ownProps.isConfigOpened) return
    return dispatch({
      type: actions.USER_ADD_ASSET_TO_LIST,
      payload: { projectId, assetsListId }
    })
  },
  addNewAssetList: payload =>
    dispatch({
      type: actions.USER_ADD_NEW_ASSET_LIST,
      payload
    }),
  removeAssetList: id =>
    dispatch({
      type: actions.USER_REMOVE_ASSET_LIST,
      payload: { id }
    })
})

export default compose(
  connect(mapStateToProps, mapDispatchToProps),
  withState('isConfigOpened', 'setConfigOpened', false)
)(AssetsList)
