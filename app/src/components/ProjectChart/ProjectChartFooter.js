import React from 'react'
import cx from 'classnames'
import { Popup, Icon, Label, Loader } from 'semantic-ui-react'
import './ProjectChartFooter.css'

export const ToggleBtn = ({
  loading,
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
    {disabled
      ? <Popup
        trigger={<div>{children}</div>}
        content="Looks like we don't have any data"
        position='top center'
      />
    : children}
    {loading && <Loader active inline size='mini' />}
  </div>
)

const FilterCategory = ({children, name}) => (
  <div className='filter-category'>
    <h5 className='filter-category-title'>{name.toUpperCase()}</h5>
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
      <FilterCategory name='Blockchain'>
        <ToggleBtn
          loading={props.burnRate.loading}
          disabled={props.burnRate.items.length === 0}
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
          disabled={props.transactionVolume.items.length === 0}
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
