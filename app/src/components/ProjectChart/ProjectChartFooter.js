import React from 'react'
import cx from 'classnames'
import {
  Popup,
  Icon,
  Label,
  Loader
} from 'semantic-ui-react'
import './ProjectChartFooter.css'

export const ToggleBtn = ({
  loading,
  error = false,
  disabled,
  isToggled,
  toggle,
  children
}) => (
  <div className={cx({
    'toggleBtn': true,
    'activated': isToggled,
    'disabled': disabled || loading
  })}
    onClick={() => !disabled && !loading && toggle(!isToggled)}>
    {!loading && disabled && !error &&
      <Popup
        trigger={<div>{children}</div>}
        content="We don't have the data for this project"
        inverted
        position='bottom left'
      />}
    {!loading && !!error &&
      <Popup
        trigger={<div>{children}</div>}
        inverted
        content='There was a problem fetching the data. Please, try again or come back later...'
        position='bottom left'
    />}
    {!loading && !disabled && !error && children}
    {loading && <div className='toggleBtn--loading'>{children}</div>}
    {loading && <div className='toggleBtn-loader'>
      <Loader active inverted={isToggled} size='mini' />
    </div>}
  </div>
)

const FilterCategory = ({
  children,
  name,
  className = '',
  settings
}) => (
  <div className={'filter-category ' + className}>
    <h5 className='filter-category-title'>
      {name.toUpperCase()}&nbsp;
      {settings && settings()}
    </h5>
    <div className='filter-category-body'>
      {children}
    </div>
  </div>
)
//
const ProjectChartFooter = ({
  historyTwitterData = {
    loading: false,
    items: []
  },
  ...props
}) => (
  <div className='chart-footer'>
    <div className='chart-footer-filters'>
      <FilterCategory name='Financial'>
        <ToggleBtn
          isToggled={props.isToggledMarketCap}
          toggle={props.toggleMarketcap}>
          <Label circular className='marketcapLabel' empty />
          Marketcap
        </ToggleBtn>
        <ToggleBtn
          isToggled={props.isToggledVolume}
          toggle={props.toggleVolume}>
          <Label circular className='volumeLabel' empty />
          Volume
        </ToggleBtn>
      </FilterCategory>
      <FilterCategory name='Development'>
        <ToggleBtn
          loading={props.github.history.loading}
          disabled={props.github.history.items.length === 0}
          isToggled={props.isToggledGithubActivity &&
            props.github.history.items.length !== 0}
          toggle={props.toggleGithubActivity}>
          <Label circular className='githubActivityLabel' empty />
          Github Activity
        </ToggleBtn>
      </FilterCategory>
      {props.isERC20 &&
      <FilterCategory
        className='filter-category-blockchain'
        name='Blockchain'>
        <ToggleBtn
          loading={props.burnRate.loading}
          error={props.burnRate.error}
          disabled={props.burnRate.items.length === 0 || props.burnRate.error}
          isToggled={props.isToggledBurnRate &&
            props.burnRate.items.length !== 0}
          toggle={props.toggleBurnRate}>
          <Label circular className='burnRateLabel' empty />
          Burn Rate
          <Popup
            trigger={<Icon name='info circle' />}
            inverted
            content='Token Burn Rate shows the amount of movement
            of tokens between addresses. One use for this metric is
            to spot large amounts of tokens moving after sitting for long periods of time'
            position='top left'
          />
        </ToggleBtn>
        <ToggleBtn
          loading={props.transactionVolume.loading}
          error={props.transactionVolume.error}
          disabled={props.transactionVolume.items.length === 0 ||
            props.transactionVolume.error}
          isToggled={props.isToggledTransactionVolume &&
            props.transactionVolume.items.length !== 0}
          toggle={props.toggleTransactionVolume}>
          <Label circular className='transactionVolumeLabel' empty />
          Transaction Volume
          <Popup
            trigger={<Icon name='info circle' />}
            inverted
            content='Total amount of tokens that were transacted on the blockchain'
            position='top left'
          />
        </ToggleBtn>
        <ToggleBtn
          loading={props.dailyActiveAddresses.loading}
          disabled={props.dailyActiveAddresses.items.length === 0}
          isToggled={props.isToggledDailyActiveAddresses &&
            props.dailyActiveAddresses.items.length !== 0}
          toggle={props.toggleActiveAddresses}>
          <Label circular className='twitterLabel' empty />
          Daily Active Addresses
        </ToggleBtn>
      </FilterCategory>}
      <FilterCategory name='Social'>
        <ToggleBtn
          loading={historyTwitterData.loading}
          disabled={historyTwitterData.items.length === 0}
          isToggled={props.isToggledTwitter &&
            historyTwitterData.items.length !== 0}
          toggle={props.toggleTwitter}>
          <Label circular className='twitterLabel' empty />
          Twitter
        </ToggleBtn>
      </FilterCategory>
      {(props.isERC20 || props.ticker === 'ETH') &&
      <FilterCategory name='Ethereum'>
        <ToggleBtn
          loading={props.ethSpentOverTime.loading}
          disabled={props.ethSpentOverTime.items.length === 0}
          isToggled={props.isToggledEthSpentOverTime &&
            props.ethSpentOverTime.items.length !== 0}
          toggle={props.toggleEthSpentOverTime}>
          <Label circular className='ethSpentOverTimeLabel' empty />
          ETH spent over time
          <Popup
            trigger={<Icon name='info circle' />}
            inverted
            content='How much ETH has moved out of team wallets over time.
            While not tracked all the way to exchanges, this metric may suggest pottential
            selling activity.'
            position='top left'
          />
        </ToggleBtn>
      </FilterCategory>}
    </div>
  </div>
)

export default ProjectChartFooter
