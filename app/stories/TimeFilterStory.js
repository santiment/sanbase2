import React from 'react'
import { storiesOf } from '@storybook/react'
import TimeFilter from './../src/components/TimeFilter'

class CompWithTimeFilter extends React.Component {
  state = {
    selected: this.props.selected || '1w'
  }

  setFilter = option => {
    this.setState({selected: option})
  }

  render() {
    const { children } = this.props
    const { selected } = this.state
    const setFilter = this.setFilter
    return this.props.render({setFilter, selected})
  }
}

const stories = storiesOf('TimeFilter', module)

stories.add('TimeFilter', () => (
  <CompWithTimeFilter render={({setFilter, selected}) => (
    <TimeFilter setFilter={setFilter} selected={selected} />
  )} />
))

stories.add('TimeFilter: disabled', () => (
  <TimeFilter disabled />
))
