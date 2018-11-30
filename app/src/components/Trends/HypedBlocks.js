import React, { Component } from 'react'
import HypedWordsBlock from './HypedWordsBlock'
import Selector from './../../components/Selector/Selector'
import styles from './HypedBlocks.module.css'

const DesktopList = ({ items }) => (
  <div className={styles.HypedBlocks}>
    {items.map((hypedTrend, index) => (
      <HypedWordsBlock
        key={index}
        latest={index === items.length - 1}
        compiled={hypedTrend.datetime}
        trends={hypedTrend.topWords}
      />
    ))}
  </div>
)

const allCases = ['Current trends', 'Previous', 'Older']

class HypedBlocks extends Component {
  state = {
    selected: allCases[0]
  }

  render () {
    const { isLoading, items, isDesktop } = this.props
    const { selected } = this.state
    if (isLoading) {
      return 'Loading...'
    }
    if (isDesktop) {
      return <DesktopList items={items} />
    }
    const reversedItems = [...items].reverse()
    const selectedIndex = allCases.findIndex(el => el === selected)
    const hypedTrend = reversedItems[selectedIndex] || {}
    return (
      <div>
        <Selector
          className={styles.selector}
          options={allCases}
          onSelectOption={this.handleSelect}
          defaultSelected={selected}
        />
        <HypedWordsBlock
          compiled={hypedTrend.datetime}
          trends={hypedTrend.topWords}
        />
      </div>
    )
  }

  handleSelect = selected => {
    this.setState({ selected })
  }
}

export default HypedBlocks
