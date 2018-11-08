const path = require('path')
require('imports-loader')

// Extend default storybook config is based on
// https://github.com/m-allanson/gatsby-storybook-css-modules/blob/master/storybook/webpack.config.js
//
// It supports scss and css modules (*.module.css)

module.exports = (baseConfig, env, defaultConfig) => {
  defaultConfig.module.rules.push({
    test: /\.scss$/,
    loaders: [
      'style-loader',
      'css-loader?modules&namedExport&sass&localIdentName=[path]-[local]-[hash:base64:5]',
      'sass-loader'
    ],
    include: path.resolve(__dirname, '../src/')
  })

  // Find Storybook's default CSS processing rule
  const cssLoaderIndex = defaultConfig.module.rules.findIndex(
    rule => rule.test.source === `\\.css$`
  )

  if (!Number.isInteger(cssLoaderIndex)) {
    throw new Error("Could not find Storybook's CSS loader")
  }

  // Exclude CSS Modules from Storybook's standard CSS processing
  defaultConfig.module.rules[cssLoaderIndex].exclude = /\.module\.css$/

  defaultConfig.module.rules.push({
    test: /\.module\.css$/,
    use: [
      { loader: `style-loader` },
      {
        loader: 'css-loader',
        options: {
          modules: true,
          importLoaders: 1,
          localIdentName: '[path]-[local]-[hash:base64:5]'
        }
      }
    ],
    include: path.resolve(__dirname, '../src')
  })

  return defaultConfig
}
