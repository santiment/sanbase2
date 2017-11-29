const webpack = require('webpack')

module.exports = {
  webpack: (cfg) => {
    cfg.plugins.push(
      new webpack.DefinePlugin({
        'process.env.WEBSITE_URL': JSON.stringify(process.env.WEBSITE_URL),
        'process.env.NODE_ENV': JSON.stringify(process.env.NODE_ENV)
      })
    )

    return cfg
  }
}
