import React from 'react'
import { Button } from 'semantic-ui-react'
import './Filters.css'

const FilterDivider = ({children}) => (
  <div className='cashflow-mobile-filters__divider'>
    {children}
  </div>
)

const Filters = ({
  onFilterChanged
}) => {
  return (
    <div className='cashflow-mobile-filters-overlay'>
      <div className='cashflow-mobile-filters'>
        <div className='cashflow-mobile-filters__header'>
          <Button basic >Clear</Button>
          <h4>Filters</h4>
          <Button onClick={() => onFilterChanged('check')} color='green'>Done</Button>
        </div>
        <FilterDivider>
          Sort by
        </FilterDivider>
        <div className='cashflow-mobile-filters__item'>
          <Button color='blue'>Marketcap</Button>
          <Button basic >Github Activity</Button>
        </div>
        <FilterDivider>
          Filter by
        </FilterDivider>
      </div>
    </div>
  )
}

export default Filters
