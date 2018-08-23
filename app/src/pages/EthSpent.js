import React from 'react'
import Assets from './../pages/assets/Assets'
import EthSpentTable from './../components/EthSpentTable'

const EthSpent = () => {
  return (
    <div>
      <Assets
        type='erc20'
        render={Assets => (
          <div>
            <EthSpentTable {...Assets} />
          </div>
        )}
      />
    </div>
  )
}

export default EthSpent
