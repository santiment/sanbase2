import React from 'react'
import Assets from './../pages/Assets/Assets'
import EthSpentTable from './../components/EthSpentTable'

const EthSpent = () => (
  <div>
    <Assets type='erc20' render={Assets => <EthSpentTable {...Assets} />} />
  </div>
)

export default EthSpent
