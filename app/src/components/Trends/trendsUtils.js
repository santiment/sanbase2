export const mergeDataSourcesForChart = ({ __typename, ...sources }) =>
  Object.keys(sources).reduce((acc, source) => {
    for (const { datetime, mentionsCount } of sources[source]) {
      acc.set(datetime, mentionsCount + (acc.get(datetime) || 0))
    }
    return acc
  }, new Map())
