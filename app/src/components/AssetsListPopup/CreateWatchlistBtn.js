import React from 'react'
import PropTypes from 'prop-types'
import { Input } from 'semantic-ui-react'
import './CreateWatchlistBtn.css'

const initialState = {
  newAssetsListTitle: ''
}

class CreateWatchlistBtn extends React.Component {
  state = initialState

  componentDidUpdate (prevProps) {
    if (
      this.props.assetsListUI.newItemSuccess !==
      prevProps.assetsListUI.newItemSuccess
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
          disabled={this.props.assetsListUI.newItemPending}
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

CreateWatchlistBtn.propTypes = {
  addNewAssetList: PropTypes.func.isRequired
}

export default CreateWatchlistBtn
