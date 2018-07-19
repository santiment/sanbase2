import React from 'react'
import PropTypes from 'prop-types'
import { Input } from 'semantic-ui-react'

const initialState = {
  newAssetsListTitle: ''
}

class AddNewAssetsList extends React.Component {
  state = initialState

  componentDidUpdate(prevProps) {
    if (this.props.assetsListUI.assetsListNewItemSuccess !==
      prevProps.assetsListUI.assetsListNewItemSuccess
    ) {
      console.log('check')
      this.setState({newAssetsListTitle: initialState.newAssetsListTitle})
    }
  }

  handleOnChange = (e, data) => {
    this.setState({newAssetsListTitle: data.value})
  }

  handleAddNewAssetsList = () => {
    const name = this.state.newAssetsListTitle
    if (name && name.length > 0) {
      this.props.addNewAssetList({ name: this.state.newAssetsListTitle })
    }
  }

  render () {
    return (
      <Input
        disabled={this.props.assetsListUI.assetsListNewItemPending}
        action={{
          color: 'google plus',
          labelPosition: 'left',
          icon: 'plus',
          content: 'Add new',
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
    )
  }
}

AddNewAssetsList.propTypes = {
  addNewAssetList: PropTypes.func.isRequired
}

export default AddNewAssetsList
