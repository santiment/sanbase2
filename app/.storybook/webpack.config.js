// const path = require('path')

// module.exports = {
//   module: {
//     rules: [
//       {
//         test: /\.css$/,
//         loaders: ['style-loader', 'css-loader'],
//         include: path.resolve(__dirname, '../src/')
//       },

//     ]
//   }
// }

const path = require('path')

module.exports = (baseConfig, env, defaultConfig) => {
  // Extend defaultConfig as you need.

  // For example, add typescript loader:
  defaultConfig.module.rules.push({
    test: /\.scss$/,
    loaders: ['style-loader', 'css-loader', 'sass-loader'],
    include: path.resolve(__dirname, '../src/')
  })
  // defaultConfig.resolve.extensions.push(".ts", ".tsx");

  return defaultConfig
}
