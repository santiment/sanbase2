import React from 'react'
import moment from 'moment'
import { storiesOf } from '@storybook/react'
import { action } from '@storybook/addon-actions'
import ProjectChart, { TimeFilter } from './../src/components/ProjectChart/ProjectChart'

const historyOneWeek = require('./history_1week.json')
const historyOneMonth = require('./history_1month.json')

storiesOf('ProjectChart', module)
  .add('with 1 week history', () => (
    <ProjectChart
      setFilter={action('setFilter')}
      setSelected={action('setSelected')}
      history={historyOneWeek}
      errorMessage=''
      interval='1w'
      isEmpty={false}
      isError={false}
      isLoading={false}
      isToggledBTC={false}
      isToggledMatketCap={false}
      focusedInput='startDate'
      selected={null}
      changeDate={action('changeDates')}
      startDate={moment('2017-12-21T00:00:00Z')}
      endDate={moment('2017-12-28T00:00:00Z')}
      showBTC={action('showBTC')}
      showUSD={action('showUSD')} />
  ))
  .add('with 1 month history', () => (
    <ProjectChart
      setFilter={action('setFilter')}
      setSelected={action('setSelected')}
      history={historyOneMonth}
      errorMessage=''
      interval='1m'
      isEmpty={false}
      isError={false}
      isLoading={false}
      isToggledBTC={false}
      isToggledMatketCap={false}
      selected={null}
      changeDate={action('changeDates')}
      startDate={moment('2017-11-28T00:00:00Z')}
      endDate={moment('2017-12-28T00:00:00Z')}
      showBTC={action('showBTC')}
      showUSD={action('showUSD')} />
  ))

storiesOf('PC - TimeFilter', module)
  .add('default', () => (
    <TimeFilter
      setFilter={action('setFilter')}
      disabled={false}
       />
  ))
  .add('picked 1w', () => (
    <TimeFilter
      setFilter={action('setFilter')}
      interval='1w'
      disabled={false}
       />
  ))
  .add('disabled', () => (
    <TimeFilter disabled />
  ))
