import React from 'react'
import { Link } from 'react-router-dom'
import cx from 'classnames'
import {
  Popup,
  Icon,
  Label,
  Loader,
  Message
} from 'semantic-ui-react'
import './ProjectChartFooter.css'

export const ToggleBtn = ({
  loading,
  error = false,
  disabled,
  isToggled,
  // this button for premium timeseries
  premium = false,
  // current user has premium
  hasPremium = false,
  toggle,
  children
}) => (
  <div className={cx({
    'toggleBtn': true,
    'activated': isToggled,
    'premium-wall-button': premium,
    'disabled': disabled || loading
  })}
    onClick={() => !disabled && !loading && toggle(!isToggled)}>
    {!loading && disabled && !error &&
      <Popup
        trigger={<div>{children}</div>}
        content={premium && !hasPremium
          ? 'You need to have more than 1000 tokens to see that data.'
          : "We don't have the data for this project."}
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
  Insights = {
    loading: false,
    error: false,
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
        {!props.isToggledBTC &&
        (props.project.icoPrice || undefined) &&
        <ToggleBtn
          isToggled={props.isToggledICOPrice}
          toggle={props.toggleICOPrice}>
          <Label circular className='icoPriceLabel' empty />
          ICO Price (USD)
        </ToggleBtn>}
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
          <Popup
            trigger={<Icon name='info circle' />}
            inverted
            content="Metric based on number of Github 'events' including
              issue interactions, pull requests, comments,
              and wiki edits, plus the number of public
              repositories a project is maintaining"
            position='top left'
          />
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
          loading={props.twitterHistory.loading}
          disabled={props.twitterHistory.items.length === 0}
          isToggled={props.isToggledTwitter &&
            props.twitterHistory.items.length !== 0}
          toggle={props.toggleTwitter}>
          <Label circular className='twitterLabel' empty />
          Twitter {!props.twitterData.loading && !props.twitterData.error &&
            `| ${props.twitterData.followersCount}`}
        </ToggleBtn>
        <ToggleBtn
          loading={props.emojisSentiment.loading}
          premium
          hasPremium={props.isPremium}
          disabled={props.emojisSentiment.items.length === 0}
          isToggled={props.isToggledEmojisSentiment &&
            props.emojisSentiment.items.length !== 0}
          toggle={props.toggleEmojisSentiment}>
          <Label circular className='sentimentLabel' empty />
          Sentiment
        </ToggleBtn>
        {!Insights.loading &&
          Insights.items.length > 0 &&
          <Message info floating size='tiny' >
            <Message.Header>
              Community Insights
            </Message.Header>
            <p style={{lineHeight: '1.25'}}>
              Our community made Insights about this project.
            </p>
            <p>
              You can learn something new.
            </p>
            <Link to={`/insights/tags/${props.project.ticker}`}>{Insights.items.length}&nbsp;
              Insight{Insights.items.length > 1 && 's'} about {props.project.ticker}</Link>
          </Message>
        }
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
        <ToggleBtn
          loading={props.ethPrice.history.loading}
          disabled={props.ethPrice.history.items.length === 0}
          isToggled={props.isToggledEthPrice &&
            props.ethPrice.history.items.length !== 0}
          toggle={props.toggleEthPrice}>
          Compare with ETH price
        </ToggleBtn>
      </FilterCategory>}
    </div>
  </div>
)

export default ProjectChartFooter
