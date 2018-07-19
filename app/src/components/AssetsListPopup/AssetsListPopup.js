import React from 'react'
import { connect } from 'react-redux'
import { graphql } from 'react-apollo'
import { compose, withState } from 'recompose'
import { Popup, Button, Label } from 'semantic-ui-react'
import { AssetsListGQL } from './AssetsListGQL'
import AddNewAssetsListBtn from './AddNewAssetsListBtn'
import * as actions from './../../actions/types'

const POLLING_INTERVAL = 2000

const AddToListBtn = (
  <Button basic color='purple'>
    add to list
  </Button>
)

const ConfigurationListBtn = ({ isConfigOpened = false, setConfigOpened }) =>
  isConfigOpened ? (
    <Button onClick={() => setConfigOpened(!isConfigOpened)} icon='close' />
  ) : (
    <Button onClick={() => setConfigOpened(!isConfigOpened)} icon='setting' />
  )

const isNewestList = id => typeof id === 'number'

const Lists = withState('isConfigOpened', 'setConfigOpened', false)(
  ({
    lists = [],
    assetsListUI,
    addNewAssetList,
    isConfigOpened,
    setConfigOpened,
    removeAssetList
  }) => (
    <div>
      {lists.length > 0 && (
        <ConfigurationListBtn
          setConfigOpened={setConfigOpened}
          isConfigOpened={isConfigOpened}
        />
      )}
      {lists.length > 0 &&
        lists.map(({ id, name }) => (
          <div key={id}>
            {name}
            {isConfigOpened &&
              !isNewestList(id) && (
                <Button onClick={() => removeAssetList(id)} icon='trash' />
              )}
            {
              // id is a number of current date for new list,
              // until backend will have returned a real id
            }
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
)

const AssetsListPopup = ({
  isLoggedIn,
  lists,
  assetsListUI,
  addNewAssetList,
  removeAssetList,
  trigger = AddToListBtn
}) => {
  return (
    <Popup
      content={
        <Lists
          assetsListUI={assetsListUI}
          addNewAssetList={addNewAssetList}
          removeAssetList={removeAssetList}
          lists={lists}
        />
      }
      trigger={trigger}
      position='bottom center'
      on='click'
    />
  )
}

const mapStateToProps = state => {
  return {
    assetsListUI: state.assetsListUI
  }
}

const mapDispatchToProps = dispatch => ({
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
  graphql(AssetsListGQL, {
    name: 'AssetsList',
    options: ({ isLoggedIn }) => ({
      skip: !isLoggedIn,
      pollInterval: POLLING_INTERVAL
    }),
    props: ({ AssetsList, ownProps }) => {
      const { fetchUserLists = [] } = AssetsList
      return {
        lists: fetchUserLists
      }
    }
  })
)(AssetsListPopup)
