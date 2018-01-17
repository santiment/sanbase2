export const findIndexByDatetime = (labels, datetime) => {
  return labels.findIndex(label => {
    return label.isSame(datetime)
  })
}
