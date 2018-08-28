import React from 'react'

/*
telegram [{
        mentionsCount,
        datetime
      }x10]
professionalTradersChat [{
  mentionsCount,
  datetime
      }]
reddit [{
  mentionsCount,
  datetime
      }]
*/

const mergeSources = sources =>
  sources.reduce((acc, source) => {
    for (const { datetime, mentionsCount } of source) {
      acc.set(datetime, mentionsCount + (acc.get(datetime) || 0))
    }
  }, new Map())

const TrendsExploreChart = ({ sources }) => {
  console.log(mergeSources(sources))
  return <div />
}

export default TrendsExploreChart
