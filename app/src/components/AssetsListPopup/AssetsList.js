import React from 'react'
import { connect } from 'react-redux'
import { compose, withState } from 'recompose'
import { Button, Label } from 'semantic-ui-react'
import AddNewAssetsListBtn from './AddNewAssetsListBtn'
import * as actions from './../../actions/types'

const ConfigurationListBtn = ({ isConfigOpened = false, setConfigOpened }) => (
  <Button
    onClick={() => setConfigOpened(!isConfigOpened)}
    icon={isConfigOpened ? 'close' : 'setting'}
  />
)

// id is a number of current date for new list,
// until backend will have returned a real id
const isNewestList = id => typeof id === 'number'

export const hasAssetById = ({ id, listItems }) => {
  return listItems.some(item => item.project.id === id)
}

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
      toggleAssetInList
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
          lists.map(({ id, name, listItems = [] }) => (
            <div
              key={id}
              onClick={toggleAssetInList.bind(this, projectId, id, listItems)}
            >
              {name}
              {hasAssetById({
                listItems,
                id: projectId
              }) && 'Yes'}
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
  toggleAssetInList: (projectId, assetsListId, listItems) => {
    if (ownProps.isConfigOpened) return
    const isAssetInList = hasAssetById({
      listItems: ownProps.lists.find(list => list.id === assetsListId)
        .listItems,
      id: projectId
    })
    if (isAssetInList) {
      return dispatch({
        type: actions.USER_REMOVE_ASSET_FROM_LIST,
        payload: { projectId, assetsListId, listItems }
      })
    } else {
      return dispatch({
        type: actions.USER_ADD_ASSET_TO_LIST,
        payload: { projectId, assetsListId, listItems }
      })
    }
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
  withState('isConfigOpened', 'setConfigOpened', false),
  connect(mapStateToProps, mapDispatchToProps)
)(AssetsList)
