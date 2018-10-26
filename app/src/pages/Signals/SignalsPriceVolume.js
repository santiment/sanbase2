import React, { Component } from 'react'
import SignalsChart from '../../components/Signals/SignalsChart'
import SignalsSearch from '../../components/Signals/SignalsSearch'
import GetHistoryPrice from './GetHistoryPrice'
import Selector from '../../components/Selector/Selector'
import Panel from '../../components/Panel'
import { getTimeFromFromString } from '../../utils/utils'
import styles from './SignalsPriceVolume.module.css'

console.log()
class SignalsPriceVolume extends Component {
  state = {
    from: '6m'
  }

  setFromValue = from => {
    this.setState({
      from
    })
  }

  render () {
    const {
      match: {
        params: { slug }
      }
    } = this.props
    const { from } = this.state
    return (
      <div className={styles.wrapper}>
        <Panel>
          <SignalsSearch slug={slug} />
          <div className={styles.header}>
            <Selector
              options={['1w', '1m', '3m', '6m']}
              onSelectOption={this.setFromValue}
              defaultSelected={from}
            />
          </div>
          <GetHistoryPrice slug={slug} from={getTimeFromFromString(from)}>
            {data => (
              <SignalsChart chartData={data ? data.historyPrice : null} />
            )}
          </GetHistoryPrice>
        </Panel>
      </div>
    )
  }
}

export default SignalsPriceVolume
