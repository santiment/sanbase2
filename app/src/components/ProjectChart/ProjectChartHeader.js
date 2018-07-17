import React from 'react'
import moment from 'moment'
import { Merge } from 'animate-components'
import { fadeIn, slideUp } from 'animate-keyframes'
import { withState, compose, lifecycle } from 'recompose'
import { DateRangePicker } from 'react-dates'
import { formatNumber } from './../../utils/formatting'
import ShareableBtn from './ShareableBtn'
import './ProjectChartHeader.css'

export const TimeFilterItem = ({
  disabled,
  interval,
  setFilter,
  value = '1d'
}) => {
  let cls = interval === value ? 'activated' : ''
  if (disabled) {
    cls += ' disabled'
  }
  return (
    <div className={cls} onClick={() => !disabled && setFilter(value)}>
      {value}
    </div>
  )
}

export const TimeFilter = props => (
  <div className='time-filter'>
    <TimeFilterItem value={'1d'} {...props} />
    <TimeFilterItem value={'1w'} {...props} />
    <TimeFilterItem value={'2w'} {...props} />
    <TimeFilterItem value={'1m'} {...props} />
    <TimeFilterItem value={'3m'} {...props} />
    <TimeFilterItem value={'all'} {...props} />
  </div>
)

export const CurrencyFilter = ({ ticker, isToggledBTC, toggleBTC }) => (
  <div className='currency-filter'>
    {ticker !== 'BTC' && (
      <div
        className={isToggledBTC ? 'activated' : ''}
        onClick={() => toggleBTC(true)}
      >
        BTC
      </div>
    )}
    <div
      className={!isToggledBTC ? 'activated' : ''}
      onClick={() => toggleBTC(false)}
    >
      USD
    </div>
  </div>
)

const HiddenElements = () => ''

const ProjectChartHeader = ({
  from,
  to,
  focusedInput,
  onFocusChange,
  setFromTo,
  isDesktop = true,
  selected,
  history,
  toggleBTC,
  isToggledBTC,
  interval,
  setFilter,
  shareableURL,
  sanbaseChart,
  ticker,
  changeFromTo,
  dates,
  isERC20
}) => {
  return (
    <div className='chart-header'>
      <div className='chart-datetime-settings'>
        <TimeFilter interval={interval} setFilter={setFilter} />
        <HiddenElements>
          {isDesktop && (
            <DateRangePicker
              small
              startDateId='startDate'
              endDateId='endDate'
              readOnly
              startDate={moment(dates.from)}
              endDate={moment(dates.to)}
              onDatesChange={({ startDate, endDate }) => {
                changeFromTo({
                  from: moment(startDate)
                    .utc()
                    .format(),
                  to: moment(endDate)
                    .utc()
                    .format()
                })
              }}
              focusedInput={focusedInput}
              onFocusChange={focusedInput => {
                if (!focusedInput) {
                  setFromTo(moment(dates.from), moment(dates.to))
                }
                onFocusChange(focusedInput)
              }}
              displayFormat={() => moment.localeData().longDateFormat('L')}
              hideKeyboardShortcutsPanel
              isOutsideRange={day => {
                const today = moment().endOf('day')
                return day > today
              }}
            />
          )}
        </HiddenElements>
      </div>
      <div className='chart-header-actions'>
        <CurrencyFilter
          ticker={ticker}
          isToggledBTC={isToggledBTC}
          toggleBTC={toggleBTC}
        />
        <ShareableBtn
          ticker={ticker}
          sanbaseChart={sanbaseChart}
          shareableURL={shareableURL}
        />
      </div>
      {!isDesktop &&
        selected && [
          <div key='selected-datetime' className='selected-value'>
            {selected && (
              <Merge
                one={{
                  name: fadeIn,
                  duration: '0.3s',
                  timingFunction: 'ease-in'
                }}
                two={{
                  name: slideUp,
                  duration: '0.5s',
                  timingFunction: 'ease-out'
                }}
                as='div'
              >
                <span className='selected-value-datetime'>
                  {moment(history[selected].datetime)
                    .utc()
                    .format('MMMM DD, YYYY')}
                </span>
              </Merge>
            )}
          </div>,
          <div key='selected-value' className='selected-value'>
            {selected && (
              <Merge
                one={{
                  name: fadeIn,
                  duration: '0.3s',
                  timingFunction: 'ease-in'
                }}
                two={{
                  name: slideUp,
                  duration: '0.5s',
                  timingFunction: 'ease-out'
                }}
                as='div'
              >
                <span className='selected-value-data'>
                  Price:
                  {formatNumber(history[selected].priceUsd, {
                    currency: 'USD'
                  })}
                </span>
                <span className='selected-value-data'>
                  Volume:
                  {formatNumber(history[selected].volume, { currency: 'USD' })}
                </span>
              </Merge>
            )}
          </div>
        ]}
    </div>
  )
}

export default compose(
  withState('dates', 'changeFromTo', {
    from: undefined,
    to: undefined
  }),
  lifecycle({
    componentWillReceiveProps (nextProps) {
      if (
        this.props.from !== nextProps.from ||
        this.props.to !== nextProps.to
      ) {
        this.props.changeFromTo({
          from: nextProps.from,
          to: nextProps.to
        })
      }
    }
  })
)(ProjectChartHeader)
