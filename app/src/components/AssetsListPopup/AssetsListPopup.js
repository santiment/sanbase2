import React from 'react'
import { graphql } from 'react-apollo'
import { compose } from 'recompose'
import { Popup, Button } from 'semantic-ui-react'
import { AssetsListGQL } from './AssetsListGQL'
import AssetsList from './AssetsList'

const POLLING_INTERVAL = 2000

const AddToListBtn = (
  <Button basic color='purple'>
    add to list
  </Button>
)

const AssetsListPopup = ({
  isLoggedIn,
  projectId,
  lists,
  assetsListUI,
  addNewAssetList,
  removeAssetList,
  trigger = AddToListBtn
}) => {
  return (
    <Popup
      content={<AssetsList projectId={projectId} lists={lists} />}
      trigger={trigger}
      position='bottom center'
      on='click'
    />
  )
}

export default compose(
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
