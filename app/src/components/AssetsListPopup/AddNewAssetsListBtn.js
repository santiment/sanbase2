import React from 'react'
import PropTypes from 'prop-types'
import { Input } from 'semantic-ui-react'
import './AddNewWatchlistBtn.css'

const initialState = {
  newAssetsListTitle: ''
}

class AddNewAssetsList extends React.Component {
  state = initialState

  componentDidUpdate (prevProps) {
    if (
      this.props.assetsListUI.assetsListNewItemSuccess &&
      this.props.assetsListUI.assetsListNewItemSuccess !==
        prevProps.assetsListUI.assetsListNewItemSuccess
    ) {
      this.setState({ newAssetsListTitle: initialState.newAssetsListTitle })
    }
  }

  handleOnChange = (e, data) => {
    this.setState({ newAssetsListTitle: data.value })
  }

  handleAddNewAssetsList = () => {
    const name = this.state.newAssetsListTitle
    if (name && name.length > 0) {
      this.props.addNewAssetList({
        name: this.state.newAssetsListTitle.toLowerCase()
      })
    }
  }

  render () {
    return (
      <div className='create-new-watchlist-btn'>
        <Input
          disabled={this.props.assetsListUI.assetsListNewItemPending}
          value={this.state.newAssetsListTitle}
          action={{
            color: 'google plus',
            labelPosition: 'left',
            icon: 'plus',
            content: 'create',
            onClick: this.handleAddNewAssetsList
          }}
          onChange={this.handleOnChange}
          onKeyPress={(e, data) => {
            if (e.key === 'Enter') {
              this.handleAddNewAssetsList()
            }
          }}
          actionPosition='left'
        />
      </div>
    )
  }
}

AddNewAssetsList.propTypes = {
  addNewAssetList: PropTypes.func.isRequired
}

export default AddNewAssetsList
