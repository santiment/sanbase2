import React from 'react'
import moment from 'moment'
import { Button, Popup, Input } from 'semantic-ui-react'
import { compose, withState } from 'recompose'
import copy from 'copy-to-clipboard'
import './ShareableBtn.css'

const enhance = compose(
  withState('isSaved', 'save', false),
  withState('sanbaseChartImg', 'renderSanbaseChartImg', null)
)

const ShareableBtn = enhance(
  ({
    ticker,
    shareableURL,
    sanbaseChartImg,
    renderSanbaseChartImg,
    save,
    isSaved = false
  }) => {
    if (window.navigator.share) {
      return (
        <Button
          onClick={() => {
            window.navigator.share({
              title: 'Sanbase',
              text: 'Check out the insight of crypto world in Sanbase.',
              url: shareableURL
            })
          }}
          positive
        >
          Share
        </Button>
      )
    }
    return (
      <Popup
        position='bottom right'
        size='large'
        trigger={
          <Button
            onClick={() => {
              const chartEl = document.getElementsByClassName(
                'chartjs-render-monitor'
              )[0]
              const img = chartEl ? chartEl.toDataURL('image/jpg') : null
              renderSanbaseChartImg(img)
            }}
            positive
          >
            Share <i className='fa fa-caret-down' />
          </Button>
        }
        on='click'
      >
        <div className='shareable-inner'>
          <div className='shareable-url'>
            <Input input={{ readOnly: true }} defaultValue={shareableURL} />
            {!isSaved && (
              <Button
                icon='clipboard'
                onClick={() => {
                  const result = copy(shareableURL)
                  setTimeout(() => {
                    save(false)
                  }, 1000)
                  save(result)
                }}
              />
            )}
            {isSaved && <div>Saved!</div>}
          </div>
          {sanbaseChartImg && (
            <div className='shareable-image'>
              <a
                download={`sanbase-chart-${ticker.toUpperCase()}-${moment().format()}.jpg`}
                href={sanbaseChartImg}
              >
                Download JPG
              </a>
            </div>
          )}
        </div>
      </Popup>
    )
  }
)

export default ShareableBtn
