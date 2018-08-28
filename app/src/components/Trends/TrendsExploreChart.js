import React from 'react'

const mergeSources = sources =>
  Object.keys(sources)
    .slice(0, -1)
    .reduce((acc, source) => {
      for (const { datetime, mentionsCount } of sources[source]) {
        acc.set(datetime, mentionsCount + (acc.get(datetime) || 0))
      }
      return acc
    }, new Map())

const TrendsExploreChart = ({ sources }) => {
  console.log(sources && mergeSources(sources))
  return <div />
}

export default TrendsExploreChart
