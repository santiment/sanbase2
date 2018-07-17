import React from 'react'
import moment from 'moment'
import PanelBlock from './../../components/PanelBlock'
import { millify } from './../../utils/formatting'

const SpentOverTime = ({ loading = true, project = {} }) => {
  return (
    <PanelBlock isLoading={loading} title='ETH Spent Over Time'>
      {!project.ethSpentOverTime && "We don't have any data now"}
      <div className='analytics-trend-chart'>
        {project.ethSpentOverTime &&
          project.ethSpentOverTime
            .filter(item => item.ethSpent !== 0)
            .map((_, id, arr) => arr[arr.length - 1 - id])
            .filter((_, index) => index < 10)
            .map((transaction, index) => (
              <div
                key={index}
                style={{ display: 'flex', justifyContent: 'space-between' }}
              >
                <div>
                  ETH {millify(parseFloat(transaction.ethSpent).toFixed(2))}
                </div>
                <div>{moment(transaction.datetime).fromNow()}</div>
              </div>
            ))}
      </div>
    </PanelBlock>
  )
}

export default SpentOverTime
