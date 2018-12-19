import React from 'react'
import { storiesOf } from '@storybook/react'
import Search from './../src/components/UI/Search/Search'
import SearchWithSuggestions
  from './../src/components/UI/Search/SearchWithSuggestions/SearchWithSuggestions'
import ColorModeComparison from './ColorModeComparison'

storiesOf('Search', module)
  .add('Simple', () => (
    <div>
      <ColorModeComparison>
        <Search defaultValue={'Left icon'} />
        <Search iconPosition='right' defaultValue={'Right icon'} />
        <Search />
        <Search iconPosition='right' />
      </ColorModeComparison>
    </div>
  ))
  .add('Suggestions', () => (
    <div>
      <ColorModeComparison>
        <SearchWithSuggestions
          data={[
            'Bibox Token',
            'Bigbom',
            'Binance Coin',
            'BioCoin',
            'BitBay',
            'bitcoin'
          ]}
          suggestionContent={suggestion => suggestion}
          predicate={searchTerm => item =>
            item.toUpperCase().includes(searchTerm.toUpperCase())}
          maxSuggestions={5}
        />
      </ColorModeComparison>
    </div>
  ))
