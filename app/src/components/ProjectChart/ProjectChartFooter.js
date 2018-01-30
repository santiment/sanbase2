import React from 'react'
import cx from 'classnames'
import {
  Popup,
  Icon,
  Label,
  Loader,
  Checkbox
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
    {disabled && !error &&
      <Popup
        trigger={<div>{children}</div>}
        content="Looks like we don't have any data"
        position='bottom left'
      />}
    {!!error &&
      <Popup
        trigger={<div>{children}</div>}
        content='Looks like we have some problems with our server'
        position='bottom left'
    />}
    {!disabled && !error && children}
    {loading && <Loader active inline size='mini' />}
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

const ProjectChartFooter = (props) => (
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
      <FilterCategory
        className='filter-category-blockchain'
        settings={() => (
          <Popup
            position='top center'
            size='large'
            trigger={<Icon name='cogs' />} on='click'>
            <div className='blockchain-settings'>
              <Checkbox
                label={{ children: 'all' }}
                value='all'
                checked={props.blockchainFilter === 'all'}
                onChange={() => props.setBlockchainFilter('all')}
                radio />
              <Checkbox
                label={{ children: 'only outliers' }}
                checked={props.blockchainFilter === 'only'}
                onChange={() => props.setBlockchainFilter('only')}
                value='only'
                radio />
              <Checkbox
                label={{ children: 'without outliers' }}
                checked={props.blockchainFilter === 'rest'}
                onChange={() => props.setBlockchainFilter('rest')}
                value='rest'
                radio />
            </div>
          </Popup>
        )}
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
            content='Total amount of tokens that were transacted on the blockchain'
            position='top left'
          />
        </ToggleBtn>
      </FilterCategory>
      <FilterCategory name='Social'>
        <ToggleBtn
          loading={props.twitter.history.loading}
          disabled={props.twitter.history.items.length === 0}
          isToggled={props.isToggledTwitter &&
            props.twitter.history.items.length !== 0}
          toggle={props.toggleTwitter}>
          <Label circular className='twitterLabel' empty />
          Twitter
        </ToggleBtn>
      </FilterCategory>
    </div>
  </div>
)

export default ProjectChartFooter
