import React from 'react'
import { connect } from 'react-redux'
import { graphql } from 'react-apollo'
import { compose } from 'recompose'
import { Popup, Button } from 'semantic-ui-react'
import { AssetsListGQL } from './AssetsListGQL'
import AddNewAssetsListBtn from './AddNewAssetsListBtn'
import * as actions from './../../actions/types'

const AddToListBtn = <Button basic color='purple'>add to list</Button>

const Lists = ({
  lists,
  assetsListUI,
  addNewAssetList
}) => (
  <div>
    {lists && lists.map(({id, name}) => (
      <div key={id}>
        {name}

      </div>
    ))}
    <AddNewAssetsListBtn
      assetsListUI={assetsListUI}
      addNewAssetList={addNewAssetList} />
  </div>
)

const AssetsListPopup = ({
  isLoggedIn,
  lists,
  assetsListUI,
  addNewAssetList,
  trigger = AddToListBtn }) => {
  return (
    <Popup
      content={<Lists
        assetsListUI={assetsListUI}
        addNewAssetList={addNewAssetList}
        lists={lists} />}
      trigger={trigger}
      position='bottom center'
      on='click'
    />
  )
}

const mapStateToProps = state => {
  return {
    assetsListUI: state.assetsListUI,
  }
}

const mapDispatchToProps = dispatch => ({
  addNewAssetList: name => dispatch({
    type: actions.USER_ADD_NEW_ASSET_LIST,
    payload: name
  })
})

export default compose(
  connect(mapStateToProps, mapDispatchToProps),
  graphql(AssetsListGQL, {
    name: 'AssetsList',
    options: ({isLoggedIn}) => ({skip: !isLoggedIn}),
    props: ({AssetsList, ownProps}) => {
      const { fetchUserLists = [] } = AssetsList
      return {
        lists: fetchUserLists
      }
    }
  })
)(AssetsListPopup)
