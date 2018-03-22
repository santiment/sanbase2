import React from 'react'
import PanelBlock from './../../components/PanelBlock'

const Hidden = () => ('')

const EthereumBlock = ({
  project = {},
  loading = true
}) => {
  return (
    <Hidden>
      <PanelBlock
        isLoading={loading}
        title='Ethereum overview'>
        <div>ETH</div>
      </PanelBlock>
    </Hidden>
  )
}

export default EthereumBlock
