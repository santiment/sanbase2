/* eslint-env jasmine */
import puppeteer from 'puppeteer'

let browser = null
let page = null
let mobilePage = null

beforeAll(async() => {
  jasmine.DEFAULT_TIMEOUT_INTERVAL = 30000
  const launchOptions = process.env.CI
    ? {}
    : {headless: true, slowMo: 5, ignoreHTTPSErrors: true}

  // Workaround till https://github.com/GoogleChrome/puppeteer/issues/290 is fixed
  if (process.env.LAUNCH_CHROME_NO_SANDBOX) {
    console.warn('Launching Chrome with "--no-sandbox" option. ' +
      'This is not recommended due to security reasons!')
    Object.assign(launchOptions, { args: ['--no-sandbox'] })
  }

  browser = await puppeteer.launch(launchOptions)
  page = await browser.newPage()
  await page.setViewport({
    width: 1366,
    height: 768
  })
  mobilePage = await browser.newPage()
  await mobilePage.setViewport({
    width: 360,
    height: 640,
    isMobile: true
  })
})

afterAll(async () => {
  await browser.close()
})

describe('Detailed page', () => {
  it('it should loads correctly', async () => {
    await page.goto('http://localhost:3000/projects/ppt')
    await mobilePage.goto('http://localhost:3000/projects/ppt')
    await page.waitForSelector('.datailed-project-description')
    await mobilePage.waitForSelector('.datailed-project-description')
    await page.screenshot({path: '.screenshots/ppt-detailed-page-desktop.png'})
    await mobilePage.screenshot({path: '.screenshots/ppt-detailed-page-mobile.png'})
  })

  it('Search should works correctly', async () => {
    await page.goto('http://localhost:3000/projects/eos')
    await page.waitForSelector('.search-data-loaded')
    await page.focus('#search-input')
    await page.keyboard.type('san')
    await page.waitForSelector('#search-result')
    const searchResult = await page.evaluate(() => {
      const resultDiv = document.querySelector('#search-result')
      return resultDiv.innerText || null
    })
    expect(searchResult).toBe('Santiment Network Token (SAN)')
    await page.screenshot({path: '.screenshots/eos-detailed-page-desktop.png'})
    await page.keyboard.press('Enter')
    await page.waitFor(4000)
    await page.screenshot({path: '.screenshots/san-detailed-page-desktop.png'})
  })
})
