import React from 'react'
import moment from 'moment'
import { storiesOf } from '@storybook/react'
import { action } from '@storybook/addon-actions'
import ProjectChart, { TimeFilter } from './../src/components/ProjectChart/ProjectChart'
import Panel from './../src/components/Panel'
import { Button, Message } from 'semantic-ui-react'
import 'semantic-ui-css/semantic.min.css'

const historyOneWeek = require('./history_1week.json')
const historyOneMonth = require('./history_1month.json')

storiesOf('ProjectChart', module)
  .add('with 1 week history with active DatePicker', () => (
    <Panel withoutHeader>
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
    </Panel>
  ))
  .add('with 1 month history', () => (
    <Panel withoutHeader>
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
    </Panel>
  ))
  .add('is loading', () => (
    <Panel withoutHeader>
      <ProjectChart
        setFilter={action('setFilter')}
        interval='1m'
        isLoading
        changeDate={action('changeDates')}
        startDate={moment('2017-11-28T00:00:00Z')}
        endDate={moment('2017-12-28T00:00:00Z')}
        showBTC={action('showBTC')}
        showUSD={action('showUSD')} />
    </Panel>
  ))
  .add('is error', () => (
    <Panel withoutHeader>
      <ProjectChart
        setFilter={action('setFilter')}
        isError
        changeDate={action('changeDates')}
        startDate={moment('2017-11-28T00:00:00Z')}
        endDate={moment('2017-12-28T00:00:00Z')}
        showBTC={action('showBTC')}
        showUSD={action('showUSD')} />
    </Panel>
  ))
  .add('is empty', () => (
    <Panel withoutHeader>
      <ProjectChart
        setFilter={action('setFilter')}
        isEmpty
        isLoading={false}
        changeDate={action('changeDates')}
        startDate={moment('2017-11-28T00:00:00Z')}
        endDate={moment('2017-12-28T00:00:00Z')}
        showBTC={action('showBTC')}
        showUSD={action('showUSD')} />
    </Panel>
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

storiesOf('Standards', module)
  .add('How to use standard components?', () => (
    <Panel>
      <p>We use react-semantic</p>
      <p>You can read more about usage in <a href='https://react.semantic-ui.com/'>documentation</a>
      </p>
    </Panel>
  ))
  .add('Panel default', () => (
    <Panel>
      <h1>This is a panel</h1>
    </Panel>
  ))
  .add('Buttons', () => (
    <div>
      <p>
        <a href='https://react.semantic-ui.com/elements/button'>documentation about buttons</a>
      </p>
      <Button>button</Button>
      <Button basic>basic button</Button>
      <Button basic color='red'>button with red color</Button>
    </div>
  ))
  .add('Messages', () => (
    <div>
      <p>
        <a href='https://react.semantic-ui.com/elements/messages'>documentation about messages</a>
      </p>
      <Message>Any message</Message>
      <Message negative>Negative message</Message>
    </div>
  ))
